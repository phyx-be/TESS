# Ideas for a next Tess revision

Hardware ideas, not planned work. Collected 2026-11-18; the software TODOs
are in `buildroot-external/board/tess/PLAN.md`.

## eMMC on SMHC2, with the boot loader in its boot partitions

The T113-S3 boots from SMHC2 (its eMMC controller, eMMC 5.0, 1 or 4 bit:
SDC2-CLK, CMD, D0-D3 on PC2-PC7), per the user manual (v1.1, 3.4.2.1):

- Boot select pins 11: SMHC0, then the eMMC boot partition (EMMC2_BOOT),
  then the eMMC user area (EMMC2_USR), then the other media. The boot
  select pins are PC4 (BOOT-SEL0) and PC5 (BOOT-SEL1), which are SDC2-D2
  and SDC2-D1: the pull-ups an eMMC needs on its data lines give mode 11
  without extra parts.
- eFuse boot select: 010 is SMHC2 only; the try mode ends with SMHC2.

What it would bring: RAUC's `boot-emmc` slot type. U-Boot (with the SPL,
472 KiB) goes into the inactive one of the eMMC hardware boot partitions
(boot0/boot1, usually 2-4 MiB each), then RAUC switches the boot partition
enable of the eMMC (`mmc bootpart enable`): an atomic boot loader update,
no size limit, no SPL fallback logic, the setup most RAUC users have. U-Boot
documents eMMC boot partitions for Allwinner SoCs in general
(`doc/board/allwinner/sunxi.rst`: U-Boot at the first sector of the enabled
boot partition); to be verified on a T113.

SMHC0 stays first in mode 11: with a microSD socket on SMHC0 instead of the
SD NAND, a card overrides the eMMC, a recovery path without FEL.

What is in the way: PC2-PC7 are SPI0, the link to the ESP32-C3 (see below).

## Moving the ESP32 off SPI0

esp-hosted (Buildroot's esp-hosted-linux 54d5367, `docs/reference/`)
carries Wi-Fi over these transports only; there is no UART transport for
Wi-Fi, UART only carries Bluetooth HCI (as UART2 does on Tess today):

| Transport | ESP targets | Host side | Peak TCP (esp-hosted docs) |
|---|---|---|---|
| SPI, full duplex (Tess today) | ESP32, S2, S3, S31, C2, C3, C5, C6, C61 | SPI controller, reset, Handshake and Data Ready GPIOs | C3: 15.8 Mbps |
| SPI-HD (dual/quad, no Handshake) | S2, S3, C2, C3, C5, C6, C61, S31 | quad-capable SPI controller, Data Ready GPIO | |
| SDIO | ESP32, C5, C6, C61 (not the C3) | SD/SDIO controller | C6: 55.6, C5: 63.3 Mbps |
| USB 2.0 High Speed | ESP32-S31 | USB host | |

The T113 has two SPI controllers: SPI0 only on PC2-PC7 (shared with
SMHC2) and SPI1 only on PD10-PD15 (the Feather SPI). Options:

1. **ESP32-C6 (or C5 for 5 GHz, C61) over SDIO on SMHC1.** SMHC1 (PG0-PG5)
   is the T113's SDIO controller, meant for Wi-Fi. Frees SPI0 and the
   Handshake (PC6) and Data Ready (PD22) GPIOs; about 3.5 times the
   throughput; Bluetooth can go over SDIO too (`radio_service=bt`), which
   frees UART2 and its RTS/strapping trap (ESP GPIO8). Costs: a new
   module and firmware target (Buildroot's esp-hosted package has the SDIO
   option); PG0-PG5 are on the P4 expansion header today and PG3 is the
   Feather pin G3, so those move. Recommended if the board gets eMMC.
2. **ESP32-C3 on SPI1, shared with the Feather SPI.** No new chip: the ESP
   side keeps its pins, the T113 side moves to PD11-PD13 with a GPIO chip
   select and two other IRQ-capable GPIOs for Handshake and Data Ready.
   Costs: the Feather SPI bus carries the Wi-Fi traffic (shared bandwidth,
   30 MHz on header stubs), FeatherWings on SPI see it, and a FeatherWing
   that holds MISO without its chip select breaks Wi-Fi.
3. **ESP32-S31 over USB on USB1.** No sideband GPIOs, USB High Speed. Costs:
   a new and less common chip, and USB1 is the host port on P6 today (a
   hub would keep one port free).
4. **UART**: not with esp-hosted. ESP-AT firmware with PPP over UART would
   give a slow link (1.5 Mbaud, about 150 kB/s) that is not a cfg80211
   Wi-Fi interface (no `wpa_supplicant`, no scans from Linux). Not
   recommended.

SPI-HD alone does not free SDC2: it still needs one of the two SPI
controllers.

## Software-selected boot order: the RTC Fast Boot register

User manual 3.4.2.7: if the RTC register at 0x07090120 is not zero, the
boot ROM uses its bits 31:28 as the boot order of that boot (1: try
process, 2: SMHC0 then eMMC user then eMMC boot, 3: SMHC0 then SPI NOR, 4:
SMHC0 then SPI NAND, 5: eMMC boot then eMMC user, 6 and 7: SMHC0 then the
try process); bits 28:0 record media information. Test whether Linux can
write it (the RTC general purpose registers next to it can, see
`tess-fel`) and whether it survives a watchdog reset: a running system
could then pick the medium of its next boot, e.g. to boot a recovery
system from another medium once.
