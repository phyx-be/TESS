#!/bin/sh
#
# Build the esp-hosted ESP32-C3 firmware for Tess.
#
# The firmware is built from the same esp-hosted-linux commit as the
# esp-hosted kernel module package, because the module refuses to talk to
# a firmware with a different version. ESP-IDF is checked out at the
# commit pinned by esp-hosted-linux (esp/esp_driver/.env) and the build
# runs in the official espressif/idf Docker image.
#
# Usage:
#   esp32c3/build.sh (or make esp32c3)
#
# Environment:
#   BUILDROOT    Buildroot tree with the esp-hosted package, default: the
#                buildroot checkout next to this external tree
#   O            Buildroot output directory (to download the esp-hosted
#                tarball), default: output/main in this external tree
#   ESP_WORKDIR  work directory, kept between builds (ESP-IDF checkout)
#                default: ~/.cache/tess-esp32c3
#   BR2_DL_DIR   Buildroot download directory, default: ~/br-dl
#   TESS_ESP32C3_O
#                output directory, default: output/esp32c3 next to this
#                directory (not tracked in git; post-build-flasher.sh copies
#                it into the flasher image)
#
# Output, in TESS_ESP32C3_O:
#   tess-esp32c3.bin: all images merged into one, to be written at 0x0
#   bootloader.bin, partition-table.bin, ota_data_initial.bin,
#   network_adapter.bin and flash_args: the separate images

set -eu

BOARD_DIR=$(cd "$(dirname "$0")" && pwd)
TESS_DIR=$(cd "${BOARD_DIR}/.." && pwd)
TOPDIR="${BUILDROOT:-${TESS_DIR}/buildroot}"
O="${O:-${TESS_DIR}/output/main}"
OUT_DIR="${TESS_ESP32C3_O:-${TESS_DIR}/output/esp32c3}"
WORKDIR="${ESP_WORKDIR:-${HOME}/.cache/tess-esp32c3}"
DL_DIR="${BR2_DL_DIR:-${HOME}/br-dl}"

ESP_HOSTED_VERSION=$(sed -n 's/^ESP_HOSTED_VERSION = //p' \
	"${TOPDIR}/package/esp-hosted/esp-hosted.mk")
TARBALL="${DL_DIR}/esp-hosted/ng-v${ESP_HOSTED_VERSION}.tar.gz"

if [ ! -f "${TARBALL}" ]; then
	echo "Downloading esp-hosted ${ESP_HOSTED_VERSION}"
	make -C "${TOPDIR}" O="${O}" esp-hosted-source
fi

# esp-hosted-linux sources, from the Buildroot download, with our patches
SRC="${WORKDIR}/esp-hosted-${ESP_HOSTED_VERSION}"
rm -rf "${SRC}"
mkdir -p "${SRC}"
tar xzf "${TARBALL}" -C "${SRC}" --strip-components=1
for p in "${BOARD_DIR}"/patches/*.patch; do
	[ -f "${p}" ] || continue
	echo "Applying $(basename "${p}")"
	patch -d "${SRC}" -p1 < "${p}"
done
DRIVER_DIR="${SRC}/esp/esp_driver"

# shellcheck disable=SC1091
. "${DRIVER_DIR}/.env"	# IDF_TAG, IDF_COMMIT

# ESP-IDF at the pinned commit, with the esp-hosted patches and libraries
IDF_DIR="${WORKDIR}/esp-idf-${IDF_COMMIT}"
if [ ! -f "${IDF_DIR}/.tess-setup-done" ]; then
	rm -rf "${IDF_DIR}"
	git clone --branch "${IDF_TAG}" --depth 100 \
		https://github.com/espressif/esp-idf.git "${IDF_DIR}"
	git -C "${IDF_DIR}" checkout -q "${IDF_COMMIT}"
	git -C "${IDF_DIR}" apply --recount "${DRIVER_DIR}/lib/rom.patch"
	if ! grep -q "config OPENTHREAD_RCP_CUSTOM" \
		"${IDF_DIR}/components/openthread/Kconfig"; then
		git -C "${IDF_DIR}" apply --recount \
			"${DRIVER_DIR}/lib/idf-openthread-custom-rcp-v6.1.patch"
	fi
	git -C "${IDF_DIR}" submodule update --init --depth 1 --recursive
	# esp-hosted ships its own WiFi libraries
	rm -rf "${IDF_DIR}/components/esp_wifi/lib/"*
	cp -r "${DRIVER_DIR}/lib/"* "${IDF_DIR}/components/esp_wifi/lib/"
	touch "${IDF_DIR}/.tess-setup-done"
fi

# Build
APP_DIR="${DRIVER_DIR}/network_adapter"
cp "${BOARD_DIR}/sdkconfig.defaults.tess" "${APP_DIR}/"
rm -rf "${APP_DIR}/build" "${APP_DIR}/sdkconfig"

docker run --rm \
	-u "$(id -u):$(id -g)" \
	-e HOME=/tmp \
	-e IDF_PATH="${IDF_DIR}" \
	-v "${WORKDIR}:${WORKDIR}" \
	-w "${APP_DIR}" \
	--entrypoint /bin/bash \
	"espressif/idf:${IDF_TAG}" \
	-c ". \"\${IDF_PATH}/export.sh\" >/dev/null && \
	    idf.py -D SDKCONFIG_DEFAULTS='sdkconfig.defaults;sdkconfig.defaults.tess' \
	           set-target esp32c3 build && \
	    cd build && python -m esptool --chip esp32c3 merge-bin \
	           -o tess-esp32c3.bin @flash_args"

# Collect the flash images
B="${APP_DIR}/build"
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cp "${B}/bootloader/bootloader.bin" \
   "${B}/partition_table/partition-table.bin" \
   "${B}/ota_data_initial.bin" \
   "${B}/network_adapter.bin" \
   "${B}/flash_args" \
   "${B}/tess-esp32c3.bin" \
   "${OUT_DIR}/"
sed -i 's#[^ ]*/##g' "${OUT_DIR}/flash_args"	# keep file names only

cat > "${OUT_DIR}/VERSION" <<EOF
esp-hosted-linux ${ESP_HOSTED_VERSION}
esp-idf ${IDF_TAG} ${IDF_COMMIT}
EOF
(cd "${OUT_DIR}" && sha256sum ./*.bin flash_args > SHA256SUMS)

echo "Firmware written to ${OUT_DIR}:"
cat "${OUT_DIR}/flash_args"
