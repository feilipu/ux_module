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
├── ddc_i2c.spin            DDC EDID / DDC/CI Spin cog (P29 SCL / P28 SDA, swapped)
└── wmf_terminal_vga.spin   Screen buffer, colours, terminal print helpers
    └── hires_text_vga.spin Dual-cog VGA text engine (Parallax / Chip Gracey)
```

Compile and upload with `ux_module.spin` as the top object. Use `-L src` only. VECTORJET lives under `src/lib_vjet` with its own demo tops. The product top does not link it.

## Pin roles (summary)

| Function | Pins |
|----------|------|
| ACIA address and control | P0–P7 (A7, A6, NOR decode, A0, /M1, /RESET, /WR, /RD) |
| ACIA data | P8–P15 |
| VGA | P16–P23 |
| /WAIT, /INT | P24, P25 (open-collector via diodes) |
| PS/2 | P26 clock, P27 data |
| I2C EEPROM (bootloader) | P28 SDA, P29 SCL |
| VGA DDC (after boot) | P29 SCL, P28 SDA (`ddc_i2c.spin`). Swapped so EDID does not ACK the bootloader. |
| FTDI | P30 TX, P31 RX |

The 74HC4078 NOR combines `/IORQ` with A5–A1 so one Propeller pin can detect the ACIA I/O page. Detail: skill `hw-ux-pcb` and comments in `acia_rc2014.spin`.

## Cog map

Typical production start order in `ux_module.main`:

1. FTDI terminal cog (`terminal_ftdi.start`)
2. ACIA cog (`acia.start`)
3. Two VGA text cogs (`wmf.init` → `hires_text_vga.start`)
4. DDC I2C cog (`i2c.startCog` in `ddc_i2c.spin`) after VGA so the monitor is alive
5. PS/2 cog (`kbd.start`)
6. 1 ms Z80 `/RESET` pulse. Discard FTDI RX and restart the ACIA cog while held. A backplane `/RESET` button is sampled on P5 (1 ms debounce) and uses the same wipe. It does not reset the Propeller.
7. Cog 0 remains in the main Spin loop (`kbdToZ80`, `termToZ80`, `readZ80`)

Text mode uses seven of eight cogs. I2C is a Spin cog, not PASM. It reads EDID and DDC/CI. It does not change VGA timing. The spare cog is unused. Only the main cog calls `acia.tx`. Main skips `kbdToZ80` during a Z80→host XMODEM session (`z80XmSess`, including the ACK gap) and a host→Z80 packet session (`hostXm <> OFF`). Trailer bytes are counted, not sniffed. DDC still runs while the 8085 is live. Do not hold `/RESET` across DDC.

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

Status and control bits follow the Motorola 6850 model (`docs/MC6850.pdf`) at a practical level. FIFOs stand in for the UART. Clock divide, word select, and Break are not driven. PE, FE, CTS, and DCD stay 0. Default base is `0x80`. RomWBW setups may use `0x40` when an SIO owns `0x80`.

FIFOs are 512 bytes each. Z80 receive is the Propeller `tx_*` FIFO (`RDRF`). Z80 transmit is the Propeller `rx_*` FIFO (`TDRE`). Spin `tx` and `rx` move bytes. `sync_irq` writes `acia_status` on a status read.

PASM holds `/INT` low while RIE or TIE match the flags. Spin also pulses `DIRA[25]` when RIE or TIE, so a key is seen while PASM is in `waitpeq`. `/RTS` is the CR5/CR6 field. Master reset `$03` sets `req_parse_idle` then zeros both FIFOs. It does not clear `tdre_hold`. Boot pulse and CTRL+ALT+DEL hold P5 for 1 ms, discard host RX, and restart the ACIA cog so FIFOs and `last_rdr` are zero. Then `tdreHold` until FTDI has room. Do not wait on `req_master`. An empty or `/RTS`-high RDR read presents the last byte and does not move `tx_tail`. A full TDR write is dropped and does not set `OVRN`. Spin `tdreHold` writes Hub `tdre_hold` so PASM keeps `TDRE` clear. Detail and revert notes: `.agents/skills/module-ux`. RomWBW and CPM-IDE ACIA clients: `.agents/skills/module-ux/references/acia-host-drivers.md`.

## FTDI UART cog

`terminal_ftdi.spin` keeps receive and transmit in one PASM cog with `JMPRET` coroutines (Parallax AN014 pattern on OBEX). Bit timing uses `CNT` deadlines. That saves a cog versus two separate UART cogs.

The line is 115200 8N2. The system clock is 117964800 Hz, so one bit is 1024 clocks. Transmit shifts 11 bits. Those bits are one mark, one start, eight data, and one stop. The next byte adds one more mark before its start bit. Two mark bits sit before that start.

Receive samples eight data bits and one stop bit. The second stop bit is idle mark. The cog then waits for the next start bit.

Host tools set two stop bits (`CSTOPB`). They leave `CRTSCTS` clear. The 6-pin header does not wire CTS or RTS. `tools/ux-ftdi-relay.py` owns the FTDI node. A running relay keeps its old termios until the next start.

The initial ACIA control image is `CR_8N1`. Word select is not driven on the parallel bus. Keep that image. The FTDI frame is the 11-bit shift above.

## PS/2 on the FTDI cog

Text mode runs the keyboard on its own cog. One cog is free. Graphics mode uses all eight cogs, so the keyboard has no cog of its own.

`keyboard_ps2.spin` uses 332 cog longs. `terminal_ftdi.spin` uses 107. The cog limit is 496 longs. A straight sum leaves 57 longs.

The keyboard driver waits until the clock pin falls. A command to the keyboard holds that clock low for about 122 µs. One UART bit is 8.68 µs. That wait drops UART bits. The two objects need a new driver before they share a cog.

A polled driver can share the cog. It samples the PS/2 pins once each UART bit. A PS/2 half-clock is about 30 µs, so the poll sees the edge. That driver is not in the tree. Do not load a guess.

The bring-up keeps the input that requested graphics and stops the other input. Control-G keeps the FTDI cog. The PS/2 chord keeps the keyboard cog and stops the FTDI cog. The final build keeps both inputs on one cog. That driver is not in the tree.

## VGA text path

`wmf_terminal_vga` owns the character buffer, per-row colours, and cursor bytes. `hires_text_vga` reads those Hub structures and generates VGA with two cogs. Resolution and character grid depend on which timing `CON` block is active in `hires_text_vga.spin` (for example 640×480 with 80×40 characters).

The active block is 640×480 at about 70 Hz (VGA 60 Hz 800×525 totals, `pr=28`). EDID preferred timing is reported at boot. It does not retune this table. DDC/CI does not set resolution.

Cursors are six bytes: text X/Y/mode and mouse X/Y/mode. The UX Module uses the text cursor and leaves the mouse cursor disabled. Overlay X/Y copies the WMF column and row after text ops. Idle backspace at column 0 is eaten. The firmware does not guess a shell prompt width.

## Relation to VECTORJET

`src/lib_vjet` is not linked from the product top. Compile VECTORJET demos with their own top objects and `-L src -L src/lib_vjet`. Pins P16–P23 have one owner. See `ARCHITECTURE_LIB_VJET.md`.

The framebuffer bring-up keeps the list and the bitmap. The 80-line bitmap pair is 20480 bytes. The next bring-up writes an eight-line slice ahead of the scan. The accepted framebuffer demo stays.

## External references

| Doc | Use |
|-----|-----|
| `tools/README.md` | Copy compile, `ux-load.sh`, `ux-screen.sh`, and `rc-screen.sh` |
| `docs/P8X32A-Web-PropellerManual-v1.2.pdf` | Spin and PASM language |
| `docs/Propeller Quick Reference v1.7.pdf` | Opcode and Spin cheat sheet |
| `pcb/P8X32A-Propeller-Datasheet-v1.4.0_0.pdf` | Hub, video, counters, electrical |
| `docs/MC6850.pdf` | ACIA register model |
| `pcb/RC2014_UX_MODULE.sch` | Board connectivity |
