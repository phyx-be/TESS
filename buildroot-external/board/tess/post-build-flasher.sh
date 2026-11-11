#!/bin/sh
#
# Flasher image: add the main image (sdcard.img from tess_defconfig)
# for tess-install to write to the SD NAND.
#
# The main image must be built first. Its location defaults to
# output/images/sdcard.img in this external tree and can be changed with
# TESS_MAIN_IMAGE.

set -eu

TESS_DIR=$(cd "$(dirname "$0")/../.." && pwd)
IMG="${TESS_MAIN_IMAGE:-${TESS_DIR}/output/images/sdcard.img}"
DEST="${TARGET_DIR}/usr/share/tess"

if [ ! -f "${IMG}" ]; then
	echo "ERROR: main image ${IMG} not found." >&2
	echo "Build tess_defconfig first, or set TESS_MAIN_IMAGE." >&2
	exit 1
fi

install -d "${DEST}"
# xz -6: 8 MiB dictionary, so busybox xzcat on the board needs little RAM
xz -6 --check=crc32 -c "${IMG}" > "${DEST}/sdcard.img.xz"
# size and checksum of the uncompressed image, to verify the SD NAND
printf '%s  %s\n' "$(stat -c %s "${IMG}")" "$(sha256sum "${IMG}" | cut -d' ' -f1)" \
	> "${DEST}/sdcard.img.info"
