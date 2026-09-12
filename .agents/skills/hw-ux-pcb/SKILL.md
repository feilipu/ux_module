---
name: hw-ux-pcb
description: >
  RC2014 UX Module board pin map and bus glue: Propeller P0–P31 assignments
  for ACIA address/data, /WAIT, /INT, VGA, PS/2, FTDI, I2C EEPROM, and the
  74HC4078 decode. Use when changing pin constants, ACIA masks, or relating
  firmware to pcb/ schematics. Sources: src/acia_rc2014.spin, README, pcb/.
---

# Hardware — UX Module PCB

Board: RC2014 User Experience Module (Propeller P8X32A). Schematics and gerbers: `pcb/`. Product overview: `README.md`.

## Clock and power

| Item | Value |
|------|-------|
| Oscillator | 7.3728 MHz (RC2014 bus clock family) |
| Propeller clock | ×16 PLL ≈ 118 MHz |
| Logic | 3.3 V Propeller; RC2014 bus via board level shifting / open-collector where noted |
| Firmware store | I2C EEPROM 24LC256 or 24LC512 |

## Pin map (production firmware)

| Pins | Function |
|------|----------|
| P0 | A7 |
| P1 | A6 |
| P2 (pin 2 — not “Propeller 2”) | `!(/IORQ \| A5 \| A4 \| A3 \| A2 \| A1)` from 74HC4078 NOR (active high when I/O hit in the decoded page) |
| P3 | A0 |
| P4 | /M1 |
| P5 | `PRESET`: drive RC2014 `!RESET` via D1. C12 200 pF to `!RESET`. Not Propeller `/RES`. |
| P6 | /WR |
| P7 | /RD |
| P8–P15 | D0–D7 data bus |
| P16–P23 | VGA (VGroup 2): VSync, HSync, B1 B0, G1 G0, R1 R0 |
| P24 | /WAIT (open-collector via diode) |
| P25 | /INT (open-collector via diode) |
| P26 | PS/2 clock |
| P27 | PS/2 data |
| P28 | I2C **SDA** for Spin DDC (`ddc_i2c.spin`). Bootloader SCL. VGA pin 12 (VESA SDA). |
| P29 | I2C **SCL** for Spin DDC. Bootloader SDA. VGA pin 15 (VESA SCL). |
| P30 | FTDI TX (Propeller → host). SparkFun FTDI Basic pin 5 RXI (YELLOW) |
| P31 | FTDI RX (host → Propeller). SparkFun FTDI Basic pin 4 TXO (ORANGE) |

Constants: `src/ux_module.spin`, `src/acia_rc2014.spin`, `src/ddc_i2c.spin`.

## ACIA I/O decode

The 74HC4078 compresses `/IORQ` and A5…A1 into one Propeller pin. Firmware treats a match on that pin plus A7/A6/A0 (and /M1 high for I/O) as chip select for the emulated MC6850.

Selectable bases in `acia_rc2014.spin`:

| Name | Typical use |
|------|-------------|
| `PORT_80` | Default RC2014 ACIA |
| `PORT_40` | RomWBW when SIO owns 0x80 |
| `PORT_C0` | Reserved / VJET experiments (`PORT_VJET` in top object) |

Register map (6850-compatible):

| Offset | /RD | /WR |
|--------|-----|-----|
| base+0 | Status | Control |
| base+1 | Receive data | Transmit data |

Status/control bit names mirror `docs/MC6850.pdf` (`SR_RDRF`, `SR_TDRE`, `CR_RIE`, …).

## Bus timing notes

- Propeller asserts `/WAIT` on address match so the Z80 stretches the I/O cycle until PASM finishes. Match uses `waitpeq … wr` (dest+mask). Rules: `lang-pasm/references/acia-wait.md`.
- `/INT` is open-collector on P25 (`OUTA` bit 25 stays 0). PASM `sync_irq` holds `DIRA` P25 on a status read. Spin also pulses `DIRA[25]` when RIE or TIE, so a key is seen while PASM is in `waitpeq`. Each cog has its own `DIRA`. The pin is the OR of driven lows.
- CTRL+ALT+DEL: `outa[5]~`, `dira[5]~~`, hold 1 ms, `masterReset`, local clear, then `dira[5]~`. Net `PRESET` is P5, D1 cathode, and C12 (200 pF). `!RESET` is the RC2014 bus (D1 anode, C12 other end). C12 does not stretch the pulse. P5 is not pulled. Do not poll it as a reset input. The board button uses ROM `$03`.
- Data bus bytes in Hub are often stored **pre-shifted** by `DATA_BASE` (8) so they OR straight onto `OUTA`.

## VGA analogue network

Eight pins through resistor DAC (270 Ω / 560 Ω / 130 Ω) as documented in `hires_text_vga.spin` / `VJET_vUXM_vga.spin` headers. Do not reassign VGA away from an 8-pin group boundary (0/8/16/24).

## Agent rules

1. Change pin numbers in **one** owning module, then import via `object#CONST`.
2. Any ACIA mask change must update `port_active_mask`, `DATA_BASE`, and schematic comments together.
3. Do not put extra I2C devices on P28/P29 that answer during Propeller boot. VGA DDC SDA/SCL are swapped so a monitor EDID chip does not ACK the bootloader. After boot, `i2c.startCog` in `ddc_i2c.spin` uses the swapped pair to read EDID at 0x50 and DDC/CI at 0x37. Do not talk to the 24LC256 with that pin pair.
4. DTR on the FTDI connector resets the Propeller (same idea as Arduino). Tools: `tools/serial_dtr.py`, `tools/serial_tool.py`. Load the chip with an **FT232** Prop Plug (`tool-propeller`). USB CDC is not a loader.
5. SparkFun FTDI Basic 6-pin matches the FTDI TTL-232R SIL except **pin 6 is DTR#**, not RTS# ([hookup guide](https://learn.sparkfun.com/tutorials/sparkfun-usb-to-serial-uart-boards-hookup-guide)). Align GRN to GRN, BLK to BLK. CTS is NC. RTS is not on this header. Load with `proploader` DTR (`tools/ux-load.sh`). No RTS/CTS or DTR flow to the Propeller. Software flow: `module-ux` revert notes.

| Pin | SparkFun / Arduino | FTDI TTL-232R cable | Colour | UX Module |
|-----|--------------------|---------------------|--------|-----------|
| 1 | GND | GND | BLACK | GND (BLK) |
| 2 | CTS# | CTS# | BROWN | NC |
| 3 | VCC | VCC | RED | VCC |
| 4 | TXO | TXD | ORANGE | P31 RX |
| 5 | RXI | RXD | YELLOW | P30 TX |
| 6 | **DTR#** | RTS# | GREEN | `!DTR` → `/RES` (GRN) |
6. 8086 Consultancy USB-C CDC adaptor (5 V, [Tindie](https://www.tindie.com/products/8086net/uusbusb-c-cdc-serial-adaptor-5v/)) is RTS, RX, TX, 5V, CTS, GND. Pin 1 is RTS, not DTR. macOS node `/dev/cu.usbmodem*`. Fine for 115200 console (`ux-screen`). Do not use it as a Prop Plug. An FT232 enumerates as `/dev/cu.usbserial-*`.

## Related

- Chip behaviour: `hw-propeller`
- Firmware topology: `module-ux`
- 6850 register behaviour in PASM: `module-ux` + `src/acia_rc2014.spin`
- `/WAIT` loop: `lang-pasm/references/acia-wait.md`
