#!/bin/sh
#
# Make sure the board is in FEL, the USB boot mode of the T113 boot ROM.
#
# With TESS_HOST set (e.g. TESS_HOST=tess-43c0.local), a running board
# whose system has tess-fel is asked over SSH (as root, with a key) to
# reboot into FEL. Otherwise: hold SW2 and press SW1 (RESET) with the USB-C
# connected.
#
# Usage: fel-enter.sh <sunxi-fel>

FEL="$1"

"${FEL}" version >/dev/null 2>&1 && exit 0

if [ -z "${TESS_HOST:-}" ]; then
	echo "no Allwinner USB FEL device: connect the USB-C connector, hold SW2" \
		"and press SW1 (RESET), or set TESS_HOST to the host name of a" \
		"running board with tess-fel to reboot it into FEL" >&2
	exit 1
fi

echo "Asking ${TESS_HOST} to reboot into FEL (tess-fel)"
ssh -o BatchMode=yes -o ConnectTimeout=10 "root@${TESS_HOST}" tess-fel || {
	echo "ssh root@${TESS_HOST} tess-fel failed" >&2
	exit 1
}
i=0
until "${FEL}" version >/dev/null 2>&1; do
	i=$((i + 1))
	if [ "${i}" -ge 30 ]; then
		echo "no Allwinner USB FEL device 30 s after tess-fel" >&2
		exit 1
	fi
	sleep 1
done
