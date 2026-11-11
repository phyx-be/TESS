#!/bin/sh
#
# Flasher image: add the main image (sdcard.img from tess_defconfig) for
# tess-install to write to the SD NAND, and the ESP32-C3 firmware
# (esp32c3/build.sh, make esp32c3) for it to flash.
#
# Both must be built first. The main image defaults to
# output/images/sdcard.img in this external tree (TESS_MAIN_IMAGE), the
# firmware to output-esp32c3/ (TESS_ESP32C3_O).

set -eu

TESS_DIR=$(cd "$(dirname "$0")/../.." && pwd)
IMG="${TESS_MAIN_IMAGE:-${TESS_DIR}/output/images/sdcard.img}"
DEST="${TARGET_DIR}/usr/share/tess"
FW_DIR="${TESS_ESP32C3_O:-${TESS_DIR}/output-esp32c3}"
FW_DEST="${TARGET_DIR}/lib/firmware/esp-hosted"

if [ ! -f "${FW_DIR}/tess-esp32c3.bin" ] || [ ! -f "${FW_DIR}/flash_args" ]; then
	echo "ERROR: ESP32-C3 firmware not found in ${FW_DIR}." >&2
	echo "Run make esp32c3 first, or set TESS_ESP32C3_O." >&2
	exit 1
fi
(cd "${FW_DIR}" && sha256sum -c --quiet SHA256SUMS)
rm -rf "${FW_DEST}"
install -d "${FW_DEST}"
install -m 0644 "${FW_DIR}"/*.bin "${FW_DIR}/flash_args" "${FW_DIR}/SHA256SUMS" "${FW_DIR}/VERSION" "${FW_DEST}/"

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
