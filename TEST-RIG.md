# Tess test rig

Plan for a rig that tests a Tess board automatically: flashing, the
system image under test and all the hardware reachable from the Feather
headers, the USB-C port and the console. Written 2026-11-18 after the
first manual board tests (see `buildroot-external/board/tess/PLAN.md`).

## Overview

```
                 USB hub with per-port power switching (uhubctl)
   Test PC ──┬── USB-C ──── Tess         power, FEL, DFU, USB functions
             ├── USB ────── FTDI 3.3V ── Tess P7 (UART3 console)
             ├── USB ────── rig controller (RP2040)
             ├── (optional) FTDI 3.3V ── ESP32-C3 UART_PROG (UART4) test points
             └── WiFi: dedicated test access point; BLE: PC adapter or dongle

   Tess Feather headers P2/P3 ── test wing ── rig controller GPIO/ADC/PIO
```

- **Test wing**: a Feather-shaped board with header sockets; Tess plugs in
  on top. It carries the loopbacks, pull-ups, the I2C EEPROM, the series
  resistors and the rig controller, and brings P7, the battery connector
  and the button signals to the board by wires or pogo pins. Swapping the
  board under test is then a matter of seconds.
- **Rig controller**: an RP2040 (Raspberry Pi Pico or Feather RP2040),
  3.3V logic like the T113. PIO measures PWM frequency and duty cycle and
  can decode a NeoPixel bit stream; it has three ADC inputs and can be an
  I2C target. The PC talks to it over USB serial (a small command
  protocol, or CircuitPython with `usb_cdc`).
- **Golden board**: keep one known good Tess to validate the rig itself
  before blaming a board under test.

## Feather headers

Positions follow the Adafruit Feather layout (schematic sheet 2):

- P2: 16 RSTn, 15 3V3, 14 AREF, 13 GND, 12 A0, 11 to 7 A1 to A5
  (GPIO0 to GPIO4), 6 SCK, 5 MO, 4 MI, 3 RX, 2 TX, 1 SPARE (GPIO5)
- P3: 12 VBAT, 11 EN, 10 VUSB, 9 to 3 D13 to D5 (GPIO12 to GPIO6), 2 SCL,
  1 SDA

The silkscreen names of the GPIOs: E12, E13, C7, G11, G9, G7, B3, B2,
G3, D10, D18, D19 and F6.

**Every line between Tess and the rig gets a 1 kΩ series resistor**, so
that a test mistake (two outputs driving against each other) damages
neither side. One common ground for Tess, the rig controller, the FTDI
cables and the battery simulator.

| Tess signal | Connection on the wing | Tests |
|---|---|---|
| TX (PB4, UART5) and RX (PB5) | TX to RX through 1 kΩ, both also to rig inputs | `busio.UART` loopback at 9600, 115200, 500000, 1500000 baud (only 1500000 / n is exact on the T113) |
| MOSI (PD12) and MISO (PD13) | MOSI to MISO through 1 kΩ | `board.SPI()` loopback, several baud rates |
| SCK (PD11), D10 (PD10, chip select) | rig inputs | SCK frequency, chip select timing |
| MOSI | rig PIO input | NeoPixel stream of `neopixel_spi` decoded by the rig (no LED needed) |
| SDA (PE7), SCL (PE6) | 4.7 kΩ pull-ups to 3V3, a 24C02 EEPROM (0x50), the rig as I2C target | scan, EEPROM write/read/verify, clock stretching via the rig |
| E12, E13, C7, G11, G9, G7, B3, B2, G3 | each to its own rig GPIO through 1 kΩ | output high/low read by the rig; input driven by the rig; pull-up and pull-down |
| F6 (PWM5), D18 (PWM2), D19 (PWM3) | rig PIO inputs | `pwmio.PWMOut` frequency and duty cycle per channel |
| D18 | also RC filter (10 kΩ, 1 µF) to a rig ADC | analog check of the duty cycle |
| A0 (GPADC0) | rig PWM, RC filter and divider, 1 kΩ in series; the same node to a rig ADC as reference | ADC accuracy at several voltages. **A0 is 0 to 1.8V only**: divide so that 3.3V at the rig gives about 1.5V |
| RSTn (P2.16) | rig open drain output (N-MOSFET) | reset |
| EN (P3.11) | rig open drain output | regulator off/on: power cycle without touching USB |
| VBAT (P3.12) | battery simulator, see below | charger |
| VUSB (P3.10) | divider to a rig ADC | USB supply present |

Notes:

- Wire each GPIO to the rig, not GPIOs in pairs to each other: a pair
  cannot tell which of its two pins is broken and hides a short between
  them. The rig also drives neighbouring header pins to opposite levels to
  find solder bridges.
- The first manual test (2026-11-18) found the I2C3 bus without working
  pull-ups: with the internal pull-downs enabled SCL and SDA read low, so
  R4/R5 (4.7 kΩ on the schematic) are not fitted or not supplied on that
  board, and the controller reports bus errors. The wing's pull-ups hide
  that; add a test with the wing pull-ups switched off (a jumper or an
  analog switch) to check the board's own.

## Power, reset and FEL

- **Power**: the USB-C port on a hub port with power switching
  (`uhubctl`), or a load switch in VBUS driven by the rig. Power cycles,
  and the power-on and boot time tests.
- **Reset**: RSTn on the header (above), or the SW1 pads.
- **FEL**: on rev 00 SW2 does not work (it pulls SDC0 CLK low through
  240 Ω, too weak, see IDEAS.md). Pull SDC0.D0 low instead: a pogo pin on
  TP4 (bottom side, next to the SD NAND) to a rig open drain output, which
  must only ever pull low, never drive high. FEL is then: pull TP4 low,
  pulse RSTn, release TP4 after a second. Never touch TP3: it is +3V3.
- **FEL from software**: a running board with `tess-fel` reboots into FEL
  by itself (`TESS_HOST`, see `buildroot-external/README.md`), a third
  way, for boards in the field; the rig tests it too.

## Battery and charger

- **Battery simulator**: a bench supply (or a programmable one) at 3.7V
  through about 1 Ω and a diode against reverse current, switched to VBAT
  by a relay or a MOSFET; or a small LiPo with a protection circuit.
- **Measure** the battery current with a shunt and an INA219 on the rig's
  own I2C bus, and VBAT with a rig ADC.
- **Cases**: no battery (the CHG.STAT output blinks: on 2026-11-18 the
  driver reported Charging and Not charging every second or two), charging
  (Charging), charge done (raise the supply to 4.2V: Not charging), running
  from the battery with USB off. Compare with
  `/sys/class/power_supply/charger/status`.

## Console, wireless, display, LEDs

- **Console**: UART3 on P7 (pin 1 TX, pin 2 RX, 3.3V) to an FTDI cable
  that stays connected: every test keeps the U-Boot, kernel and init log.
- **ESP32-C3 console** (optional): UART4 (UART_PROG) on its test points to
  a second FTDI, for the ESP's own boot log during firmware tests.
- **WiFi**: a dedicated access point with a fixed SSID (configured on
  the board by the test). Tests: connect, DHCP, mDNS, SSH, `iperf3`
  throughput, reconnect after `wpa_cli disconnect`.
- **BLE**: the PC's adapter (or a USB dongle) scans for the board
  advertising (`bluetoothctl advertise on` on the board) and connects;
  later the 2M PHY throughput test (BLE item in PLAN.md).
- **Display**: check that the panel, the display MCU and the touchscreen
  probe (`/dev/fb0`, `/sys/class/backlight`, Goodix at 0x5d on I2C2), draw
  into `/dev/fb0` and read it back. A photodiode taped over a
  corner of the panel, read by a rig ADC, while the test turns that
  corner black and white, proves the picture reaches the glass.
- **Touch**: the Goodix input device must exist; a real touch needs a
  person, or a capacitive probe switched by the rig.
- **User LEDs**: not on the headers. Photodiodes over LED0 to LED2, in
  foam so that they do not see each other, read by rig ADCs.

## Test sequence

pytest on the PC; the board over SSH (the PC's key in
`/root/.ssh/authorized_keys`) or the console; the rig over its USB serial
port.

1. **Power on**: board current from VBUS, boot log on P7, time to the
   login prompt.
2. **Flashing**: FEL with SW2 and RSTn, `make flash-sd` (USB DFU),
   `make flash` and `tess-install` (ESP32-C3); FEL from software.
3. **Image**: the system image under test boots, and its own tests
   (e.g. updates, host name, mDNS, SSH, NTP) pass.
4. **USB device**: the USB functions of the image appear on the PC.
5. **Feather I/O**: GPIO, UART, SPI, I2C, PWM, A0, NeoPixel stream, with
   the pins and the rig as above.
6. **Wireless**: WiFi and BLE.
7. **Charger**: the four battery cases.
8. **Display**: probe, draw, read back, photodiode.

Each step writes its log and a pass/fail line; a board passes when all
steps pass.

## Mapping to the open TODOs

- PLAN.md, BLE throughput: step 6.
