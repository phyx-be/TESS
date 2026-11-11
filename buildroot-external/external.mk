include $(sort $(wildcard $(BR2_EXTERNAL_TESS_PATH)/package/*/*.mk))

# Build both images and flash them, from any configured output directory
# of this tree (make -C output-flasher tess-flasher). The flasher image
# embeds the main image, so tess-flasher builds the main image first.
#
#   tess-main     main image in $(TESS_MAIN_O) (default: output)
#   tess-flasher  flasher image in $(TESS_FLASHER_O) (default: output-flasher)
#   tess-flash    boot the flasher image over USB (FEL), see flash.sh
#
# An output directory that has no configuration yet gets its defconfig.
TESS_DIR = $(BR2_EXTERNAL_TESS_PATH)
TESS_MAIN_O ?= $(TESS_DIR)/output
TESS_FLASHER_O ?= $(TESS_DIR)/output-flasher

# $(1): output directory, $(2): defconfig name
define tess-build
	$(if $(wildcard $(1)/.config),,\
		$(MAKE) -C $(TOPDIR) BR2_EXTERNAL=$(TESS_DIR) O=$(1) $(2))
	$(MAKE) -C $(TOPDIR) O=$(1)
endef

.PHONY: tess-main tess-flasher tess-flash

tess-main:
	$(call tess-build,$(TESS_MAIN_O),tess_defconfig)

tess-flasher: export TESS_MAIN_IMAGE = $(TESS_MAIN_O)/images/sdcard.img
tess-flasher: tess-main
	$(call tess-build,$(TESS_FLASHER_O),tess_flasher_defconfig)

# sunxi-fel (host-sunxi-tools of the flasher build) first checks that the
# board is in FEL: hold SW2 and press SW1 (RESET) with the USB-C connected
tess-flash:
	@if [ ! -x $(TESS_FLASHER_O)/host/bin/sunxi-fel ]; then \
		echo "ERROR: $(TESS_FLASHER_O)/host/bin/sunxi-fel not found, build the flasher image first (tess-flasher)" >&2; \
		exit 1; \
	fi
	@if ! $(TESS_FLASHER_O)/host/bin/sunxi-fel version; then \
		echo "ERROR: no Allwinner USB FEL device: connect the USB-C connector, hold SW2 and press SW1 (RESET), see README.md" >&2; \
		exit 1; \
	fi
	$(TESS_DIR)/flash.sh $(TESS_FLASHER_O)
