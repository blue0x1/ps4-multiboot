#!/usr/bin/env bash
# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Builds out/bzImage plus kernel modules and firmware for the rootfs.
# The PS4 kernel tree is fetched at build time (GPLv2), never vendored here.
# It is built with its own build.sh and Docker image; config/ps4.config adds
# the options this project needs on top.
source "$(dirname "$0")/common.sh"

SRC="$BUILD/ps4-linux"

if [ -d "$SRC/.git" ] && [ "$(git -C "$SRC" remote get-url origin)" != "$KERNEL_REPO" ]; then
    log "Kernel tree in $SRC is from another repository, cloning again"
    rm -rf "$SRC"
fi
if [ ! -d "$SRC/.git" ]; then
    log "Cloning $KERNEL_REPO ($KERNEL_BRANCH)"
    git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$SRC"
else
    log "Updating kernel tree"
    git -C "$SRC" fetch --depth 1 origin "$KERNEL_BRANCH"
    # -f: drop our previous merge into the tree's config file.
    git -C "$SRC" checkout -q -f FETCH_HEAD
fi
for f in config build.sh Dockerfile; do
    [ -f "$SRC/$f" ] || die "PS4 kernel tree has no '$f' file; upstream layout changed"
done

if ! docker image inspect "$KERNEL_BUILDER_IMAGE" >/dev/null 2>&1; then
    log "Building kernel toolchain image $KERNEL_BUILDER_IMAGE"
    # The Dockerfile copies nothing in, so no build context is sent.
    docker build -t "$KERNEL_BUILDER_IMAGE" - < "$SRC/Dockerfile"
fi
rm -rf "$BUILD/modules"

log "Compiling kernel (this takes a while)"
docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e KERNEL_PROFILE="$KERNEL_PROFILE" \
    -e KERNEL_LTO="$KERNEL_LTO" \
    -v "$BUILD:/build" \
    -v "$ROOT/config:/cfg:ro" \
    -w /build/ps4-linux \
    "$KERNEL_BUILDER_IMAGE" bash -euo pipefail -c '
        # Our options go into the tree config that build.sh starts from. Its own
        # profile files run after, but none of them touch these options.
        while IFS= read -r line; do
            name="${line%%=*}"
            case "$line" in
                CONFIG_*=y) scripts/config --file config --enable "$name" ;;
                CONFIG_*=m) grep -qx "$name=y" config || scripts/config --file config --module "$name" ;;
            esac
        done < /cfg/ps4.config

        ./build.sh --option 3 use="$KERNEL_PROFILE" lto="$KERNEL_LTO"

        # Our initramfs has no modules, so the boot path must be built in.
        fail=0
        while IFS= read -r line; do
            name="${line%%=*}"
            case "$line" in
                CONFIG_*=y) grep -qx "$name=y" .config || { echo "$name is not =y" >&2; fail=1; } ;;
                CONFIG_*=m) grep -qE "^$name=[ym]$" .config || echo "warning: $name was dropped by the kernel config" >&2 ;;
            esac
        done < /cfg/ps4.config
        [ "$fail" = 0 ]

        # Modules, with the flags build.sh compiled the kernel with. bzImage is
        # rebuilt in the same run so it matches the modules exactly.
        eval "$(grep -E "^export (KCFLAGS|KAFLAGS|HOSTCFLAGS)=" build.sh)"
        opts=(LLVM=1 ARCH=x86_64 HOSTCFLAGS="$HOSTCFLAGS")
        make -j"$(nproc)" "${opts[@]}" bzImage modules
        make "${opts[@]}" INSTALL_MOD_PATH=/build/modules INSTALL_MOD_STRIP=1 modules_install
        rm -f /build/modules/lib/modules/*/build
    '

cp "$SRC/arch/x86/boot/bzImage" "$OUT/bzImage"
cp "$SRC/.config" "$OUT/kernel.config"
{
    echo "kernel_repo=$KERNEL_REPO"
    echo "kernel_branch=$KERNEL_BRANCH"
    echo "kernel_commit=$(git -C "$SRC" rev-parse HEAD)"
    echo "kernel_build=use=$KERNEL_PROFILE lto=$KERNEL_LTO"
    echo "kernel_release=$(ls "$BUILD/modules/lib/modules")"
} > "$OUT/kernel.info"
ok "Kernel: $OUT/bzImage ($(cut -d= -f2 <<<"$(grep release "$OUT/kernel.info")"))"
