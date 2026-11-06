# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Root filesystem for one distro (config/<DISTRO>/). Built with `docker build`,
# then exported as a tarball by scripts/build-rootfs.sh.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG DISTRO
ARG NAME
# minimal: text console only.  desktop: XFCE.
ARG PROFILE=desktop
# Metapackage with security tools, or "none".
ARG TOOLS=none
ARG USER_NAME
ARG USER_PASS
ENV DEBIAN_FRONTEND=noninteractive

COPY config/${DISTRO}/packages-*.txt /tmp/distro/
RUN set -e; \
    case "$PROFILE" in \
        minimal) lists=/tmp/distro/packages-base.txt ;; \
        desktop) lists="/tmp/distro/packages-base.txt /tmp/distro/packages-desktop.txt" ;; \
        *) echo "Unknown PROFILE=$PROFILE (use minimal or desktop)" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    cat $lists | grep -vE '^[[:space:]]*(#|$)' | xargs apt-get install -y; \
    if [ "$TOOLS" != none ]; then apt-get install -y $TOOLS; fi; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/distro

# Default login (same idea as the official live images); change it with passwd.
RUN groups=sudo; \
    for g in netdev bluetooth plugdev input video audio; do \
        getent group "$g" >/dev/null && groups="$groups,$g"; \
    done; \
    useradd -m -s "$(command -v zsh || echo /bin/bash)" -G "$groups" "$USER_NAME" \
 && echo "$USER_NAME:$USER_PASS" | chpasswd

COPY overlay/ /
COPY config/motd.in /tmp/motd.in

# Per-distro names: root filesystem label <DISTRO>-PS4 (hostname and hosts
# are written after the export, since docker export replaces them).
RUN label="$(echo "$DISTRO" | tr a-z A-Z)-PS4" \
 && sed -e "s|@NAME@|$NAME|" -e "s|@USER@|$USER_NAME|" -e "s|@PASS@|$USER_PASS|" /tmp/motd.in > /etc/motd \
 && rm /tmp/motd.in \
 && printf '%s\n' \
      '# <device>        <mount>  <type>  <options>               <dump> <pass>' \
      "LABEL=$label  /        ext4    defaults,noatime        0      1" \
      'LABEL=PS4BOOT     /boot    vfat    defaults,noauto,nofail  0      0' \
      'tmpfs             /tmp     tmpfs   defaults,nosuid,nodev   0      0' > /etc/fstab

# Every image would otherwise ship the same SSH host keys and machine-id.
RUN rm -f /etc/ssh/ssh_host_* \
 && : > /etc/machine-id \
 && rm -f /var/lib/dbus/machine-id \
 && systemctl enable ps4-hostkeys.service NetworkManager.service ps4-hdmi-keepalive.service \
 && systemctl enable ssh.service \
 && if [ "$PROFILE" = desktop ]; then systemctl set-default graphical.target; \
    else systemctl set-default multi-user.target; fi
