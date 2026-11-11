#!/bin/sh
#
# Main image:
#  - login console on the USB serial gadget (ttyGS0)
#  - read-only root filesystem: mount points and real directories for the
#    bind mounts from the data partition (/etc/init.d/S00datafs)
#  - RAUC keyring: the certificate that update bundles must be signed with

set -eu

BOARD_DIR="$(dirname "$0")"
INITTAB="${TARGET_DIR}/etc/inittab"
RAUC_CERT="${TESS_RAUC_CERT:-${BOARD_DIR}/rauc/development.cert.pem}"

if ! grep -q '^ttyGS0::' "${INITTAB}"; then
	sed -i '/# GENERIC_SERIAL$/a ttyGS0::respawn:/usr/sbin/usb-getty # USB serial gadget' "${INITTAB}"
fi

# Data partition mount point
install -d "${TARGET_DIR}/data"

# Bind mount targets (DATA_BINDS in /etc/default/datafs). The skeleton and
# the dropbear package make /var/log and /etc/dropbear links into tmpfs
# directories; turn them into directories of their own.
for d in etc/dropbear etc/wpa_supplicant var/lib var/log; do
	if [ -L "${TARGET_DIR}/${d}" ]; then
		rm "${TARGET_DIR}/${d}"
	fi
	install -d "${TARGET_DIR}/${d}"
done

install -D -m 0644 "${RAUC_CERT}" "${TARGET_DIR}/etc/rauc/keyring.pem"
