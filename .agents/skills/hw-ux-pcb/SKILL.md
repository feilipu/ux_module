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
| P5 | /RESET (sense) |
| P6 | /WR |
| P7 | /RD |
| P8–P15 | D0–D7 data bus |
| P16–P23 | VGA (VGroup 2): VSync, HSync, B1 B0, G1 G0, R1 R0 |
| P24 | /WAIT (open-collector via diode) |
| P25 | /INT (open-collector via diode) |
| P26 | PS/2 clock |
| P27 | PS/2 data |
| P28 | I2C **SDA** (swapped vs Propeller default labels in `i2c.spin`) |
| P29 | I2C **SCL** |
| P30 | FTDI / Prop Plug TX (Propeller → host). SparkFun FTDI Basic pin 2 RXI |
| P31 | FTDI / Prop Plug RX (host → Propeller). SparkFun FTDI Basic pin 3 TXO |

Constants: `src/ux_module.spin`, `src/acia_rc2014.spin`, `src/i2c.spin`.

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
- `/INT` is a held open-collector level from the ACIA cog (`DIRA` P25, `OUTA` bit 25 stays 0). It is not a pulse. Spin must not drive P25.
- Spin may pulse P5 (`RESET_PIN_NUM`) low for CTRL+ALT+DEL. Return that pin to input after the pulse.
- Data bus bytes in Hub are often stored **pre-shifted** by `DATA_BASE` (8) so they OR straight onto `OUTA`.

## VGA analogue network

Eight pins through resistor DAC (270 Ω / 560 Ω / 130 Ω) as documented in `hires_text_vga.spin` / `VJET_vUXM_vga.spin` headers. Do not reassign VGA away from an 8-pin group boundary (0/8/16/24).

## Agent rules

1. Change pin numbers in **one** owning module, then import via `object#CONST`.
2. Any ACIA mask change must update `port_active_mask`, `DATA_BASE`, and schematic comments together.
3. Do not put extra I2C devices on P28/P29 that answer during Propeller boot.
4. DTR on the FTDI connector resets the Propeller (same idea as Arduino). Tools: `serial_dtr.py`, `serial_tool.py`.
5. SparkFun FTDI Basic 6-pin is DTR, RXI, TXO, VCC, CTS, GND. DTR is net `!DTR` to Propeller `/RES` only. CTS is not connected. RTS is not on this header. The Propeller cannot pause the host with RTS/CTS or DTR. Software flow choice (no XON/XOFF): `module-ux` revert notes.

## Related

- Chip behaviour: `hw-propeller`
- Firmware topology: `module-ux`
- 6850 register behaviour in PASM: `module-ux` + `src/acia_rc2014.spin`
- `/WAIT` loop: `lang-pasm/references/acia-wait.md`
