# Tess flasher and USB flashing tools

Buildroot `BR2_EXTERNAL` tree for the Phyx Tess board (Allwinner T113-S3,
ESP32-C3 WiFi/BLE co-processor, Adafruit Feather form factor). It holds:

- `configs/tess_flasher_defconfig`: the flasher image, booted over USB
  (FEL), that flashes the ESP32-C3. Its U-Boot, started alone over FEL,
  offers USB DFU to write the SD NAND from the host.
- `esp32c3/`: the ESP32-C3 firmware build (esp-hosted, ESP-IDF in Docker).
- `flash-sd.sh` and `flash.sh`: write an image to the SD NAND, and boot the
  flasher, over USB.
- `board/tess/`: the files of the flasher image (overlay, scripts, kernel
  and U-Boot configuration, espflash patch).

The main image, with A/B root filesystems, RAUC updates, WiFi, BLE, the
DSI display and CircuitPython, is built in its own repository, tess-os
(https://github.com/bertouttier/tess-os, private).

Basic board support lives in Buildroot itself, on the branch
`phyxbe-tess` of https://github.com/phyx-be/buildroot-tess (upstream
`master` plus the commit adding `board/phyxbe/tess/` and the minimal
`phyxbe_tess_defconfig`, to be submitted as a pull request). This tree
reuses its `board/phyxbe/tess/sun8i-t113s-tess.dts` (the device tree,
shared by Linux and U-Boot), `board/phyxbe/tess/uboot.fragment` and the
Linux and U-Boot hash files.

## Layout

```
buildroot/          Buildroot, branch phyxbe-tess (git submodule)
configs/            tess_flasher_defconfig
board/tess/         board files, see above
esp32c3/            ESP32-C3 firmware build
Makefile            make / esp32c3 / flash / flash-sd, see "How to build"
flash-sd.sh         writes an image to the SD NAND over USB (FEL + DFU)
flash.sh            boots the flasher image over USB (FEL)
output/flasher/     flasher image build (not in this repository)
output/esp32c3/     ESP32-C3 firmware build (not in this repository)
```

## Buildroot checkout

`buildroot/` is a git submodule: the `phyxbe-tess` branch of
https://github.com/phyx-be/buildroot-tess, pinned to a commit. Get it
when cloning, or afterwards:

```
git clone --recurse-submodules git@github.com:phyx-be/TESS.git
# or, in an existing clone:
git submodule update --init
```

To save time and disk space with a local Buildroot clone, pass it as a
reference: `git submodule update --init --reference ~/development/buildroot.git`.

Keep the submodule at the same Buildroot commit as the one in tess-os, or
at least at the same `esp-hosted` package version: the ESP32-C3 firmware
built here must match the esp-hosted driver of the main image. After
`phyxbe-tess` moves, update it in both repositories:

```
git submodule update --remote buildroot
git commit -m "buildroot: update to <commit>" buildroot
```

## How to build

```
make esp32c3   # the ESP32-C3 firmware in output/esp32c3/ (needs Docker)
make           # the flasher image in output/flasher/, which embeds the
               # firmware
```

Any other target goes to Buildroot for the flasher build (`O`, default
`output/flasher`), e.g. `make menuconfig` or `make linux-rebuild`;
`make help-buildroot` shows Buildroot's own help. `BUILDROOT`,
`FLASHER_O` and `ESP32C3_O` override the Buildroot tree and the output
directories. Downloads go to `~/br-dl` (`BR2_DL_DIR` from `~/.profile`).

## Consoles

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

The flasher is also a USB serial device (CDC ACM) on the USB-C
connector, with a login console on ttyGS0:

```
picocom /dev/ttyACM0
```

ModemManager probes the port once when it appears, which can show a
"Login incorrect" on the console.

## Installing over USB (FEL)

Both steps start from the USB bootloader (FEL) of the T113:

1. Connect the USB-C connector to the host.
2. Hold SW2 (pulls SDC0 CLK low, disabling the on-board storage) and
   press/release SW1 (RESET). The SoC now enters FEL. Check with:

   ```
   ./output/flasher/host/bin/sunxi-fel version
   ```

### SD NAND: an image, over USB DFU

```
make flash-sd IMAGE=<path to tess-os>/output/images/sdcard.img
```

`flash-sd.sh` starts the flasher's U-Boot alone over FEL. Without a boot
script to run, U-Boot enters USB DFU (`board/tess/uboot/tess-flasher.env`),
and dfu-util sends the image to the `sdcard` entity, the whole SD NAND.
When dfu-util detaches, U-Boot resets the board, which boots the new
image (release SW2 first). The tess-os README describes what its image
writes and keeps.

### ESP32-C3: the flasher image

```
make flash
```

It loads and starts the flasher image over FEL (`flash.sh`: U-Boot with
the kernel, device tree, boot script and root filesystem; with a boot
script, U-Boot boots Linux instead of starting DFU). Log in on the USB
console (`picocom /dev/ttyACM0`, or UART3, see above) and run:

```
tess-install
```

It flashes the ESP32-C3 firmware over UART4 (`esp32c3-flash`).

If SW2 does not get the board into FEL, erase the U-Boot SPL from the
running main image; the boot ROM then falls back to FEL on the next
reset:

```
dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=16 count=2 conv=fsync
reboot
```

## ESP32-C3 firmware

The ESP32-C3 runs the esp-hosted-linux `network_adapter` firmware, built
by `make esp32c3` (`esp32c3/build.sh`, ESP-IDF in Docker) into
`output/esp32c3/`, not tracked in git; the flasher build copies it to
`/lib/firmware/esp-hosted/` in the flasher image
(`board/tess/post-build.sh`), where `tess-install` takes it from. The
host driver (Buildroot's `esp-hosted` package, in the main image) refuses
a firmware of another version, so both must come from the same
esp-hosted-linux commit; `build.sh` asks Buildroot in `buildroot/` for
that commit.

Status: the firmware on the boards is NG-1.0.6.0.15, built from
esp-hosted-linux 2a8772c (the version the old Buildroot fork pinned).
Buildroot master now ships esp-hosted-linux 54d5367 (NG-1.0.6.0.23), so
the ESP32-C3 has to be reflashed with a firmware rebuilt from that
commit (`make esp32c3`, `make`, then `make flash` and `tess-install`)
before WiFi works with the main image. The former firmware patch 0002
(report a host disconnect right away) is dropped: 54d5367 tags the
disconnect event with the generation of the disconnect command instead,
so the host no longer drops the late event. To confirm on the board:
`wpa_cli disconnect` followed by a reconnect must not loop on
authentication timeouts.

See `board/tess/PLAN.md` for the hardware notes and the design history.
