setenv bootdelay 2
setenv bootargs console=tty0 console=ttyS3,115200 root=/dev/ram0 ro fbcon=rotate:1 loglevel=8
setenv fdt_high ffffffff
setenv initrd_high ffffffff
# Raspberry Pi 7" DSI display overlay, loaded at 0x43200000 by flash.sh
fdt addr 0x43000000
fdt resize 8192
fdt apply 0x43200000
bootz 0x42000000 0x43300000 0x43000000
