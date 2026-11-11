#!/bin/sh

set -u
set -e

# Login console on the USB serial gadget (ttyGS0), both images
if ! grep -q '^ttyGS0::' "${TARGET_DIR}/etc/inittab"; then
	sed -i '/# GENERIC_SERIAL$/a ttyGS0::respawn:/usr/sbin/usb-getty # USB serial gadget' "${TARGET_DIR}/etc/inittab"
fi

if [ -e ${TARGET_DIR}/etc/fstab ]; then
    # add configfs mount
    grep -qE '^configfs' ${TARGET_DIR}/etc/fstab || \
        echo 'configfs	/sys/kernel/config	configfs	defaults	0	0' >> ${TARGET_DIR}/etc/fstab
    # add debugfs mount
    grep -qE '^debugfs' ${TARGET_DIR}/etc/fstab || \
        echo 'debugfs	/sys/kernel/debug	debugfs	defaults	0	0' >> ${TARGET_DIR}/etc/fstab
fi
