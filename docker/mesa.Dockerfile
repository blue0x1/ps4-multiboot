# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Toolchain for the PS4 Mesa bundle (OpenGL and Vulkan for the PS4 GPU).
# Debian trixie: the bundle then runs on distros with glibc 2.41 or newer.
FROM docker.io/library/debian:trixie

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential meson ninja-build pkg-config cmake bison flex \
        python3 python3-mako python3-yaml python3-packaging python3-ply \
        curl ca-certificates xz-utils patch file patchelf \
        llvm-19-dev libelf-dev libexpat1-dev zlib1g-dev libzstd-dev \
        libx11-dev libxext-dev libxfixes-dev libx11-xcb-dev libxshmfence-dev \
        libxxf86vm-dev libxrandr-dev \
        libxcb1-dev libxcb-glx0-dev libxcb-shm0-dev libxcb-dri3-dev libxcb-present-dev \
        libxcb-sync-dev libxcb-randr0-dev libxcb-xfixes0-dev libxcb-keysyms1-dev \
        libwayland-dev wayland-protocols libwayland-egl-backend-dev \
        libglvnd-dev libdisplay-info-dev libudev-dev glslang-tools spirv-tools \
    && rm -rf /var/lib/apt/lists/*
