# Tess: ESP32-C3 WiFi/BLE and image layout plan

Note (2026-11-08): this work moved from a Buildroot fork (branch
feat/add_tess, `board/phyxbe/tess/`, `configs/phyxbe_tess_*_defconfig`)
to this BR2_EXTERNAL tree (`board/tess/`, `configs/tess_*_defconfig`), on
top of the Buildroot branch `phyxbe-tess` that adds the board upstream
(device tree, U-Boot fragment, minimal `phyxbe_tess_defconfig`). Paths
below are the old ones. The `esp-hosted` package bump (2a8772c) is
superseded by upstream Buildroot (esp-hosted-linux 54d5367, firmware
version NG-1.0.6.0.23): the ESP32-C3 firmware must be rebuilt from that
commit, see README.md.

Status (2026-10-14): the flasher image flashes the ESP32-C3 and writes
the main image to the SD NAND, and the main image boots from the SD
NAND. WiFi over esp-hosted works (WPA2, DHCP, internet, 12 Mbit/s) and
BLE over UART2 works (btattach, bluetoothctl LE scan). See section 6.

Goals:

- WiFi through the ESP32-C3 using esp-hosted
  (https://github.com/espressif/esp-hosted-linux), with SPI0 as the WiFi
  transport, a Linux kernel module and a device tree node.
- BLE through the ESP32-C3 using HCI over UART (UART2).
- Two images, each with its own defconfig:
  - a **flasher image**, booted over USB (FEL), that writes the main image
    to the soldered SD NAND on SDC0 and does the initial flash of the
    ESP32-C3 over UART4 with espflash;
  - a **main image**, booting from SDC0 with its root filesystem on SDC0
    (no initramfs), that updates the ESP32-C3 firmware over SPI.

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

Verified on the board (FEL image, 2026-10-07): the `wifi@0` node makes
udev load `esp32_spi`, which probes in SPI mode 2 and toggles WiFi.EN;
the ESP32-C3 ROM log is received on ttyS4 (`SPI_FAST_FLASH_BOOT`, blank
flash).

## 2. esp-hosted findings

- `espressif/esp-hosted-linux` is the successor of `esp_hosted_ng` from
  `espressif/esp-hosted` (split on 2026-08-03, history kept).
  - Host driver: `host/`, GPL-2.0, built with `target=spi` into
    `esp32_spi.ko`.
  - Firmware: `esp/esp_driver/network_adapter/`, Apache-2.0, ESP-IDF v6.1
    (commit pinned in `esp/esp_driver/.env`, plus patches and WiFi
    libraries applied by `esp/esp_driver/setup.sh`).
- Device tree support (`compatible = "espressif,esp32-spi"`,
  `reset-gpios`, `handshake-gpios`, `data-ready-gpios`,
  `spi-max-frequency`, `spi-cpol`) exists **only on master**, not in the
  `release/ng-1.0.6` tag. Pinned master commit: `2a8772c` (2026-10-08).
- Host driver and firmware versions must match exactly: the driver
  compares version strings and refuses a mismatch. Both are built from
  the same commit and report `NG-1.0.6.0.15`.
- The driver builds without warnings for ARM32 against 6.18.8.
- The driver pulses `reset-gpios` at probe (500 ms boot wait) and owns
  that GPIO while bound.
- Bluetooth: with `CONFIG_BT_CTRL_HCI_MODE_UART_H4=y` the firmware
  exposes HCI on UART1 (TX=GPIO5, RX=GPIO18, RTS=GPIO19, CTS=GPIO8) at
  `CONFIG_EXAMPLE_HCI_UART_BAUDRATE` (Tess: 500000), RTS/CTS always on.
  The host driver registers no HCI device in that mode; attach with
  `btattach -B /dev/ttyS2 -P h4 -S 500000`.
- The HCI UART code did not build with ESP-IDF v6.1 (GDMA API change):
  fixed by `esp32c3/patches/0001-*.patch`, to be sent upstream.
- No prebuilt firmware binaries in the repo or the releases.
- The driver supports in-band firmware update over the transport with
  the `ota_file=` module parameter (`docs/guides/ota.md`). This is the
  update path for the main image.

## 3. Common parts (both images)

### 3.1 Kernel module package (done)

- `package/esp-hosted` points to `esp-hosted-linux` at the pinned
  commit: `ESP_HOSTED_MODULE_SUBDIRS = host`, `target=spi`, license file
  `host/LICENSE`. The Linux 7.1 build fix patch was dropped (already in
  master). Kept upstreamable for Buildroot.
- Dropped `board/phyxbe/tess/patches/esp-hosted/0001-dt-fixes.patch`; the
  `esp-hosted-sergey` override in the (untracked) `local.mk` is
  commented out.
- Kernel config: `bluetooth.frag` (`CONFIG_BT`, `CONFIG_BT_HCIUART`,
  `CONFIG_BT_HCIUART_H4`). `CONFIG_BT` must be in the fragment itself,
  `sunxi_defconfig` has it disabled. `CONFIG_CFG80211` is already on.

### 3.2 Device tree (done)

```dts
aliases {
	serial2 = &uart2;	/* ttyS2: ESP32-C3 BLE HCI */
	serial3 = &uart3;	/* ttyS3: console */
	serial4 = &uart4;	/* ttyS4: ESP32-C3 programming */
	serial5 = &uart5;	/* ttyS5: feather */
};

&spi0 {
	wifi@0 {
		compatible = "espressif,esp32-spi";
		reg = <0>;
		spi-max-frequency = <30000000>;
		spi-cpol;					/* SPI mode 2 */
		reset-gpios = <&pio 4 11 GPIO_ACTIVE_LOW>;	/* PE11 WiFi.EN */
		handshake-gpios = <&pio 2 6 GPIO_ACTIVE_HIGH>;	/* PC6 */
		data-ready-gpios = <&pio 3 22 GPIO_ACTIVE_HIGH>; /* PD22 */
	};
};

&uart2 {
	uart-has-rtscts;
};
```

- The unused `gpio_out_pe_pins` group is dropped. PE10 (BOOT) is a plain
  GPIO for user space (libgpiod, line offset 4 * 32 + 10 = 138, PE11 is
  139).

### 3.3 ESP32-C3 firmware (done)

- Built outside Buildroot (ESP-IDF downloads several GB of toolchains,
  which does not fit the Buildroot model): `esp32c3/build.sh` builds in
  the `espressif/idf` Docker image, with
  - the esp-hosted-linux commit read from `package/esp-hosted/esp-hosted.mk`,
  - ESP-IDF at the pinned commit with the `setup.sh` patches and WiFi
    libraries (checkout kept in `~/.cache/tess-esp32c3`),
  - `esp32c3/patches/*.patch` applied to esp-hosted-linux,
  - `esp32c3/sdkconfig.defaults.tess`: SPI transport,
    `CONFIG_BT_CTRL_HCI_MODE_UART_H4=y`, HCI at 500000 baud, console on
    UART0 only, USB-Serial-JTAG disabled.
- Output, committed in `rootfs_overlay_flasher/lib/firmware/esp-hosted/`:
  `tess-esp32c3.bin` (all images merged, written at 0x0, used by
  espflash), the separate `bootloader.bin` (0x0), `partition-table.bin`
  (0x8000), `ota_data_initial.bin` (0xd000), `network_adapter.bin`
  (0x10000), `flash_args`, `VERSION` and `SHA256SUMS`. Two OTA
  partitions on 4 MB flash.

### 3.4 U-Boot (done)

U-Boot 2026.01, the same as `mangopi_mq1rdw2_defconfig`, in both images:

- `BR2_TARGET_UBOOT_BOARD_DEFCONFIG="mangopi_mq_r"` (same T113-S3, DRAM
  settings and UART3 console) plus `uboot/tess.fragment`:
  - `CONFIG_DEFAULT_DEVICE_TREE="sun8i-t113s-tess"` with `OF_UPSTREAM`
    off: Buildroot copies the Tess DTS to `arch/arm/dts`
    (`BR2_TARGET_UBOOT_CUSTOM_DTS_PATH`).
  - `CONFIG_OF_LIBFDT_OVERLAY=y`, for device tree overlays (extlinux
    `fdtoverlays`).
  - `CONFIG_ENV_IS_NOWHERE` instead of `ENV_IS_IN_FAT`: there is no FAT
    partition, the environment is not stored.
- One Tess DTS (`sun8i-t113s-tess.dts`) for Linux and U-Boot. It includes
  `<arm/allwinner/sun8i-t113s.dtsi>`, which resolves in both builds. The
  separate U-Boot DTS, `uboot/tess_defconfig` and `uboot/uenv.txt` are gone.
- `BR2_TARGET_UBOOT_NEEDS_GNUTLS=y`; hash in `patches/uboot/uboot.hash`.
- Tested: FEL boot of the flasher (boot.scr), `tess-install`, distro boot
  from the SD NAND (extlinux), reboot, USB console.

## 4. Flasher image: `configs/phyxbe_tess_flasher_defconfig` (works)

Purpose: factory/recovery image. Booted over USB with sunxi-fel, writes
the main image to SDC0 and flashes the ESP32-C3 over UART4.

- Boot: FEL, `board/phyxbe/tess/flash.sh output-flasher` loads U-Boot,
  kernel, DTB, `boot.scr` and `rootfs.squashfs.uboot` (at `0x43300000`,
  `initrd_high=ffffffff`).
- Root filesystem: **xz squashfs loaded as initrd into `/dev/ram0`**
  (`root=/dev/ram0 ro`, `flasher.frag`: `SQUASHFS`, `SQUASHFS_XZ`,
  `BLK_DEV_RAM` up to 64 MB). It stays compressed in RAM, unlike an
  initramfs, which needed the compressed and the unpacked copy at the
  same time and did not fit in the 128 MB (about 80 MB free) with Python.
  `post-image-flasher.sh` wraps it in a U-Boot ramdisk header. Note:
  classic initrd support is marked for removal in the kernel (only the
  `/linuxrc` path is deprecated in 6.18).
- No Python: esptool 5 needs `rich_click`, which Buildroot does not
  package, plus `python-cryptography`. The flasher uses **espflash**
  (Buildroot package, Rust) instead. espflash only accepted ports listed
  by the serialport crate, which does not list the T113 UARTs: fixed by
  `package/espflash/0001-*.patch` (to be sent upstream).
- Contents: BusyBox, espflash, `libgpiod2` tools, e2fsprogs, the
  ESP32-C3 firmware and the main image (`/usr/share/tess/sdcard.img.xz`,
  xz -6 so busybox xzcat needs little RAM, plus `sdcard.img.info` with
  its size and SHA-256), added by `post-build-flasher.sh` from
  `output/images/sdcard.img`. The main image must be built first.
- No esp-hosted module (it would own WiFi.EN), no WiFi packages.
- `esp32c3-flash`:
  1. PE10 (BOOT) low, pulse PE11 (EN): ROM download mode (gpioset).
  2. `espflash write-bin --chip esp32c3 --port /dev/ttyS4 --baud 1500000
     --before no-reset --after no-reset --non-interactive 0x0
     tess-esp32c3.bin` (skips unchanged regions, verifies).
  3. Release PE10, reset the ESP, check its boot log on ttyS4. WiFi.EN
     stays driven high by a background gpioset.
- `tess-install`: run `esp32c3-flash` first (on failure the SD NAND is
  left untouched), then write `sdcard.img.xz` to `/dev/mmcblk0` and verify it
  against the SHA-256. Run by hand for now.
- Once the SD NAND has a boot image, FEL needs SW2 + SW1 again (a
  `reboot` boots the SD NAND). If the buttons do not work (2026-10-14:
  four tries, the board kept booting the SD NAND), zero the SPL header
  from the main image and reboot, the BROM then falls back to FEL:
  `dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=16 count=2 conv=fsync`
  (the image has no second SPL copy at 128 KiB).
- Tested 2026-10-07: boots over FEL (squashfs in `/dev/ram0`, 70 MB RAM
  free), `tess-install` takes 1.5 minutes (espflash at 1500000 baud,
  verified, then the SD NAND written and verified).

## 5. Main image: `configs/phyxbe_tess_defconfig` (boots from the SD NAND)

Purpose: the normal product image, booting on its own from the SD NAND.

- Done: no initramfs. The boot script and sunxi-fel host tools moved to
  the flasher.
- **Storage layout (A/B with RAUC), `genimage.cfg`**: U-Boot with SPL at
  8 KiB; U-Boot environment at 1 MiB (two redundant 64 KiB copies, raw,
  not a partition); `mmcblk0p1` rootfs A and `mmcblk0p2` rootfs B (96 MiB
  ext4 each, both written by the image, mounted read-only); `mmcblk0p3`
  data (ext4, `/data`, the rest of the SD NAND: 284 MiB on 480 MiB).
  The image (196 MiB) and `tess-install` stop before the data partition,
  so a reinstall keeps the data. `S00datafs` adds the partition when the
  table has none (busybox `fdisk`, from the first 4 MiB boundary after
  `mmcblk0p2` to the end of the disk, so the same place every time and
  all of a bigger SD card), then reboots once: the kernel cannot re-read
  the table of a disk with a mounted partition, and there is no `partx`
  in the image.
- **Boot**: `tess_boot` in U-Boot's default environment
  (`patches/uboot/0001-*.patch` adds `board/sunxi/tess.env`,
  `uboot/tess-main.fragment` selects it and the MMC environment) walks
  `BOOT_ORDER`, decrements `BOOT_x_LEFT`, saves the environment and runs
  `sysboot` on `/boot/extlinux/extlinux.conf` of that slot; the append
  line gets `root=/dev/mmcblk0p${tess_part} ro rauc.slot=${tess_slot}`.
  `bootcmd` reloads `tess_boot` from the default environment first, so a
  saved environment cannot pin an old script. The flasher keeps
  `ENV_IS_NOWHERE`: booted over FEL, sunxi has no valid location for an
  MMC environment and U-Boot would hang.
- **RAUC** 1.15 (`/etc/rauc/system.conf`, `bootloader=uboot`,
  `fw_setenv` from libubootenv, `/etc/fw_env.config`); verity bundles
  (kernel: loop, squashfs, dm-verity, `rauc.frag`);
  `output/images/tess-update.raucb` from `post-image-main.sh`, signed with
  the development key in `rauc/` (or `TESS_RAUC_KEY`/`TESS_RAUC_CERT`).
  `use-bundle-signing-time=true`: the board has no RTC, its clock starts
  in 1970 and a new certificate is "not yet valid". `S99rauc-mark-good`.
- **Read-only root, persistent directories**: `S00datafs` mounts `/data`
  (e2fsck, mkfs only without a filesystem, tmpfs fallback) and
  bind-mounts `/etc/dropbear`, `/etc/wpa_supplicant`, `/var/lib`,
  `/var/log` from `/data/rootfs`, copying entries missing there from the
  rootfs. `post-build-main.sh` turns the skeleton links `/var/log` and
  `/etc/dropbear` into directories. WiFi: `rc.netif` uses
  `/etc/wpa_supplicant/wpa_supplicant.conf`, seeded from the image by
  `S00datafs`.
- Tested 2026-10-14: first boot from the default environment (slot A),
  data filesystem created on the first boot, binds and WiFi ok, dropbear
  host key kept; `rauc install` to B, boot B, mark-good; slot A wiped and
  set first: three failed attempts, then B; A restored with
  `rauc install`.
- `reboot` needs the watchdog: the SoC dtsi has it `reserved`, the Tess
  DTS enables it, so `sunxi-wdt` provides the restart handler.
- Tested 2026-10-07: SPL, U-Boot distro boot (extlinux), ext4 root on
  `mmcblk0p1`. esp32_spi gets the boot-up event, detects the ESP32-C3,
  switches SPI to 30 MHz, versions match (`NG-1.0.6.0.14`), wlan0
  appears and wpa_supplicant scans (5 scans in a row, no errors).
- **Fixed: SPI command timeouts.** Commands timed out (`CMD_TIMEOUT`)
  and their response came with the next command (`CMD_RESP_MISMATCH`).
  Cause: the T113 pin controller samples GPIO interrupts with the 32 kHz
  LOSC by default (`Px_EINT_DEB` reset value 0), so it missed the short
  ESP32-C3 handshake/data-ready pulses. Fix in the Tess DTS:
  `&pio { input-debounce = <1 1 1 1 1 1>; }` (HOSC, 750 kHz sampling).
- **Fixed upstream: no data after connecting.** With WPA2 the driver and
  the firmware keep the data path closed (EAPOL only) until
  `CMD_STA_SET_AUTHORIZED`. The ESP-IDF v6.1 Wi-Fi libraries changed
  `esp_wifi_auth_done_internal()` to return true on success, so the
  firmware's check was inverted and the command always failed: no DHCP.
  Bisected to `4ddec53` (merge of feature/idf-v6.1; `ffe2af4` with
  ESP-IDF v5.5.1 works). Fixed upstream in `2a8772c` ("hosted: fix STA
  data port not opening after authorization"), which replaces our former
  firmware patch 0002. Tested 2026-10-14 (`NG-1.0.6.0.15`, no patch
  0002): WPA2-PSK `COMPLETED`, DHCP, ping, DNS, 10 MB download in 7 s
  (12 Mbit/s), no SPI timeouts.
- **Fixed: reconnect.** After `wpa_cli disconnect` + `reconnect` (or
  restarting wpa_supplicant) the station looped on `auth timeout` and
  `Drop DISCONNECT_EVENT for unexpected generation` until `esp32_spi`
  was reloaded. The firmware handles `CMD_DISCONNECT` with
  `esp_wifi_deauthenticate_internal()`: the station goes `run -> init`,
  but the v6.1 Wi-Fi library posts `WIFI_EVENT_STA_DISCONNECTED` only
  when the next connection attempt ends. cfg80211 kept the old
  connection, the new auth retired the pending disconnect, and the late
  event was dropped; on its own the driver times out after 5 s and
  resets the ESP. `esp32c3/patches/0002-*.patch` uses
  `esp_wifi_disconnect()`, which posts the event at once (deauth reason
  8 instead of the host's reason). Tested 2026-10-14: 5 disconnect +
  reconnect cycles back to `COMPLETED` in 2 s each, ping ok, plus a
  wpa_supplicant restart; no dropped events. To report upstream.
- Reflashing the ESP32-C3 from the main image, for firmware tests:
  copy `espflash`, `gpioset`, `gpiodetect`, `libgpiod.so.3`,
  `libgpiotools.so.1` and `esp32c3-flash` from `output-flasher/target`,
  stop btattach, `rmmod esp32_spi`, then open and close `/dev/ttyS2`
  once (`stty -F /dev/ttyS2 hupcl`): after btattach, UART2 RTS stays
  asserted and holds GPIO8 low, so the ROM does not enter download mode
  (no output at all on ttyS4).
- WiFi configuration: `/etc/wpa_supplicant/wpa_supplicant.conf`; `/etc/rc.netif` (udev)
  starts wpa_supplicant and ifplugd/udhcpc when wlan0 appears.
- `iwlist` cannot scan (no WEXT), use `iw` or wpa_supplicant.
- **Fixed: regulatory.db.** cfg80211 is built in (the esp-hosted package
  forces `CONFIG_CFG80211=y`) and tries to load `regulatory.db` before
  the root filesystem is mounted. After that failure the kernel never
  retries (`regdb = ERR_PTR(-ENODATA)`), so `iw reg set` was silently
  ignored. `/etc/init.d/S45regdb` runs `iw reg reload` and, if set in
  `/etc/default/regdomain`, `iw reg set $REGDOMAIN` (empty by default:
  world domain). esp-hosted logs `Regulatory domain 00 apply failed`
  during the reload (the firmware refuses the world domain), harmless.
- **Fixed: BLE.** `btattach` from BlueZ 5.86 ORs the speed into
  `c_cflag`, which gives B0 (hang up, RTS/DTR dropped) with glibc >= 2.42,
  where `B500000` is 500000: the controller never answered HCI Reset.
  Backported the upstream fix (`package/bluez5_utils/0001-*.patch`).
  Tested: `btattach -B /dev/ttyS2 -P h4 -S 500000`, bluetoothctl LE scan
  finds devices. `bluetoothctl` needs commands on stdin when not run
  interactively.
- WiFi/BLE packages: `esp-hosted`, `wpa_supplicant` (nl80211),
  `wireless-regdb`, `iw`, `bluez5_utils` (client, monitor, tools); to
  add: `network_adapter.bin` for OTA. No Python, no espflash.
- Boot sequence (init script, to do):
  1. `modprobe esp32_spi` (udev already loads it from the device tree).
  2. If the ESP firmware version differs from the module version: load
     with `ota_file=/lib/firmware/esp-hosted/network_adapter.bin`, let
     the driver write the new app to the inactive OTA partition and
     reset the ESP, then load normally.
  3. `btattach -B /dev/ttyS2 -P h4 -S 500000`: done, `/etc/init.d/S41btattach`
     (arguments in `/etc/default/btattach`) waits up to 20 s for wlan0,
     i.e. for the ESP32-C3 firmware to run, then starts btattach.
- To verify: whether the driver allows OTA while the firmware version
  does not match (it refuses normal operation on mismatch). If not, the
  OTA must happen with the old module before the module is updated,
  or the version check needs a patch.
- OTA only updates the application. Bootloader and partition table
  changes still need the flasher image.

## 6. Steps

1. ~~Buildroot 2026.08 / kernel 6.18.8 bring-up.~~ Done, display works.
2. ~~Kernel module and device tree.~~ Done, probes on the board.
3. ~~Firmware build script and binaries.~~ Done.
4. ~~Flasher image: espflash, squashfs root, `tess-install`.~~ Done.
5. Main image from the SD NAND: boots, WiFi scans work (SPI timeouts
   fixed with `input-debounce`), BLE scans work (btattach fix),
   regulatory.db loads (S45regdb), WPA2 + DHCP work (fixed upstream in
   `2a8772c`), reconnect works (firmware patch 0002).
6. Main image: ~~data partition, A/B root filesystems with RAUC~~ (done);
   OTA update of the ESP firmware.
7. ~~U-Boot update (section 3.4).~~ Done, U-Boot 2026.01.
8. Update `readme.txt` for both images.

Related TODOs:

- `board/tess/patches/linux/0001-fix-dsi-clk.patch` (sun8i_tcon_top:
  register the TCON TOP clock gates in probe instead of the component
  bind, a bring-up hack from December 2024 for the DSI path): test a
  build without it on the board; drop it if the display still comes up,
  otherwise turn it into a proper fix and send it upstream.
- BLE throughput: test 2M PHY transfers with a higher HCI baud rate.
  500000 (50 kB/s) can cap a sustained 2M-PHY link; 750000 and 1500000
  are the other exact rates of the T113 UART. Change
  `CONFIG_EXAMPLE_HCI_UART_BAUDRATE` in `esp32c3/sdkconfig.defaults.tess`
  (rebuild and reflash the firmware) and `BTATTACH_ARGS` in
  `rootfs_overlay/main/etc/default/btattach` together, measure with
  the display and WiFi active, keep the highest rate without HCI errors.
- `patches/bluez5_utils/0001-btattach-*.patch` (upstream bluez commit
  12f5eb72, 2026-09-03): needed with glibc >= 2.42 whatever the baud
  rate, as unpatched btattach ORs the numeric speed into c_cflag. Drop it
  once Buildroot's bluez5_utils is newer than 5.87 (still 5.87 on
  2026-11-11); the alternative without the patch is the deprecated
  hciattach (`BR2_PACKAGE_BLUEZ5_UTILS_DEPRECATED`), which uses
  cfsetospeed.
- ~~Move the Raspberry Pi 7" DSI display into a device tree overlay.~~
  Done: `rpi-7inch-dsi-overlay.dts`, applied by U-Boot (extlinux
  `fdtoverlays` in the main image, `fdt apply` in the flasher boot
  script); the base DTB is built with symbols
  (`BR2_LINUX_KERNEL_DTB_OVERLAY_SUPPORT`). Linux 6.18 cannot build a
  single `.dtbo` in `arch/arm/boot/dts`, so the overlay is named `.dts`
  and built as `rpi-7inch-dsi-overlay.dtb` (the kbuild patch that worked
  around it is gone).
- Upstream: esp-hosted-linux: firmware patch 0002 (late disconnect
  event with the v6.1 Wi-Fi libraries); esp-hosted-linux HCI UART fix for ESP-IDF v6.1; Buildroot
  `esp-hosted` package update; espflash patch for non-enumerated ports;
  Buildroot `bluez5_utils` btattach backport; kbuild patch for single
  `.dtbo` targets;
  Buildroot `python-esptool` 5.x misses its `rich_click`/`click`
  dependencies.
- Flasher: `seedrng` cannot write `/var/lib/seedrng` on the read-only
  root (harmless warning); espflash's progress bar floods the console.

## 7. Decisions

1. Firmware binaries: committed in this repository, in the flasher
   rootfs overlay.
2. `esp-hosted` package: Buildroot's own package is updated
   (upstreamable).
3. Flasher: the main image is embedded in the flasher image and written
   by `tess-install` on the board.
4. BLE HCI baudrate: 500000 (exact on the T113 UART).
5. Flashing tool: espflash, no Python in the flasher image.
6. U-Boot version: 2026.01, as the MangoPi defconfig (done).
