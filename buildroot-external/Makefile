# Tess flasher, built with Buildroot from this external tree, and the
# tools to write the board over USB:
#
#   make           the flasher image in output/flasher/ (the default target)
#   make esp32c3   ESP32-C3 esp-hosted firmware in output/esp32c3/, which
#                  the flasher image embeds and flashes; build it before
#                  the flasher (esp32c3/build.sh, ESP-IDF in Docker)
#   make flash     boot the flasher image over USB (FEL) to flash the
#                  ESP32-C3, see flash.sh
#   make flash-sd IMAGE=<file>
#                  write an image, e.g. the tess-os sdcard.img, to the SD
#                  NAND over USB: the flasher's U-Boot over FEL, then USB
#                  DFU, see flash-sd.sh
#   make <target>  any other target goes to Buildroot for the build in O
#                  (default: output/flasher), e.g. make menuconfig,
#                  make linux-rebuild
#
# BUILDROOT, FLASHER_O and ESP32C3_O override the Buildroot tree (the
# buildroot submodule) and the output directories. Downloads go to
# BR2_DL_DIR (~/br-dl from ~/.profile).

TESS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILDROOT ?= $(TESS_DIR)/buildroot
FLASHER_O ?= $(TESS_DIR)/output/flasher
ESP32C3_O ?= $(TESS_DIR)/output/esp32c3

# Build that the pass-through targets go to
ifneq ("$(origin O)", "command line")
O := $(FLASHER_O)
else
override O := $(abspath $(O))
endif

BR_MAKE = $(MAKE) -C $(BUILDROOT) BR2_EXTERNAL=$(TESS_DIR)

.PHONY: all flasher flash flash-sd esp32c3 help help-buildroot

all: flasher

# $(1): output directory, $(2): defconfig name. An output directory that
# has no configuration yet gets its defconfig.
define buildroot-configure
	@if [ ! -f $(BUILDROOT)/Makefile ]; then \
		echo "ERROR: no Buildroot in $(BUILDROOT): git submodule update --init" >&2; \
		exit 1; \
	fi
	$(if $(wildcard $(1)/.config),,$(BR_MAKE) O=$(1) $(2))
endef

flasher: export TESS_ESP32C3_O = $(ESP32C3_O)
flasher:
	$(call buildroot-configure,$(FLASHER_O),tess_flasher_defconfig)
	$(BR_MAKE) O=$(FLASHER_O)

# The SD NAND is written from the host: flash-sd.sh checks that the board
# is in FEL, starts the flasher's U-Boot alone, which enters USB DFU, and
# sends the image with dfu-util
flash-sd:
	@if [ -z "$(IMAGE)" ]; then \
		echo "ERROR: give the image to write: make flash-sd IMAGE=<path to sdcard.img>" >&2; \
		exit 1; \
	fi
	$(TESS_DIR)/flash-sd.sh $(abspath $(IMAGE)) $(FLASHER_O)

# sunxi-fel (host-sunxi-tools of the flasher build) first checks that the
# board is in FEL: hold SW2 and press SW1 (RESET) with the USB-C connected
flash:
	@if [ ! -x $(FLASHER_O)/host/bin/sunxi-fel ]; then \
		echo "ERROR: $(FLASHER_O)/host/bin/sunxi-fel not found, build the flasher image first (make flasher)" >&2; \
		exit 1; \
	fi
	@if ! $(FLASHER_O)/host/bin/sunxi-fel version; then \
		echo "ERROR: no Allwinner USB FEL device: connect the USB-C connector, hold SW2 and press SW1 (RESET), see README.md" >&2; \
		exit 1; \
	fi
	$(TESS_DIR)/flash.sh $(FLASHER_O)

# The firmware must come from the esp-hosted-linux commit of the esp-hosted
# package in BUILDROOT: build.sh asks the configured flasher build for it
# and downloads the tarball through it
esp32c3:
	$(call buildroot-configure,$(FLASHER_O),tess_flasher_defconfig)
	BUILDROOT=$(BUILDROOT) O=$(FLASHER_O) TESS_ESP32C3_O=$(ESP32C3_O) $(TESS_DIR)/esp32c3/build.sh

help:
	@echo "make                     flasher image (output/flasher/)"
	@echo "make esp32c3             ESP32-C3 esp-hosted firmware in output/esp32c3/ (ESP-IDF in Docker)"
	@echo "make flash               boot the flasher image over USB (FEL) to flash the ESP32-C3"
	@echo "make flash-sd IMAGE=...  write an image to the SD NAND over USB DFU"
	@echo "make <target>            Buildroot target for the build in O (default: output/flasher),"
	@echo "                         e.g. make menuconfig, make linux-rebuild"
	@echo "make help-buildroot      Buildroot's own help"

help-buildroot:
	$(BR_MAKE) O=$(O) help

# Any other target: Buildroot, for the build in O
.DEFAULT:
	$(BR_MAKE) O=$(O) "$@"
