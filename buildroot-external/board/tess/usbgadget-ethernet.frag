# Flasher image: CDC ECM + RNDIS network gadget, both bridged in br0
# (USB_GADGET="ethernet" in /etc/default/usbgadget, /etc/init.d/S09bridge.sh)
CONFIG_USB_CONFIGFS_ECM=y
CONFIG_USB_CONFIGFS_ECM_SUBSET=y
CONFIG_USB_CONFIGFS_RNDIS=y
CONFIG_BRIDGE=y
