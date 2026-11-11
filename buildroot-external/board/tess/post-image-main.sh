#!/bin/sh
#
# Main image: RAUC update bundle tess-update.raucb with the root filesystem,
# signed with TESS_RAUC_KEY / TESS_RAUC_CERT (default: the development
# pair in rauc/, see rauc/README). Install on the board with:
#   rauc install /data/tess-update.raucb
#
# Arguments (the genimage configuration) are ignored.

set -eu

BOARD_DIR="$(dirname "$0")"
RAUC_KEY="${TESS_RAUC_KEY:-${BOARD_DIR}/rauc/development.key.pem}"
RAUC_CERT="${TESS_RAUC_CERT:-${BOARD_DIR}/rauc/development.cert.pem}"
BUNDLE="${BINARIES_DIR}/tess-update.raucb"
WORK="${BUILD_DIR}/tess-rauc-bundle"
VERSION="$(date -u +%Y%m%d%H%M%S)"
if GIT="$(git -C "${BOARD_DIR}" describe --always --dirty 2>/dev/null)"; then
	VERSION="${VERSION}-${GIT}"
fi

rm -rf "${WORK}" "${BUNDLE}"
mkdir -p "${WORK}"
cp "${BINARIES_DIR}/rootfs.ext4" "${WORK}/"

cat > "${WORK}/manifest.raucm" <<EOM
[update]
compatible=phyxbe-tess
version=${VERSION}

[bundle]
format=verity

[image.rootfs]
filename=rootfs.ext4
EOM

"${HOST_DIR}/bin/rauc" bundle \
	--cert="${RAUC_CERT}" \
	--key="${RAUC_KEY}" \
	"${WORK}" "${BUNDLE}"

rm -rf "${WORK}"
echo "RAUC bundle: ${BUNDLE} (version ${VERSION})"
