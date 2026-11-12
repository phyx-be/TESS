#!/bin/sh
#
# Write an image to the SD NAND of the Tess board over USB: start the
# flasher's U-Boot alone over FEL, which then runs USB DFU (see
# board/tess/uboot/tess-flasher.env), and send the image with dfu-util. On
# detach, U-Boot resets the board, which boots the new image.
#
# The board must be in FEL: connect the USB-C connector, hold SW2 and
# press SW1 (RESET).
#
# Usage, from this external tree:
#   ./flash-sd.sh [image] [flasher output directory]
#     image: default output/main/images/sdcard.img (the main image)
#     flasher output directory: default output/flasher (for sunxi-fel,
#     dfu-util and U-Boot)

set -eu

TESS_DIR=$(cd "$(dirname "$0")" && pwd)
IMG="${1:-${TESS_DIR}/output/main/images/sdcard.img}"
O="${2:-${TESS_DIR}/output/flasher}"
FEL="${O}/host/bin/sunxi-fel"
DFU="${O}/host/bin/dfu-util"
UBOOT="${O}/images/u-boot-sunxi-with-spl.bin"
# "sdcard raw 0 0xF0000" in tess-flasher.env: 0xF0000 blocks of 512 bytes
MAX_SIZE=$((0xF0000 * 512))
USB_ID="1f3a:1010"	# U-Boot's USB gadget (Allwinner)

die() {
	echo "flash-sd.sh: $*" >&2
	exit 1
}

[ -f "${IMG}" ] || die "image ${IMG} not found (make main, or give an image)"
[ -x "${FEL}" ] && [ -x "${DFU}" ] && [ -f "${UBOOT}" ] ||
	die "flasher build not found in ${O} (make flasher)"
SIZE=$(stat -c %s "${IMG}")
[ "${SIZE}" -le "${MAX_SIZE}" ] ||
	die "${IMG} is ${SIZE} bytes, larger than the SD NAND (${MAX_SIZE})"

"${FEL}" version >/dev/null ||
	die "no Allwinner USB FEL device: connect the USB-C connector, hold SW2 and press SW1 (RESET)"

echo "Starting U-Boot over FEL"
"${FEL}" uboot "${UBOOT}"

echo "Waiting for the USB DFU device"
i=0
until "${DFU}" -l 2>/dev/null | grep -q "\[${USB_ID}\].*name=\"sdcard\""; do
	i=$((i + 1))
	[ "${i}" -lt 30 ] || die "no USB DFU device after 30 s (check the serial console)"
	sleep 1
done

echo "Writing ${IMG} (${SIZE} bytes) to the SD NAND"
"${DFU}" -d "${USB_ID}" -a sdcard -R -D "${IMG}"
echo "Done: the board resets and boots the new image."
