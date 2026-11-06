#!/usr/bin/env bash
# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Writes a bootable USB drive for one distro. ERASES THE WHOLE DRIVE.
#   Partition 1: FAT32 "PS4BOOT"  - bzImage + initramfs.cpio.gz (read by the PS4 Linux payload)
#   Partition 2: ext4  "<NAME>-PS4" - the distro root filesystem
# Usage: sudo scripts/make-usb.sh /dev/sdX [ROOT_SIZE]
#   ROOT_SIZE: size of the root partition, e.g. 8G (default: rest of the drive)
source "$(dirname "$0")/common.sh"

DEV="${1:-}"
ROOT_SIZE="${2:-}"
[ "$(id -u)" = 0 ] || die "Run as root: sudo $0 /dev/sdX"
[ -n "$DEV" ] || die "Usage: sudo $0 /dev/sdX   (see 'lsblk -o NAME,SIZE,TRAN,MODEL')"
[ -b "$DEV" ] || die "$DEV is not a block device"
[ "$(lsblk -dno TYPE "$DEV")" = disk ] || die "$DEV is a partition; give the whole disk (e.g. /dev/sdb)"
[ "$(lsblk -dno TRAN "$DEV")" = usb ] || die "$DEV is not a USB drive; refusing"
if lsblk -nro MOUNTPOINTS "$DEV" | grep -q .; then
    die "$DEV has mounted partitions; unmount them first"
fi
for f in bzImage initramfs.cpio.gz $ROOTFS_TAR; do
    [ -f "$OUT/$f" ] || die "Missing $OUT/$f - run 'make' first"
done
for t in sfdisk mkfs.vfat mkfs.ext4 partprobe; do
    command -v "$t" >/dev/null || die "Missing tool: $t (apt install dosfstools e2fsprogs parted fdisk)"
done

lsblk -o NAME,SIZE,MODEL,TRAN "$DEV"
echo
read -r -p "ALL DATA on $DEV will be destroyed. Type the device path again to continue: " answer
[ "$answer" = "$DEV" ] || die "Aborted"

part() { case "$DEV" in *[0-9]) echo "${DEV}p$1" ;; *) echo "${DEV}$1" ;; esac; }

log "Partitioning $DEV (MBR: 512M FAT32 + ext4 ${ROOT_SIZE:-to end of drive})"
wipefs -aq "$DEV"
sfdisk -q "$DEV" <<EOF
label: dos
,512M,c,*
,${ROOT_SIZE},83
EOF
partprobe "$DEV"
udevadm settle
wipefs -aq "$(part 1)" "$(part 2)"

mkfs.vfat -F 32 -n "$BOOT_LABEL" "$(part 1)" >/dev/null
mkfs.ext4 -q -F -L "$ROOT_LABEL" "$(part 2)"
sync
blockdev --flushbufs "$DEV"
# Formatting partition 2 must not change partition 1. If it does, the drive
# maps high addresses onto low ones (fake capacity) or is failing.
[ "$(blkid -p -o value -s TYPE "$(part 1)")" = vfat ] \
    || die "Partition 1 lost its FAT32 format after partition 2 was formatted: this drive is failing or has less real capacity than it reports. Retry with a smaller ROOT_SIZE (e.g. 8G) or use another drive."

mnt="$(mktemp -d)"
trap 'umount -q "$mnt/boot" "$mnt/root" 2>/dev/null; rm -rf "$mnt"' EXIT
mkdir -p "$mnt/boot" "$mnt/root"
mount "$(part 1)" "$mnt/boot"
mount "$(part 2)" "$mnt/root"

log "Copying kernel and initramfs"
cp "$OUT/bzImage" "$OUT/initramfs.cpio.gz" "$mnt/boot/"

log "Extracting the $NAME root filesystem (several minutes)"
tar -xpJf "$OUT/$ROOTFS_TAR" -C "$mnt/root" --numeric-owner

log "Flushing writes to the drive"
sync
ok "USB ready. Plug it into the PS4's rightmost USB port and launch the Linux payload."
