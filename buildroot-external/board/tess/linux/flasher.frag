# Flasher image: squashfs root filesystem loaded as initrd into /dev/ram0
CONFIG_BLK_DEV_RAM=y
CONFIG_BLK_DEV_RAM_COUNT=1
CONFIG_BLK_DEV_RAM_SIZE=65536
CONFIG_SQUASHFS=y
CONFIG_SQUASHFS_XZ=y
