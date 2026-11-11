# Tess images, built with Buildroot from this external tree:
#
#   make flasher   the main image in output-main/, then the flasher image in
#                  output-flasher/, which embeds it (the default target)
#   make main      only the main image
#   make flash     boot the flasher image over USB (FEL), see flash.sh
#   make esp32c3   ESP32-C3 esp-hosted firmware in output-esp32c3/, which
#                  the flasher image embeds and flashes; build it before
#                  the flasher (esp32c3/build.sh, ESP-IDF in Docker)
#   make <target>  any other target goes to Buildroot for the build in O
#                  (default: output-main, the main image), e.g.
#                  make menuconfig, make O=output-flasher linux-rebuild
#
# BUILDROOT, MAIN_O, FLASHER_O and ESP32C3_O override the Buildroot tree
# (the buildroot submodule) and the output directories. Downloads go to
# BR2_DL_DIR (~/br-dl from ~/.profile).

TESS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILDROOT ?= $(TESS_DIR)/buildroot
MAIN_O ?= $(TESS_DIR)/output-main
FLASHER_O ?= $(TESS_DIR)/output-flasher
ESP32C3_O ?= $(TESS_DIR)/output-esp32c3

# Build that the pass-through targets go to
ifneq ("$(origin O)", "command line")
O := $(MAIN_O)
else
override O := $(abspath $(O))
endif

BR_MAKE = $(MAKE) -C $(BUILDROOT) BR2_EXTERNAL=$(TESS_DIR)

.PHONY: all main flasher flash esp32c3 help

all: flasher

# $(1): output directory, $(2): defconfig name. An output directory that
# has no configuration yet gets its defconfig.
define buildroot-build
	@if [ ! -f $(BUILDROOT)/Makefile ]; then \
		echo "ERROR: no Buildroot in $(BUILDROOT): git submodule update --init" >&2; \
		exit 1; \
	fi
	$(if $(wildcard $(1)/.config),,$(BR_MAKE) O=$(1) $(2))
	$(BR_MAKE) O=$(1)
endef

main:
	$(call buildroot-build,$(MAIN_O),tess_defconfig)

flasher: export TESS_MAIN_IMAGE = $(MAIN_O)/images/sdcard.img
flasher: export TESS_ESP32C3_O = $(ESP32C3_O)
flasher: main
	$(call buildroot-build,$(FLASHER_O),tess_flasher_defconfig)

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
# package in BUILDROOT; build.sh reads it there and downloads the tarball
# through the main build (O)
esp32c3:
	BUILDROOT=$(BUILDROOT) O=$(MAIN_O) TESS_ESP32C3_O=$(ESP32C3_O) $(TESS_DIR)/esp32c3/build.sh

help:
	@echo "make flasher      main image (output-main/) then flasher image (output-flasher/)"
	@echo "make main         main image only"
	@echo "make flash        boot the flasher image over USB (FEL)"
	@echo "make esp32c3      ESP32-C3 esp-hosted firmware in output-esp32c3/ (ESP-IDF in Docker)"
	@echo "make <target>     Buildroot target for the build in O (default: output-main),"
	@echo "                  e.g. make menuconfig, make O=output-flasher linux-rebuild"
	@echo "make O=... help   Buildroot's own help"

# Any other target: Buildroot, for the build in O
.DEFAULT:
	$(BR_MAKE) O=$(O) "$@"
