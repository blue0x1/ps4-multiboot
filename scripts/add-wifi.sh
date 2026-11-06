#!/usr/bin/env bash
# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Saves a Wi-Fi network onto a flashed USB drive so the distro joins it at boot.
# Usage: sudo scripts/add-wifi.sh      (asks for the Wi-Fi name and password)
set -euo pipefail

die() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }

[ "$(id -u)" = 0 ] || die "Run with sudo: sudo $0"
dev="$(blkid -L "$ROOT_LABEL")" || die "No partition labeled $ROOT_LABEL found; is the USB drive plugged in?"

mnt="$(findmnt -n -o TARGET --source "$dev" | head -n1 || true)"
if [ -z "$mnt" ]; then
    mnt="$(mktemp -d)"
    mount "$dev" "$mnt"
    trap 'umount "$mnt"; rmdir "$mnt"' EXIT
fi
[ -d "$mnt/etc/NetworkManager" ] || die "$dev does not look like a $NAME root filesystem"

read -r -p "Wi-Fi name (SSID): " ssid
[ -n "$ssid" ] || die "Empty Wi-Fi name"
read -r -s -p "Wi-Fi password: " psk; echo
[ ${#psk} -ge 8 ] || die "WPA passwords are at least 8 characters"

dir="$mnt/etc/NetworkManager/system-connections"
mkdir -p "$dir"
f="$dir/home-wifi.nmconnection"
umask 077
cat > "$f" <<EOF
[connection]
id=home-wifi
uuid=$(cat /proc/sys/kernel/random/uuid)
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$psk

[ipv4]
method=auto

[ipv6]
method=auto
EOF
chown 0:0 "$f"
chmod 600 "$f"
sync
ok "Saved Wi-Fi \"$ssid\" on the USB drive. $NAME will join it at boot."
