# Tess images, built with Buildroot from this external tree:
#
#   make main      main image in output/ (A/B root filesystems, RAUC)
#   make flasher   flasher image in output-flasher/, after the main image
#                  it embeds (the default target)
#   make flash     boot the flasher image over USB (FEL), see flash.sh
#   make main-<target>, make flasher-<target>
#                  any Buildroot target in that build, e.g. make
#                  main-menuconfig, make flasher-linux-rebuild
#
# BUILDROOT, MAIN_O and FLASHER_O override the Buildroot tree (the
# buildroot submodule) and the output directories. Downloads go to
# BR2_DL_DIR (~/br-dl from ~/.profile).

TESS_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILDROOT ?= $(TESS_DIR)/buildroot
MAIN_O ?= $(TESS_DIR)/output
FLASHER_O ?= $(TESS_DIR)/output-flasher

.PHONY: all main flasher flash

all: flasher

# $(1): output directory, $(2): defconfig name. An output directory that
# has no configuration yet gets its defconfig.
define buildroot-build
	@if [ ! -f $(BUILDROOT)/Makefile ]; then \
		echo "ERROR: no Buildroot in $(BUILDROOT): git submodule update --init" >&2; \
		exit 1; \
	fi
	$(if $(wildcard $(1)/.config),,\
		$(MAKE) -C $(BUILDROOT) BR2_EXTERNAL=$(TESS_DIR) O=$(1) $(2))
	$(MAKE) -C $(BUILDROOT) O=$(1) $(3)
endef

main:
	$(call buildroot-build,$(MAIN_O),tess_defconfig)

flasher: export TESS_MAIN_IMAGE = $(MAIN_O)/images/sdcard.img
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

main-%:
	$(call buildroot-build,$(MAIN_O),tess_defconfig,$*)

flasher-%: export TESS_MAIN_IMAGE = $(MAIN_O)/images/sdcard.img
flasher-%:
	$(call buildroot-build,$(FLASHER_O),tess_flasher_defconfig,$*)
