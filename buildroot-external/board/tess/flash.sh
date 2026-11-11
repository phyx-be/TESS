#!/bin/sh
#
# Boot the Tess flasher image over USB (FEL): load U-Boot, kernel, device
# tree, boot script and the squashfs root filesystem into RAM and start them.
#
# Usage:
#   board/tess/flash.sh [output directory, default: output-flasher next to
#                        this external tree]

TESS_DIR=$(cd "$(dirname "$0")/../.." && pwd)
O="${1:-${TESS_DIR}/output-flasher}"
I="${O}/images"

"${O}/host/bin/sunxi-fel" -v uboot "${I}/u-boot-sunxi-with-spl.bin" \
	write 0x42000000 "${I}/zImage" \
	write 0x43000000 "${I}/sun8i-t113s-tess.dtb" \
	write 0x43100000 "${I}/boot.scr" \
	write 0x43200000 "${I}/rpi-7inch-dsi-overlay.dtb" \
	write 0x43300000 "${I}/rootfs.squashfs.uboot"
