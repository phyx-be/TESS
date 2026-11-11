# Linux console on the display (console=tty0 fbcon=rotate:1 on the kernel
# command line): framebuffer emulation on the DRM device and a rotatable
# framebuffer console
CONFIG_FONT=y
CONFIG_FB=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_FBDEV_OVERALLOC=200
