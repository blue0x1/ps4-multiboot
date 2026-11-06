#!/usr/bin/env bash
# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Builds out/<distro>-ps4-rootfs.tar.xz: the distro userland + PS4 kernel modules + firmware.
# Needs build-kernel.sh to have run first.
source "$(dirname "$0")/common.sh"

[ -d "$BUILD/modules/lib/modules" ] || die "No kernel modules yet - run 'make kernel' first"

log "Building $NAME rootfs image (PROFILE=$PROFILE TOOLS=$TOOLS)"
docker build -t "$ROOTFS_IMAGE" \
    --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg DISTRO="$DISTRO" --build-arg NAME="$NAME" \
    --build-arg USER_NAME="$USER_NAME" --build-arg USER_PASS="$USER_PASS" \
    --build-arg PROFILE="$PROFILE" --build-arg TOOLS="$TOOLS" -f "$ROOT/docker/rootfs.Dockerfile" "$ROOT"

log "Exporting container filesystem"
cid="$(docker create "$ROOTFS_IMAGE")"
trap 'docker rm -f "$cid" >/dev/null' EXIT
docker export "$cid" -o "$BUILD/rootfs.tar"

# Name and logo for the boot menu. They go first in the archive, so the menu
# reads them from the first few MB without unpacking the rest.
#   name: NAME from config/<distro>/distro.env, else NAME from os-release
#   logo: assets/logos/<distro>.png, else LOGO (a path inside the image) from
#         distro.env, else the icon named by os-release's LOGO= field
log "Adding the menu name and logo"
META="$BUILD/meta"
rm -rf "$META"
mkdir -p "$META/etc/ps4-distro"
# shellcheck disable=SC2016
osr="$(docker run --rm "$ROOTFS_IMAGE" sh -c '. /etc/os-release; printf "%s\n%s\n" "$NAME" "$LOGO"')"
menu_name="${NAME:-$(echo "$osr" | sed -n 1p)}"
printf '%s\n' "$menu_name" | tr -d '|' > "$META/etc/ps4-distro/name"
logo_src=""
if [ -f "$ROOT/assets/logos/$DISTRO.png" ]; then
    logo_src="$ROOT/assets/logos/$DISTRO.png"
else
    in_image="${LOGO:-}"
    icon="$(echo "$osr" | sed -n 2p)"
    if [ -z "$in_image" ] && [ -n "$icon" ]; then
        # Largest PNG of that icon name, or an SVG.
        in_image="$(docker run --rm "$ROOTFS_IMAGE" sh -c \
            "find /usr/share/icons /usr/share/pixmaps -name '$icon.png' -o -name '$icon.svg' 2>/dev/null | xargs -r ls -S 2>/dev/null | head -1")"
    fi
    if [ -n "$in_image" ]; then
        logo_src="$BUILD/logo-src.${in_image##*.}"
        docker cp -L "$cid:$in_image" "$logo_src" || logo_src=""
        if [ "${logo_src##*.}" = svg ]; then
            if command -v rsvg-convert >/dev/null; then
                rsvg-convert -w 960 "$logo_src" -o "$BUILD/logo-src.png" && logo_src="$BUILD/logo-src.png"
            else
                log "rsvg-convert not installed: cannot use the SVG logo"; logo_src=""
            fi
        fi
    fi
fi
if [ -n "$logo_src" ]; then
    python3 "$ROOT/tools/logo-to-rgba.py" "$logo_src" "$META/etc/ps4-distro/logo.rgba"
else
    log "No logo found: the menu shows the first letter of the name"
fi
rm -f "$BUILD"/logo-src.*

ensure_builder
log "Adding kernel modules and firmware, compressing"
FIRMWARE="$BUILD/ps4-linux/extra_firmware"
docker run --rm \
    -v "$BUILD:/build:ro" \
    -v "$META:/meta:ro" \
    -v "$OUT:/out" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e DISTRO="$DISTRO" -e ROOTFS_TAR="$ROOTFS_TAR" \
    -e HAVE_FW="$([ -d "$FIRMWARE" ] && echo 1 || echo 0)" \
    "$BUILDER_IMAGE" bash -euo pipefail -c '
        r=/work/root
        mkdir -p "$r"
        tar -xpf /build/rootfs.tar -C "$r" --numeric-owner

        cp -a /build/modules/lib/modules/. "$r/usr/lib/modules/"
        if [ "$HAVE_FW" = 1 ]; then
            cp -a /build/ps4-linux/extra_firmware/. "$r/usr/lib/firmware/"
        fi
        # The initramfs covers these with the console GPU firmware and EDID
        # that ps4-linux-loader extracts at boot, so they only need to exist.
        mkdir -p "$r/usr/lib/firmware/amdgpu" "$r/usr/lib/firmware/edid"

        # docker export leaves its own runtime versions of these files.
        echo "$DISTRO-ps4" > "$r/etc/hostname"
        printf "127.0.0.1\tlocalhost\n127.0.1.1\t%s\n::1\t\tlocalhost ip6-localhost ip6-loopback\nff02::1\t\tip6-allnodes\nff02::2\t\tip6-allrouters\n" \
            "$DISTRO-ps4" > "$r/etc/hosts"
        rm -f "$r/etc/resolv.conf" && : > "$r/etc/resolv.conf"
        rm -f "$r/.dockerenv"

        # Menu name and logo first (owned by root), then the root filesystem.
        cp -a /meta /work/meta
        chown -R 0:0 /work/meta
        chmod -R u=rwX,go=rX /work/meta
        tar -cpf - --numeric-owner -C /work/meta --no-recursion ./etc --recursion ./etc/ps4-distro \
            -C "$r" . | xz -T0 -6 > "/out/$ROOTFS_TAR"
        chown "$HOST_UID:$HOST_GID" "/out/$ROOTFS_TAR"
    '

rm -f "$BUILD/rootfs.tar"
ok "Rootfs: $OUT/$ROOTFS_TAR ($(du -h "$OUT/$ROOTFS_TAR" | cut -f1))"
