#!/bin/sh
#
# Flasher root filesystem:
#  - login console on the USB serial gadget (ttyGS0)
#  - configfs (USB gadget) and debugfs mounts
#  - the ESP32-C3 firmware (esp32c3/build.sh, make esp32c3) for
#    esp32c3-flash to flash. It must be built first; it defaults to
#    output/esp32c3/ in this external tree (TESS_ESP32C3_O).

set -eu

TESS_DIR=$(cd "$(dirname "$0")/../.." && pwd)
FW_DIR="${TESS_ESP32C3_O:-${TESS_DIR}/output/esp32c3}"
FW_DEST="${TARGET_DIR}/lib/firmware/esp-hosted"

if ! grep -q '^ttyGS0::' "${TARGET_DIR}/etc/inittab"; then
	sed -i '/# GENERIC_SERIAL$/a ttyGS0::respawn:/usr/sbin/usb-getty # USB serial gadget' "${TARGET_DIR}/etc/inittab"
fi

grep -qE '^configfs' "${TARGET_DIR}/etc/fstab" ||
	echo 'configfs	/sys/kernel/config	configfs	defaults	0	0' >> "${TARGET_DIR}/etc/fstab"
grep -qE '^debugfs' "${TARGET_DIR}/etc/fstab" ||
	echo 'debugfs	/sys/kernel/debug	debugfs	defaults	0	0' >> "${TARGET_DIR}/etc/fstab"

if [ ! -f "${FW_DIR}/tess-esp32c3.bin" ] || [ ! -f "${FW_DIR}/flash_args" ]; then
	echo "ERROR: ESP32-C3 firmware not found in ${FW_DIR}." >&2
	echo "Run make esp32c3 first, or set TESS_ESP32C3_O." >&2
	exit 1
fi
(cd "${FW_DIR}" && sha256sum -c --quiet SHA256SUMS)
rm -rf "${FW_DEST}"
install -d "${FW_DEST}"
install -m 0644 "${FW_DIR}"/*.bin "${FW_DIR}/flash_args" "${FW_DIR}/SHA256SUMS" "${FW_DIR}/VERSION" "${FW_DEST}/"
