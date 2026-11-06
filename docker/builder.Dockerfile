# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Toolchain image used for the kernel, initramfs and final rootfs assembly.
FROM docker.io/kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bc bison build-essential busybox-static ca-certificates clang cpio \
      dwarves e2fsprogs flex git kmod libelf-dev libssl-dev lld llvm perl python3 \
      rsync xz-utils zstd \
 && rm -rf /var/lib/apt/lists/*
