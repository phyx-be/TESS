#!/bin/sh
#
# Flasher image: wrap the squashfs root filesystem in a U-Boot legacy
# ramdisk image, loaded over FEL by flash.sh and booted with bootz.

set -eu

"${HOST_DIR}/bin/mkimage" -A arm -O linux -T ramdisk -C none \
	-d "${BINARIES_DIR}/rootfs.squashfs" "${BINARIES_DIR}/rootfs.squashfs.uboot"
