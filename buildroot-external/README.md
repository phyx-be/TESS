# Tess Buildroot external tree

Buildroot `BR2_EXTERNAL` tree for the Phyx Tess board (Allwinner T113-S3,
ESP32-C3 WiFi/BLE co-processor, Adafruit Feather form factor).

Basic board support lives in Buildroot itself, on the branch
`phyxbe-tess` (upstream `master` plus one commit adding
`board/phyxbe/tess/` and the minimal `phyxbe_tess_defconfig`, to be
submitted as a pull request to https://github.com/buildroot/buildroot).
This tree builds on that branch and adds everything that is not
upstream material:

- `configs/tess_defconfig`: the main image, booting from the SD NAND
  with A/B root filesystems, RAUC updates, a data partition, WiFi (esp-hosted),
  BLE (btattach), USB serial console and the Raspberry Pi 7" DSI display
- `configs/tess_flasher_defconfig`: the flasher image, booted over USB
  (FEL), that flashes the ESP32-C3 and writes the main image to the SD NAND
- `board/tess/`: the files of both images (scripts, kernel and U-Boot
  fragments, patches, RAUC development key, ESP32-C3 firmware) and the
  root filesystem overlays in `rootfs_overlay/`: `common` for both images,
  `main` and `flasher` for one of them

From Buildroot it reuses `board/phyxbe/tess/sun8i-t113s-tess.dts` (the
device tree, shared by Linux and U-Boot) and
`board/phyxbe/tess/uboot.fragment`.

## Layout

```
buildroot/          Buildroot, branch phyxbe-tess (not in this repository)
configs/            tess_defconfig, tess_flasher_defconfig
board/tess/         board files, see below
output/             main image build (not in this repository)
output-flasher/     flasher image build (not in this repository)
```

## Buildroot checkout

`buildroot/` is a checkout of the `phyxbe-tess` branch. Locally it is a
git worktree of the shared bare clone:

```
git -C ~/development/buildroot.git worktree add buildroot phyxbe-tess
```

Elsewhere, clone the branch from the fork that carries it:

```
git clone -b phyxbe-tess https://github.com/phyx-be/buildroot-tess.git buildroot
```

Rebase the branch on upstream `master` from time to time; it must stay
a clean single commit for the pull request.

## How to build

The flasher embeds the main image, so build the main image first:

```
make -C buildroot BR2_EXTERNAL=$PWD O=$PWD/output tess_defconfig
make -C output
make -C buildroot BR2_EXTERNAL=$PWD O=$PWD/output-flasher tess_flasher_defconfig
make -C output-flasher
```

Downloads go to `~/br-dl` (`BR2_DL_DIR` from `~/.profile`).

The main build also creates `output/images/tess-update.raucb`, a RAUC
update bundle with its root filesystem (see "Updates").

## Storage layout

SD NAND (mmcblk0, 480 MiB, or larger):

```
  8 KiB    U-Boot with SPL
  1 MiB    U-Boot environment, two redundant copies of 64 KiB
  4 MiB    mmcblk0p1  root filesystem slot A (96 MiB, ext4, read-only)
  100 MiB  mmcblk0p2  root filesystem slot B (96 MiB, ext4, read-only)
  196 MiB  mmcblk0p3  data (the rest, ext4, read-write, /data)
```

The image (`sdcard.img`) holds everything up to the data partition, which
it does not contain. On boot, `/etc/init.d/S00datafs` adds the data
partition when the partition table has none (up to the end of the SD
NAND, then it reboots once) and creates its filesystem when it has none.

U-Boot boots the slot that RAUC selected: `BOOT_ORDER`, `BOOT_A_LEFT` and
`BOOT_B_LEFT` in its environment (`fw_printenv` on the board). Each boot
attempt costs one, `/etc/init.d/S99rauc-mark-good` resets the counter
once the system is up, and a slot that fails three times in a row falls
back to the other one. The A/B boot logic is the U-Boot default
environment `board/tess/uboot/tess-main.env`
(`BR2_TARGET_UBOOT_DEFAULT_ENV_FILE` in `configs/tess_defconfig`).

The root filesystem is read-only. These directories are bind-mounted
from `/data/rootfs` (`/etc/default/datafs`), so they persist across reboots
and updates: `/etc/dropbear` (SSH host keys), `/etc/wpa_supplicant` (WiFi),
`/var/lib` and `/var/log`. Everything else is replaced by an update.

The upstream `phyxbe_tess_defconfig` image uses the same first 100 MiB
(U-Boot at 8 KiB, one root filesystem at 4 MiB) without environment,
slot B and data partition.

## Serial console

The Linux and U-Boot console is UART3 (ttyS3), 115200 8N1, 3.3V levels.
Connect a 3.3V USB-serial adapter to header P7:

```
  P7 pin 1  UART3.TX (PB6)  -> RX of the USB-serial adapter
  P7 pin 2  UART3.RX (PB7)  -> TX of the USB-serial adapter
  GND                       -> GND of the USB-serial adapter
                               (e.g. Feather header P2 pin 13)
```

Do not connect the VCC pin of the adapter, and do not use a 5V adapter.

```
picocom -b 115200 /dev/ttyUSB0
```

## USB console

The main image is a USB serial device (CDC ACM) on the USB-C connector,
with a login console on ttyGS0. On a Linux host:

```
picocom /dev/ttyACM0
```

The gadget type is set in `/etc/default/usbgadget`: "serial" in the main
image, "ethernet" (CDC ECM + RNDIS network) in the flasher image.
ModemManager probes the port once when it appears, which can show a
"Login incorrect" on the console.

## Installing over USB (FEL)

1. Connect the USB-C connector to the host.
2. Hold SW2 (pulls SDC0 CLK low, disabling the on-board storage) and
   press/release SW1 (RESET). The SoC now enters the USB bootloader (FEL).
   Check with:

   ```
   ./output-flasher/host/bin/sunxi-fel version
   ```

3. Load and start the flasher image:

   ```
   board/tess/flash.sh
   ```

   (the output directory of the flasher build is `output-flasher` by
   default, pass another one as the argument).

4. Log in on the console (UART3, see above) and run:

   ```
   tess-install
   ```

   It flashes the ESP32-C3 firmware over UART4, writes the main image
   to the SD NAND: U-Boot, its environment (back to the defaults) and
   both root filesystem slots. The data partition is not touched, the
   main image finds it again on its first boot (and reboots once). Then
   reset the board without SW2 to boot it.

If SW2 does not get the board into FEL, erase the U-Boot SPL from the
running main image; the boot ROM then falls back to FEL on the next
reset:

```
dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=16 count=2 conv=fsync
reboot
```

## WiFi

The WiFi configuration is `/etc/wpa_supplicant/wpa_supplicant.conf`, on
the data partition. On the first boot it is a copy of the one in the
image (`board/tess/rootfs_overlay/common/etc/wpa_supplicant/`, ignored by git:
it holds your credentials), if that exists. To change it on the board:

```
{ echo "ctrl_interface=/var/run/wpa_supplicant"
  wpa_passphrase "<ssid>" "<password>" | grep -v '#psk'
} > /etc/wpa_supplicant/wpa_supplicant.conf
```

and reboot. The country is set in `/etc/default/regdomain` (in the image).

## Updates

Copy the bundle to the data partition and install it with RAUC; it
writes the other root filesystem slot and makes U-Boot boot it next:

```
scp output/images/tess-update.raucb root@<board>:/data/
rauc install /data/tess-update.raucb
reboot
```

`rauc status` shows the slots and which one is booted. Bundles are
signed with the development key in `board/tess/rauc/` unless
`TESS_RAUC_KEY` and `TESS_RAUC_CERT` are set; see `board/tess/rauc/README`.

## Display

The Raspberry Pi 7" DSI display (with touchscreen) is not in the board
device tree but in the `rpi-7inch-dsi-overlay.dtb` overlay
(`board/tess/rpi-7inch-dsi-overlay.dts`). The main image loads
it with `fdtoverlays` in `/boot/extlinux/extlinux.conf`: remove that line
from `board/tess/rootfs_overlay/common` when no display is connected. The flasher
applies it in its boot script. The overlay source is a `.dts`, not a
`.dtso`, so that the kernel builds it with its single-`.dtb` rule (see the
comment in the file).

## ESP32-C3 firmware

The ESP32-C3 runs the esp-hosted-linux `network_adapter` firmware, built
by `board/tess/esp32c3/build.sh` (ESP-IDF in Docker) into
`board/tess/rootfs_overlay/flasher/lib/firmware/esp-hosted/`, where
`tess-install` takes it from. The host driver (Buildroot's `esp-hosted`
package) refuses a firmware of another version, so both must come from
the same esp-hosted-linux commit; `build.sh` reads that commit from the
package in `buildroot/`.

Status: the committed firmware binaries are NG-1.0.6.0.15, built from
esp-hosted-linux 2a8772c (the version the old Buildroot fork pinned).
Buildroot master now ships esp-hosted-linux 54d5367 (NG-1.0.6.0.23), so
the ESP32-C3 has to be reflashed with a firmware rebuilt from that
commit (`build.sh`, then the flasher) before WiFi works with the main
image. Firmware patch `esp32c3/patches/0002-*.patch` (immediate
disconnect event) no longer applies to 54d5367, where the disconnect
handling was reworked: check whether it is still needed and drop or
rebase it.

See `board/tess/PLAN.md` for the hardware notes and the design history.
