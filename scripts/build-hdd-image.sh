#!/usr/bin/env bash
# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Builds out/<distro>-ps4.img: an ext4 image of the rootfs for booting from
# the PS4's internal drive. Upload it with the PS4's FTP (GoldHEN) to
#   /user/home/<name>-ps4.img
# The PS4 then owns and fully allocates the file; the initramfs maps its blocks
# and never writes the PS4 filesystem itself.
#
# Usage: scripts/build-hdd-image.sh [SIZE]     (default 16G; ext4 sizes like 12G)
source "$(dirname "$0")/common.sh"

SIZE="${1:-16G}"
[ -f "$OUT/$ROOTFS_TAR" ] || die "Missing $OUT/$ROOTFS_TAR - run 'make rootfs' first"
ensure_builder

log "Building $OUT/$DISTRO-ps4.img ($SIZE ext4) from $ROOTFS_TAR"
rm -f "$OUT/$DISTRO-ps4.img"
docker run --rm \
    -v "$OUT:/out" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e SIZE="$SIZE" \
    -e ROOTFS_TAR="$ROOTFS_TAR" -e ROOT_LABEL="$ROOT_LABEL" -e DISTRO="$DISTRO" \
    "$BUILDER_IMAGE" bash -euo pipefail -c '
        r=/work/root
        mkdir -p "$r"
        tar -xpJf /out/$ROOTFS_TAR -C "$r" --numeric-owner
        # Mounted by the initramfs, not from fstab.
        mke2fs -q -t ext4 -L $ROOT_LABEL -m 1 -d "$r" /out/$DISTRO-ps4.img "$SIZE"
        e2fsck -fn /out/$DISTRO-ps4.img > /dev/null
        chown "$HOST_UID:$HOST_GID" /out/$DISTRO-ps4.img
    '
ok "Image: $OUT/$DISTRO-ps4.img ($(du -h --apparent-size "$OUT/$DISTRO-ps4.img" | cut -f1), $(du -h "$OUT/$DISTRO-ps4.img" | cut -f1) used)"
