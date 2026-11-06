# Copyright (C) 2026 Chokri Hammedi (blue0x1) <https://github.com/blue0x1>
# Build entry points. Variables can be overridden:
#   make rootfs DISTRO=parrot        (one archive per distro, see config/)
#   make PROFILE=desktop TOOLS=kali-tools-top10
#   make KERNEL_BRANCH=6.15
#   make usb DEVICE=/dev/sdX [ROOT_SIZE=8G]

DISTRO ?= kali
export KERNEL_REPO KERNEL_BRANCH DISTRO PROFILE TOOLS

.PHONY: all kernel initramfs rootfs mesa ps4-files usb clean distclean

all: kernel initramfs rootfs

kernel:
	scripts/build-kernel.sh

initramfs:
	scripts/build-initramfs.sh

rootfs:
	scripts/build-rootfs.sh

# PS4 Mesa (OpenGL and Vulkan for the PS4 GPU): out/ps4-mesa.tar.xz
mesa:
	scripts/build-mesa.sh

# Copies a finished build into ps4-files/, laid out like the PS4's folders
# (for the GitHub Release; not committed).
ps4-files:
	mkdir -p ps4-files/data/linux/boot ps4-files/user/home
	cp out/bzImage out/initramfs.cpio.gz config/bootargs.txt ps4-files/data/linux/boot/
	cp out/*-ps4-rootfs.tar.xz ps4-files/user/home/
	cp out/kernel.info ps4-files/

usb:
	@test -n "$(DEVICE)" || { echo "Usage: make usb DEVICE=/dev/sdX"; exit 1; }
	sudo scripts/make-usb.sh "$(DEVICE)" "$(ROOT_SIZE)"

clean:
	rm -rf out build/modules build/rootfs.tar

distclean: clean
	rm -rf build
	-docker rmi $(DISTRO)-ps4-rootfs kali-ps4-builder
