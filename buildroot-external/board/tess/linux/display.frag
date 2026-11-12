# Main image: Raspberry Pi 7" Touch Display 2 on the DSI connector
# (rpi-7inch-dsi-overlay.dts): ILI9881C panel, display MCU (power,
# backlight) and Goodix touchscreen
CONFIG_DRM_PANEL_ILITEK_ILI9881C=y
CONFIG_REGULATOR_RASPBERRYPI_TOUCHSCREEN_V2=y
CONFIG_TOUCHSCREEN_GOODIX=y
