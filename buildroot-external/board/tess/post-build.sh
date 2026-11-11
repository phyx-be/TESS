#!/bin/sh

set -u
set -e

if [ -e ${TARGET_DIR}/etc/fstab ]; then
    # add configfs mount
    grep -qE '^configfs' ${TARGET_DIR}/etc/fstab || \
        echo 'configfs	/sys/kernel/config	configfs	defaults	0	0' >> ${TARGET_DIR}/etc/fstab
    # add debugfs mount
    grep -qE '^debugfs' ${TARGET_DIR}/etc/fstab || \
        echo 'debugfs	/sys/kernel/debug	debugfs	defaults	0	0' >> ${TARGET_DIR}/etc/fstab
fi
