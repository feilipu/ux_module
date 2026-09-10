# Architecture — UX Module firmware

This note describes the production firmware under `src/` (not `src/lib_vjet`).  
MCU: **Parallax Propeller 1 (P8X32A) only** — not Propeller 2.  
Agent edit rules: `.agents/skills/module-ux`, `hw-ux-pcb`, `lang-spin`, `lang-pasm`, `tool-propeller`.  
Prose style: `.agents/skills/style-ste-writing`.

## Purpose

The UX Module is an RC2014 board that presents:

- VGA text console
- PS/2 keyboard
- FTDI serial (programming + parallel console)
- An MC6850-compatible ACIA on the Z80 I/O bus

Host software can use stock RC2014 ROMs that expect a 68B50 ACIA. The Propeller P8X32A runs the firmware. Primary product documentation is `README.md`. Board files are under `pcb/`. Chip and language manuals are under `docs/`.

## Clock

The board uses a 7.3728 MHz oscillator. Firmware sets `XTAL1 + PLL16X`, so the system clock is about 118 MHz. VGA pixel-rate constants in `hires_text_vga.spin` assume that clock. A different oscillator needs a new `_xinfreq` and new video timing.

## Object hierarchy

```
ux_module.spin
├── terminal_ftdi.spin      Full-duplex UART on P31/P30 (Prop Plug pins)
├── keyboard_ps2.spin       PS/2 decode on P27 data / P26 clock
├── acia_rc2014.spin        6850 register and bus timing emulator
├── i2c.spin                Hub EEPROM helpers (P29 SCL / P28 SDA, swapped)
└── wmf_terminal_vga.spin   Screen buffer, colours, terminal print helpers
    └── hires_text_vga.spin Dual-cog VGA text engine (Parallax / Chip Gracey)
```

Compile and upload with `ux_module.spin` as the top object.

## Pin roles (summary)

| Function | Pins |
|----------|------|
| ACIA address and control | P0–P7 (A7, A6, NOR decode, A0, /M1, /RESET, /WR, /RD) |
| ACIA data | P8–P15 |
| VGA | P16–P23 |
| /WAIT, /INT | P24, P25 (open-collector via diodes) |
| PS/2 | P26 clock, P27 data |
| I2C EEPROM | P28 SDA, P29 SCL |
| FTDI | P30 TX, P31 RX |

The 74HC4078 NOR combines `/IORQ` with A5–A1 so one Propeller pin can detect the ACIA I/O page. Detail: skill `hw-ux-pcb` and comments in `acia_rc2014.spin`.

## Cog map

Typical production start order in `ux_module.main`:

1. FTDI terminal cog (`terminal_ftdi.start`)
2. ACIA cog (`acia.start`)
3. Two VGA text cogs (`wmf.init` → `hires_text_vga.start`)
4. PS/2 cog (`kbd.start`)
5. Cog 0 remains in the main Spin loop (`kbdToZ80`, `termToZ80`, `readZ80`)

That uses six of eight cogs. I2C runs in Spin on an existing cog. Only the main cog calls `acia.tx`. Main skips `kbdToZ80` during Z80→host XMODEM (`inXmodem`) and host→Z80 XMODEM (`hostXmodem` from FTDI `SOH`/`STX`).

## Data paths

```
Keyboard  →  kbdToZ80  ─┐
                        ├─ acia.tx → ACIA transmit FIFO → Z80 IN data
FTDI RX   →  termToZ80 ─┘
Z80 OUT data  →  ACIA receive FIFO  →  readZ80  →  VGA + FTDI TX
```

`readZ80` is a non-blocking parser. It pumps bytes already in the FIFO. LF still drains when FTDI TX is full. Other bytes wait for FTDI room. If the next byte will not fit, `readZ80` holds ACIA `TDRE`. There is no XON/XOFF on FTDI. The FTDI RX cog drops inbound bytes when its FIFO is full. The 6-pin header does not wire CTS or RTS to the Propeller, so the host cannot be paused in hardware.

Naming trap: from the Z80, “receive data register” is filled by the Propeller **transmit** FIFO (`tx_*`). “Transmit data register” writes enter the Propeller **receive** FIFO (`rx_*`).

## ACIA emulation

`acia_rc2014.spin` runs a PASM cog that:

1. Waits for the decoded address match (including `/M1` high for I/O)
2. Pulls `/WAIT` so the Z80 stretches the cycle
3. Services status/control at base+0 or data at base+1
4. Releases `/WAIT` and returns to wait

A real MC68B50 places data in 150 ns or less. This cog is slower, so P24 stretches the Z80 I/O cycle. Address detect uses `WAITPNE` then `waitpeq outa, port_active_mask wr`. The `wr` effect adds the mask into `OUTA`. Bit 24 was already 1, so the add drives `/WAIT` low in that instruction.

Carry hits bit 25 (`/INT`). The next instruction clears that bit. Do not drop `wr`. Loop rules live in `.agents/skills/lang-pasm/references/acia-wait.md`.

Status and control bits follow the Motorola 6850 model (`docs/MC6850.pdf`). Default base is `0x80`. RomWBW setups may use `0x40` when an SIO owns `0x80`.

FIFOs are 512 bytes each. Z80 receive is the Propeller `tx_*` FIFO (`RDRF`). Z80 transmit is the Propeller `rx_*` FIFO (`TDRE`). Spin `tx` and `rx` move bytes. The PASM cog writes `acia_status`.

The PASM cog owns `/INT` as a level, held low while RIE or TIE match the flags. `/RTS` is the CR5/CR6 field. Master reset `$03` sets `req_parse_idle` then zeros both FIFOs. It does not clear `tdre_hold`. CTRL+ALT+DEL holds P5 for 1 ms, runs `do_master_reset` (including `tdre_hold` and config `$03`), then `tdreHold` until FTDI has room. An empty or `/RTS`-high RDR read presents the last byte and does not move `tx_tail`. A full TDR write is dropped and does not set `OVRN`. Spin `tdreHold` writes Hub `tdre_hold` so PASM keeps `TDRE` clear. `sync_irq` is the only writer of `acia_status`. Detail and revert notes: `.agents/skills/module-ux`.

## FTDI UART cog

`terminal_ftdi.spin` keeps receive and transmit in **one** PASM cog with `JMPRET` coroutines (Parallax AN014 pattern on OBEX). Bit timing uses `CNT` deadlines. That saves a cog versus two separate UART cogs.

## VGA text path

`wmf_terminal_vga` owns the character buffer, per-row colours, and cursor bytes. `hires_text_vga` reads those Hub structures and generates VGA with two cogs. Resolution and character grid depend on which timing `CON` block is active in `hires_text_vga.spin` (for example 640×480 with 80×40 characters).

Cursors are six bytes: text X/Y/mode and mouse X/Y/mode. The UX Module uses the text cursor and leaves the mouse cursor disabled.

## Relation to VECTORJET

`src/lib_vjet` is linked from `ux_module.spin` but does not start at boot. `enterGraphics` stops text VGA and starts VECTORJET (empty list, black). `enterText` reverses that. Cog 0 keeps the ACIA pump. Put `draw` on another Spin cog. See `ARCHITECTURE_LIB_VJET.md`.

## External references

| Doc | Use |
|-----|-----|
| `docs/P8X32A-Web-PropellerManual-v1.2.pdf` | Spin and PASM language |
| `docs/Propeller Quick Reference v1.7.pdf` | Opcode and Spin cheat sheet |
| `pcb/P8X32A-Propeller-Datasheet-v1.4.0_0.pdf` | Hub, video, counters, electrical |
| `docs/MC6850.pdf` | ACIA register model |
| `pcb/RC2014_UX_MODULE.sch` | Board connectivity |
