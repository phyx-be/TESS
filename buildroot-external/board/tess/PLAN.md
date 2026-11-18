# Tess: flasher, ESP32-C3 firmware and USB flashing

Note (2026-11-08): this work moved from a Buildroot fork (branch
feat/add_tess, `board/phyxbe/tess/`, `configs/phyxbe_tess_*_defconfig`)
to this BR2_EXTERNAL tree (`board/tess/`, `configs/tess_*_defconfig`), on
top of the Buildroot branch `phyxbe-tess` that adds the board upstream
(device tree, U-Boot fragment, minimal `phyxbe_tess_defconfig`). The
`esp-hosted` package bump (2a8772c) is superseded by upstream Buildroot
(esp-hosted-linux 54d5367, firmware version NG-1.0.6.0.23): the ESP32-C3
firmware must be rebuilt from that commit, see README.md.

Status (2026-11-17): the flasher image flashes the ESP32-C3; the SD NAND
is written from the host over USB DFU (tested on the board). With
this firmware, WiFi over esp-hosted works on the board (WPA2, DHCP,
internet, 12 Mbit/s, 2026-10-14) and BLE over UART2 (btattach,
bluetoothctl LE scan).

Goals:

- WiFi through the ESP32-C3 using esp-hosted
  (https://github.com/espressif/esp-hosted-linux), with SPI0 as the WiFi
  transport; BLE through the ESP32-C3 using HCI over UART (UART2). This
  tree builds the ESP32-C3 firmware for both.
- A **flasher image**, booted over USB (FEL), that does the initial flash
  of the ESP32-C3 over UART4 with espflash.
- The soldered SD NAND on SDC0 written from the host over USB.

## 1. Hardware

From the schematic (TESS_00.PDF, sheets 2 and 3):

| Function                  | T113-S3               | ESP32-C3                          | Notes                                |
|---------------------------|-----------------------|-----------------------------------|--------------------------------------|
| SPI0 CLK / MOSI / MISO / CS | PC2 / PC4 / PC5 / PC3 | GPIO6 / GPIO7 / GPIO2 / GPIO10  | esp-hosted C3 defaults               |
| SPI handshake             | PC6                   | GPIO3                             | esp-hosted C3 default                |
| SPI data ready            | PD22                  | GPIO4                             | esp-hosted C3 default                |
| UART2 TX / RX             | PE2 / PE3             | GPIO18 (RX) / GPIO5 (TX)          | BLE HCI, firmware default pins       |
| UART2 RTS / CTS           | PE0 / PE1             | GPIO8 (CTS) / GPIO19 (RTS)        | BLE HCI flow control                 |
| UART4 TX / RX (UART_PROG) | PE4 / PE5             | GPIO20 (U0RXD) / GPIO21 (U0TXD)   | ROM bootloader, espflash             |
| ESP.BOOT                  | PE10                  | GPIO9                             | low at reset = download mode         |
| WiFi.EN                   | PE11                  | EN                                | 100K pull-down: ESP off until driven |

Notes:

- The board follows the esp-hosted default ESP32-C3 pinout for both SPI
  and HCI UART, so the firmware needs no pin changes.
- ESP32-C3 GPIO8 and GPIO2 are strapping pins and must be high when the
  ESP leaves reset into download mode. GPIO2 has a pull-up (shared with
  T113 BOOT_SEL1). GPIO8 has a 4K7 pull-up but is also driven by the T113
  UART2 RTS output: UART2 must not be held open (btattach) while the ESP
  is put in download mode.
- GPIO18/GPIO19 are the C3 USB-Serial-JTAG pins; the firmware must not
  enable the USB-Serial-JTAG console. Its log console stays on UART0
  (GPIO20/21), which is UART4 on the T113.
- PC2-PC5 are also the T113 SPI boot pins. The ESP is held in reset by
  the EN pull-down while the T113 boot ROM probes SPI0.
- **UART baud rates:** the T113 UARTs run from a 24 MHz clock (base baud
  1500000), so only 1500000 / n is exact: 1500000, 750000, 500000, ...
  (115200 is 0.16 % off). 460800 and 921600 are 8.5 % and 19 % off and
  do not work. Hence 1500000 for flashing and 500000 for BLE HCI.
- PE10 (BOOT) and PE11 (WiFi.EN) are plain GPIOs for user space
  (libgpiod, line offsets 4 * 32 + 10 = 138 and 139).

Verified on the board (2026-10-07): the `wifi@0` node of the device tree
makes udev load `esp32_spi`, which probes in SPI mode 2 and toggles
WiFi.EN; the ESP32-C3 ROM log is received on ttyS4
(`SPI_FAST_FLASH_BOOT`, blank flash).

## 2. esp-hosted findings

- `espressif/esp-hosted-linux` is the successor of `esp_hosted_ng` from
  `espressif/esp-hosted` (split on 2026-08-03, history kept).
  - Host driver: `host/`, GPL-2.0, built with `target=spi` into
    `esp32_spi.ko` (Buildroot's `esp-hosted` package).
  - Firmware: `esp/esp_driver/network_adapter/`, Apache-2.0, ESP-IDF v6.1
    (commit pinned in `esp/esp_driver/.env`, plus patches and WiFi
    libraries applied by `esp/esp_driver/setup.sh`).
- Device tree support (`compatible = "espressif,esp32-spi"`,
  `reset-gpios`, `handshake-gpios`, `data-ready-gpios`,
  `spi-max-frequency`, `spi-cpol`) exists only on master, not in the
  `release/ng-1.0.6` tag.
- Host driver and firmware versions must match exactly: the driver
  compares version strings and refuses a mismatch. Both must be built from
  the same commit.
- The driver pulses `reset-gpios` at probe (500 ms boot wait) and owns
  that GPIO while bound.
- Bluetooth: with `CONFIG_BT_CTRL_HCI_MODE_UART_H4=y` the firmware
  exposes HCI on UART1 (TX=GPIO5, RX=GPIO18, RTS=GPIO19, CTS=GPIO8) at
  `CONFIG_EXAMPLE_HCI_UART_BAUDRATE` (Tess: 500000), RTS/CTS always on.
  The host driver registers no HCI device in that mode; attach with
  `btattach -B /dev/ttyS2 -P h4 -S 500000`.
- The HCI UART code did not build with ESP-IDF v6.1 (GDMA API change):
  fixed by `esp32c3/patches/0001-*.patch`, sent upstream as
  https://github.com/espressif/esp-hosted-linux/pull/8 (2026-11-12).
- No prebuilt firmware binaries in the repository or the releases.
- The driver supports in-band firmware update over the transport with
  the `ota_file=` module parameter (`docs/guides/ota.md`): a way to update
  the ESP32-C3 application without the flasher.
- Fixed upstream in 2a8772c: with the ESP-IDF v6.1 WiFi libraries the
  firmware kept the data path closed after WPA2 authorization (no DHCP).
  54d5367 also tags the disconnect event with the generation of the
  disconnect command, which replaces our former firmware patch 0002 (late
  disconnect event after `wpa_cli disconnect`).

## 3. ESP32-C3 firmware

- Built outside Buildroot (ESP-IDF downloads several GB of toolchains,
  which does not fit the Buildroot model): `esp32c3/build.sh` (`make
  esp32c3`) builds in the `espressif/idf` Docker image, with
  - the esp-hosted-linux version and tarball of Buildroot's `esp-hosted`
    package, asked from the configured flasher build (`make printvars`),
  - ESP-IDF at the pinned commit with the `setup.sh` patches and WiFi
    libraries (checkout kept in `~/.cache/tess-esp32c3`),
  - `esp32c3/patches/*.patch` applied to esp-hosted-linux,
  - `esp32c3/sdkconfig.defaults.tess`: SPI transport,
    `CONFIG_BT_CTRL_HCI_MODE_UART_H4=y`, HCI at 500000 baud, console on
    UART0 only, USB-Serial-JTAG disabled.
- Output in `output/esp32c3/`, not in git: `tess-esp32c3.bin` (all images
  merged, written at 0x0, used by espflash), the separate
  `bootloader.bin` (0x0), `partition-table.bin` (0x8000),
  `ota_data_initial.bin` (0xd000), `network_adapter.bin` (0x10000),
  `flash_args`, `VERSION` and `SHA256SUMS`. Two OTA partitions on 4 MB
  flash. The flasher build copies it to `/lib/firmware/esp-hosted/`
  (`board/tess/post-build.sh`, which checks `SHA256SUMS`).

## 4. Flasher image: `configs/tess_flasher_defconfig`

Purpose: factory/recovery image for the ESP32-C3. Booted over USB with
sunxi-fel, it flashes the ESP32-C3 over UART4.

- Boot: FEL, `flash.sh` (`make flash`) loads U-Boot, kernel, DTB,
  `boot.scr` and `rootfs.squashfs.uboot` (at `0x43300000`,
  `initrd_high=ffffffff`).
- Root filesystem: **xz squashfs loaded as initrd into `/dev/ram0`**
  (`root=/dev/ram0 ro`, `linux/flasher.frag`: `SQUASHFS`, `SQUASHFS_XZ`,
  `BLK_DEV_RAM` up to 64 MB). It stays compressed in RAM, unlike an
  initramfs, which needs the compressed and the unpacked copy at the
  same time. `post-image.sh` wraps it in a U-Boot ramdisk header. Note:
  classic initrd support is marked for removal in the kernel (only the
  `/linuxrc` path is deprecated in 6.18).
- No Python: esptool 5 needs `rich_click`, which Buildroot does not
  package, plus `python-cryptography`. The flasher uses **espflash**
  (Buildroot package, Rust) instead. espflash only accepted ports listed
  by the serialport crate, which does not list the T113 UARTs: fixed by
  `board/tess/patches/espflash/0001-*.patch`, merged upstream
  (esp-rs/espflash#1122).
- Contents: BusyBox, espflash, the `libgpiod2` tools and the ESP32-C3
  firmware; a login on the USB serial console (ttyGS0) and on UART3. No
  esp-hosted module (it would own WiFi.EN), no network.
- `esp32c3-flash`:
  1. PE10 (BOOT) low, pulse PE11 (EN): ROM download mode (gpioset).
  2. `espflash write-bin --chip esp32c3 --port /dev/ttyS4 --baud 1500000
     --before no-reset --after no-reset --non-interactive 0x0
     tess-esp32c3.bin` (skips unchanged regions, verifies).
  3. Release PE10, reset the ESP, check its boot log on ttyS4. WiFi.EN
     stays driven high by a background gpioset.
- `tess-install` runs `esp32c3-flash`. Run by hand for now.
- Tested 2026-10-07: boots over FEL (squashfs in `/dev/ram0`, 70 MB RAM
  free), espflash writes and verifies the firmware at 1500000 baud.
- Reflashing the ESP32-C3 from a system running on the board, for
  firmware tests: copy `espflash`, `gpioset`, `gpiodetect`,
  `libgpiod.so.3`, `libgpiotools.so.1` and `esp32c3-flash` from
  `output/flasher/target`, stop btattach, `rmmod esp32_spi`, then open and
  close `/dev/ttyS2` once (`stty -F /dev/ttyS2 hupcl`): after btattach,
  UART2 RTS stays asserted and holds GPIO8 low, so the ROM does not enter
  download mode (no output at all on ttyS4).

## 5. SD NAND over USB DFU

- U-Boot 2026.01, as `mangopi_mq1rdw2_defconfig`: `mangopi_mq_r` (same
  T113-S3, DRAM settings and UART3 console), the in-tree
  `board/phyxbe/tess/uboot.fragment` and `uboot/tess-flasher.fragment`
  (the sunxi MUSB gadget, DFU with the MMC back end). No stored
  environment (`ENV_IS_NOWHERE`): booted over FEL, sunxi has no valid
  location for one.
- The default environment (`uboot/tess-flasher.env`) looks at
  `fel_scriptaddr`, which U-Boot's sunxi code sets only when sunxi-fel
  uploaded a boot script along with U-Boot: `flash.sh` does, so U-Boot
  boots the flasher Linux (`uboot/boot.cmd`); `flash-sd.sh` starts U-Boot
  alone, so it runs `dfu 0 mmc 0` with the whole SD NAND as the raw
  `sdcard` entity, and resets the board when dfu-util detaches.
- `flash-sd.sh` (`make flash-sd IMAGE=...`) checks that the board is in
  FEL, starts U-Boot, waits for the DFU device and writes the image with
  dfu-util (a host tool of the flasher build, like sunxi-fel).

## 6. TODO

- BLE throughput: test 2M PHY transfers with a higher HCI baud rate.
  500000 (50 kB/s) can cap a sustained 2M-PHY link; 750000 and 1500000
  are the other exact rates of the T113 UART. Change
  `CONFIG_EXAMPLE_HCI_UART_BAUDRATE` in `esp32c3/sdkconfig.defaults.tess`
  (rebuild and reflash the firmware) and the speed of btattach (`-S`) on
  the board together, measure with WiFi active, keep the highest rate
  without HCI errors.
  - First measurement (2026-11-18, HCI UART at 500000 with RTS/CTS): an
    L2CAP LE credit based channel (`l2test -s/-r -V le_public -P 128 -I
    65535 -O 65535 -b 4096`) between the board and the development PC,
    whose controller is Bluetooth 4.2 (no 2M PHY, LE data length 123
    bytes; the ESP32-C3 offers 251, 12 buffers of 251 bytes). PC central,
    Linux default 30-50 ms interval: 17 kB/s. Board peripheral with
    `conn_min_interval`/`conn_max_interval` 6 in
    `/sys/kernel/debug/bluetooth/hci0/` (it asks the central for 7.5 ms
    with an L2CAP Connection Parameter Update Request, granted): 24-25
    kB/s. As the central, the board grants the PC's own request for
    30-50 ms, so set the interval on the peripheral. 25 kB/s is half of
    what the UART carries: the PC's controller (123-byte packets, about
    1.5 per 7.5 ms event) is the limit, not the HCI UART.
  - Next: repeat with a Bluetooth 5 peer with LE 2M PHY and 251-byte data
    length (a USB dongle, e.g. RTL8761B based, see TEST-RIG.md). Only
    such a peer can exceed 50 kB/s and show whether 500000 caps the link.
- ESP32-C3 firmware update without the flasher: esp-hosted's OTA
  (`ota_file=`). To verify: whether the driver allows OTA while the
  firmware version does not match (it refuses normal operation on a
  mismatch). OTA only updates the application: bootloader and partition
  table changes still need the flasher.
- Upstream: esp-hosted-linux HCI UART fix for ESP-IDF v6.1 (pull request
  8); Buildroot `python-esptool` 5.x misses its `rich_click`/`click`
  dependencies.
- Flasher: `seedrng` cannot write `/var/lib/seedrng` on the read-only
  root (harmless warning); espflash's progress bar floods the console.

## 7. Decisions

1. ESP32-C3 firmware: built from source (`esp32c3/build.sh`), not kept in
   git, copied into the flasher image at build time.
2. `esp-hosted` package: Buildroot's own, so that the firmware and the
   driver of a system built with the same Buildroot match.
3. BLE HCI baud rate: 500000 (exact on the T113 UART).
4. Flashing tool: espflash, no Python in the flasher image.
5. U-Boot version: 2026.01, as the MangoPi defconfig.
6. SD NAND written from the host over USB DFU (2026-11-12): the flasher's
   U-Boot, started alone over FEL (no `fel_scriptaddr`), runs
   `dfu 0 mmc 0` with the whole SD NAND as the raw `sdcard` entity;
   `flash-sd.sh` drives sunxi-fel and dfu-util. Started with the flasher's
   boot script, it boots the flasher Linux, which only flashes the
   ESP32-C3.
   Tested on a board 2026-11-17: `make flash-sd` writes a 205 MB image
   in 3.5 minutes; `make flash` and `tess-install` reflash the ESP32-C3
   (NG-1.0.6.0.23). Fixed on the way: the DFU buffer (8 MiB) did not fit
   U-Boot's 2.1 MiB malloc pool (SYS_MALLOC_LEN 32 MiB); nothing probed
   the MUSB, as USB_ETHER (whose board_late_init probes it, default y on
   sunxi) stays off when the gadget is enabled from a fragment
   (DM_USB_GADGET does not work: the sunxi glue registers its gadget only
   without it); dfu-util exits non-zero after a complete download because
   U-Boot resets the board on detach (flash-sd.sh checks its output); the
   host needs a udev rule for 1f3a:1010 as well as 1f3a:efe8 (README.md);
   `esp32c3-flash` hung the CPU (RCU stall in dw8250_set_termios) with
   `stty` on UART4 while the ESP was still running after espflash: the
   ESP is now held in reset while UART4 changes speed.
