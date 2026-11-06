#!/usr/bin/env bash
# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Builds out/bzImage plus kernel modules and firmware for the rootfs.
# The PS4 kernel tree is fetched at build time (GPLv2), never vendored here.
source "$(dirname "$0")/common.sh"

SRC="$BUILD/ps4-linux"

if [ ! -d "$SRC/.git" ]; then
    log "Cloning $KERNEL_REPO ($KERNEL_BRANCH)"
    git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$SRC"
else
    log "Updating kernel tree"
    git -C "$SRC" fetch --depth 1 origin "$KERNEL_BRANCH"
    git -C "$SRC" checkout -q FETCH_HEAD
fi
[ -f "$SRC/config" ] || die "PS4 kernel tree has no 'config' file; upstream layout changed"

# Our own kernel fixes, applied once (skipped if already applied).
for p in "$ROOT"/patches/kernel/*.patch; do
    [ -e "$p" ] || continue
    if git -C "$SRC" apply --reverse --check "$p" 2>/dev/null; then
        continue
    fi
    log "Applying $(basename "$p")"
    git -C "$SRC" apply "$p" || die "Patch $(basename "$p") does not apply to this kernel tree"
done

ensure_builder
rm -rf "$BUILD/modules"

log "Compiling kernel (this takes a while)"
docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$BUILD:/build" \
    -v "$ROOT/config:/cfg:ro" \
    -w /build/ps4-linux \
    "$BUILDER_IMAGE" bash -euo pipefail -c '
        cp config .config
        scripts/kconfig/merge_config.sh -m .config /cfg/ps4.config
        make LLVM=1 olddefconfig

        # Our initramfs has no modules, so the boot path must be built in.
        for opt in BLK_DEV_INITRD DEVTMPFS USB_XHCI_HCD USB_STORAGE BLK_DEV_SD EXT4_FS; do
            grep -qx "CONFIG_${opt}=y" .config || { echo "CONFIG_${opt} is not =y" >&2; exit 1; }
        done

        make -j"$(nproc)" LLVM=1 bzImage modules
        make LLVM=1 INSTALL_MOD_PATH=/build/modules INSTALL_MOD_STRIP=1 modules_install
        rm -f /build/modules/lib/modules/*/build
    '

cp "$SRC/arch/x86/boot/bzImage" "$OUT/bzImage"
{
    echo "kernel_repo=$KERNEL_REPO"
    echo "kernel_branch=$KERNEL_BRANCH"
    echo "kernel_commit=$(git -C "$SRC" rev-parse HEAD)"
    echo "kernel_release=$(ls "$BUILD/modules/lib/modules")"
} > "$OUT/kernel.info"
ok "Kernel: $OUT/bzImage ($(cut -d= -f2 <<<"$(grep release "$OUT/kernel.info")"))"
