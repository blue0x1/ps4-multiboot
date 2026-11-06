# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Shared settings and helpers. Sourced by the other scripts.
# shellcheck shell=bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
OUT="$ROOT/out"

KERNEL_REPO="${KERNEL_REPO:-https://github.com/sony-jaguar-devs/ps4-linux.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-7.0-Clean}"
DISTRO="${DISTRO:-kali}"
PROFILE="${PROFILE:-desktop}"
TOOLS="${TOOLS:-none}"

[ -f "$ROOT/config/$DISTRO/distro.env" ] || { echo "Unknown DISTRO=$DISTRO (see config/)" >&2; exit 1; }
# shellcheck source=/dev/null
source "$ROOT/config/$DISTRO/distro.env"

BUILDER_IMAGE="kali-ps4-builder"
ROOTFS_IMAGE="$DISTRO-ps4-rootfs"
ROOTFS_TAR="$DISTRO-ps4-rootfs.tar.xz"

ROOT_LABEL="$(echo "$DISTRO" | tr a-z A-Z)-PS4"
BOOT_LABEL="PS4BOOT"

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

ensure_builder() {
    if ! docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
        log "Building toolchain image $BUILDER_IMAGE"
        docker build -t "$BUILDER_IMAGE" -f "$ROOT/docker/builder.Dockerfile" "$ROOT/docker"
    fi
}

mkdir -p "$BUILD" "$OUT"
