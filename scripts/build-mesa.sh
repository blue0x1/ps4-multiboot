#!/usr/bin/env bash
# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Builds out/ps4-mesa.tar.xz: Mesa (OpenGL and Vulkan) patched for the PS4 GPU
# (Liverpool and Gladius), with its own libdrm and LLVM, installed under
# /opt/ps4-mesa so it works the same on any distro (glibc 2.41 or newer).
source "$(dirname "$0")/common.sh"

MESA_VER="${MESA_VER:-26.2.5}"
MESA_SHA256="794b3d1729075dae7ebd47c7283b7ca0cdb5dec668f7f11cc0a5d82f6138a0a5"
DRM_VER="${DRM_VER:-2.4.134}"
DRM_SHA256="ac5e74d157830eb8bee44c6a6bf3ad49774ef0dd2a72bdad74a8f20308b52a95"
IMAGE="ps4-mesa-builder"
PREFIX=/opt/ps4-mesa
W="$BUILD/mesa"

fetch() {  # url sha256
    local f="$W/src/$(basename "$1")"
    [ -f "$f" ] || curl -fL -o "$f" "$1"
    echo "$2  $f" | sha256sum -c --quiet || die "Checksum mismatch: $f"
}

mkdir -p "$W/src"
fetch "https://archive.mesa3d.org/mesa-$MESA_VER.tar.xz" "$MESA_SHA256"
fetch "https://dri.freedesktop.org/libdrm/libdrm-$DRM_VER.tar.xz" "$DRM_SHA256"

docker image inspect "$IMAGE" >/dev/null 2>&1 \
    || docker build -t "$IMAGE" -f "$ROOT/docker/mesa.Dockerfile" "$ROOT/docker"

rm -rf "$W/stage"
log "Building libdrm $DRM_VER and Mesa $MESA_VER (this takes a while)"
docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "$W:/w" -v "$ROOT/patches/mesa:/patches:ro" \
    -e MESA_VER="$MESA_VER" -e DRM_VER="$DRM_VER" -e PREFIX="$PREFIX" \
    "$IMAGE" bash -euo pipefail -c '
        cd /w
        rm -rf "libdrm-$DRM_VER" "mesa-$MESA_VER" b-drm b-mesa
        tar -xf "src/libdrm-$DRM_VER.tar.xz"
        tar -xf "src/mesa-$MESA_VER.tar.xz"

        # libdrm: names the PS4 GPUs in amdgpu.ids (shown by glxinfo and vulkaninfo).
        printf "9920,\t00,\tAMD Liverpool (PlayStation 4)\n9922,\t00,\tAMD Liverpool (PlayStation 4)\n9923,\t00,\tAMD Liverpool (PlayStation 4)\n9924,\t11,\tAMD Gladius (PlayStation 4 Pro)\n" \
            >> "libdrm-$DRM_VER/data/amdgpu.ids"
        meson setup b-drm "libdrm-$DRM_VER" --prefix="$PREFIX" --libdir=lib --buildtype=release \
            -Damdgpu=enabled -Dradeon=enabled -Dintel=disabled -Dnouveau=disabled \
            -Dvmwgfx=disabled -Dfreedreno=disabled -Dvc4=disabled -Detnaviv=disabled \
            -Dexynos=disabled -Domap=disabled -Dtegra=disabled \
            -Dtests=false -Dman-pages=disabled -Dvalgrind=disabled -Dcairo-tests=disabled
        ninja -C b-drm
        DESTDIR=/w/stage ninja -C b-drm install

        # Mesa, with the PS4 patches.
        for p in /patches/0*.patch; do patch -d "mesa-$MESA_VER" -p1 < "$p"; done
        export PKG_CONFIG_PATH=/w/stage$PREFIX/lib/pkgconfig
        export PKG_CONFIG_SYSROOT_DIR=
        sed -i "s|^prefix=.*|prefix=/w/stage$PREFIX|" /w/stage$PREFIX/lib/pkgconfig/*.pc
        meson setup b-mesa "mesa-$MESA_VER" --prefix="$PREFIX" --libdir=lib --buildtype=release \
            -Db_ndebug=true -Dstrip=true \
            -Dgallium-drivers=radeonsi,zink,llvmpipe -Dvulkan-drivers=amd \
            -Dplatforms=x11,wayland -Dglx=dri -Degl=enabled -Dgbm=enabled -Dglvnd=enabled \
            -Dgles1=disabled -Dgles2=enabled -Dopengl=true \
            -Dllvm=enabled -Dshared-llvm=enabled \
            -Dgallium-va=disabled -Dvideo-codecs= \
            -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dbuild-tests=false
        ninja -C b-mesa
        DESTDIR=/w/stage ninja -C b-mesa install
        sed -i "s|^prefix=.*|prefix=$PREFIX|" /w/stage$PREFIX/lib/pkgconfig/*.pc

        # Bundle the libraries Mesa needs that a distro may not have. They go
        # in lib/private, which only Mesa finds (lib/ is on the system path
        # once Mesa is enabled, and must not replace the distro own copies).
        L=/w/stage$PREFIX/lib
        mkdir -p $L/private
        for lib in $(LD_LIBRARY_PATH=$L ldd $L/libgallium-*.so $L/libvulkan_radeon.so \
                        | awk "/=> \\// {print \$3}" | sort -u); do
            case "$(basename "$lib")" in
                # Present on every desktop distro, and newer there: never shadow them.
                libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|ld-linux*) ;;
                libgcc_s.so*|libstdc++.so*|libz.so*|libzstd.so*|libexpat.so*|liblzma.so*) ;;
                libffi.so*|libtinfo.so*|libbsd.so*|libmd.so*|libelf.so*|libudev.so*) ;;
                libX*|libxcb*|libwayland*|libxshmfence*|libGLdispatch*|libGLX.so*|libEGL.so*) ;;
                *) [ "$(dirname "$lib")" = "$L" ] || cp -nL "$lib" $L/private/ ;;
            esac
        done
        rm -f $L/private/libcap.so*
        for f in $L/*.so*; do [ -L "$f" ] || patchelf --set-rpath "\$ORIGIN:\$ORIGIN/private" "$f"; done
        for f in $L/private/*; do patchelf --set-rpath "\$ORIGIN" "$f"; done
        for f in $L/dri/*.so $L/gbm/*.so; do [ -L "$f" ] || patchelf --set-rpath "\$ORIGIN/..:\$ORIGIN/../private" "$f"; done
        rm -rf /w/stage$PREFIX/include $L/pkgconfig
    '

cp -a "$ROOT/overlay-mesa/." "$W/stage/"
tar -C "$W/stage" -cf - --owner=0 --group=0 opt | xz -T0 -6 > "$OUT/ps4-mesa.tar.xz"
ok "PS4 Mesa: $OUT/ps4-mesa.tar.xz ($(du -h "$OUT/ps4-mesa.tar.xz" | cut -f1))"
