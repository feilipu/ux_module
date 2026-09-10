---
name: module-ux
description: >
  UX Module firmware architecture: ux_module.spin object tree, cog budget,
  ACIA 6850 emulation path, VGA text terminal, PS/2 keyboard, FTDI bridge,
  and Z80 console flow. Use when changing src/ outside lib_vjet, or when
  integrating VECTORJET with the product firmware. See ARCHITECTURE_UX_MODULE.md.
---

# Module — UX firmware

Human architecture note: `ARCHITECTURE_UX_MODULE.md` (repo root). This skill is the agent checklist.

## Object tree

```
ux_module.spin                 ' top object — compile/upload this
├── terminal_ftdi.spin         ' FullDuplex serial on P31/P30
├── keyboard_ps2.spin          ' PS/2 on P27/P26
├── acia_rc2014.spin           ' MC6850 bus emulator (PASM cog)
├── i2c.spin                   ' EEPROM bus helpers (Spin bit-bang)
├── wmf_terminal_vga.spin      ' terminal services + screen buffer
│   └── hires_text_vga.spin    ' dual-cog VGA text (Chip Gracey)
├── VJET_vUXM_vga.spin         ' src/lib_vjet (search path)
└── VJET_vUXM_rendering.spin
```

Boot starts text VGA only. `enterGraphics` / `enterText` switch exclusive owners of P16–P23. Do not call `enterGraphics` from `main` until a draw cog exists. Serial and ACIA keep running in both modes.

Archive demos under `archive/` are not part of the production tree.

## Cog budget (production path)

| Cog role | Source |
|----------|--------|
| Spin main (Cog 0) | `ux_module` event loop: `kbdToZ80` / `termToZ80` / `readZ80` |
| FTDI UART | `terminal_ftdi` PASM |
| ACIA bus | `acia_rc2014` PASM |
| PS/2 | `keyboard_ps2` PASM |
| VGA text ×2 | `hires_text_vga` (two cogs) |

That is six cogs when all start successfully. Two cogs remain. Only the main Spin cog calls `acia.tx`. `enterGraphics` stops the text pair and starts 1 VECTORJET VGA cog plus 2 render cogs (seven total). One cog remains for a later Spin draw loop. See `library-vjet`.

## Main loop data paths

```
PS/2 keyboard ──kbdToZ80──┐
                          ├── acia.tx ──► ACIA tx FIFO ──► Z80
FTDI rx ──termToZ80───────┘
Z80 writes data ──► ACIA rx FIFO ──readZ80──► VGA + FTDI
```

Cog 0 is the only `acia.tx` writer. Do not add a pump cog. Each of `kbdToZ80`, `termToZ80`, and `readZ80` moves at most `PUMP_LIMIT` bytes per pass.

`readZ80` is a non-blocking parser (`PARSE_IDLE` / `PARSE_ESC` / `PARSE_CSI` / `PARSE_CSI_M` / `PARSE_XMODEM_*`). Each call uses bytes that are already in the FIFO. Pump `ftdiNeed==0` bytes even when FTDI TX is full. Allow `TDRE` only when the next byte fits.

`inXmodem` is Z80 TDR `SOH`/`STX` through trailer (Z80→host). `hostXmodem` is FTDI `SOH`/`STX` until `EOT`/`CAN` (host→Z80). Skip `kbdToZ80` if either is true. Ctrl-A (`$01`) also sets `hostXmodem`. Panic or `$03` clears it.

Arrow, Home, Left, and Right need three FIFO slots (`acia.txSpace >= 3`) before `kbd.getKey`. Other keys need one slot (`acia.txCheck`).

If FTDI TX cannot take the next byte, `readZ80` calls `acia.tdreHold`. `term.rxCount` is a count only. There is no XON/XOFF. FTDI RX PASM drops inbound bytes when that FIFO is full. The header does not wire CTS or RTS.

CTRL+ALT+DEL: `outa[5]~`, drive P5 1 ms, `masterReset` (FIFOs, `last_rdr`, `tdre_hold`, config `$03`), `tdreHold`, `PARSE_IDLE`, VGA clear, FTDI clear only if `txSpace => 4`, then release P5. Z80 `CR_RESET` sets `req_parse_idle` **then** zeros FIFOs. Keep `tdre_hold`. Spin `tx`/`rx` abort while that flag is set.

ASCII and XMODEM `CON` names are lookup tables. Do not delete unused names.

Boot banner `"UX Module Initialised"` goes to FTDI and VGA.

## ACIA emulation (agent-critical)

- One PASM cog watches the decoded I/O address with `WAITPNE` / `WAITPEQ`.
- Match uses `waitpeq … wr` so `/WAIT` asserts via **destination += mask**. Do not drop `wr`. Loop contract: `lang-pasm/references/acia-wait.md`.
- Handler releases `/WAIT` with `or outa, bus_wait` after it places data or captures a write. `/RD` `/WR` rise uses `wait_pin_high` (polls `req_master`). Do not put Hub ops on the match path to `waitpeq … wr`.
- Hub block at `PAR` (11 longs): `rx_head`, `rx_tail`, `tx_head`, `tx_tail`, `acia_base`, `acia_config`, `acia_status`, `buffer_ptr`, `tdre_hold`, `req_master`, `req_parse_idle`, then rx/tx byte FIFOs.
- Perspective: Z80 “receive” is Propeller `tx_*` (host→Z80); Z80 “transmit” is Propeller `rx_*`.
- PASM `sync_irq` is the only writer of `acia_status`. `sync_irq` derives `RDRF` from the TX FIFO and `/RTS`, and `TDRE` from RX room and `tdre_hold`.
- Spin `tx` / `rx` move FIFO indexes only. They abort on `req_parse_idle` / `req_master`. `rxCount` / `rxCheck` / `txCheck` / `txSpace` / `rxPeek` are counts or peeks only.
- `tdreHold` / `tdreAllow` write Hub `tdre_hold` (0/1). They do not write `acia_status` or drive `/INT`.
- `/RTS` high (`CR_TID_RTS1`): hide `RDRF`, keep FIFO bytes. `/RTS` low: set `RDRF` if the TX FIFO holds data.
- Empty or `/RTS`-high RDR: present last byte, do not move `tx_tail`. Full TDR: drop the write, do not set `OVRN` (that bit is a receiver error).
- CR5/CR6 is a two-bit field. TIE is the exact value `CR_TIE_RTS0`, not bit 5 alone. Master reset `$03` zeros both FIFOs and sets `req_parse_idle`. It does not clear `tdre_hold`.
- `/INT` is a **level** from this cog only (`sync_irq`). Spin must not touch `DIRA[25]`.

Edit with `lang-pasm` + `hw-ux-pcb`. Datasheet: `docs/MC6850.pdf`. OBEX idioms: `lang-pasm/references/obex-pasm.md`.

## Flow and reset decisions (revert notes)

These replace earlier WIP (`ea4502e` XON/XOFF, `569cd07` flow). Change the named rule, then the listed files. Do not restore Spin writes to `acia_status` without a new single-writer design.

| Decision | Current rule | Why | Revert |
|----------|--------------|-----|--------|
| Status owner | PASM `sync_irq` is the only writer of `acia_status`. | Spin and PASM RMW lost `RDRF` / `tdreHold` (starve then burst). | Do not give Spin `acia_status` again unless PASM stops writing it. |
| `TDRE` hold | Hub `tdre_hold`. `tdreHold` / `tdreAllow` write that long only. | PASM `receive_data` and Spin `rx` used to set `TDRE` and undo the hold. | Restore only if PASM and `acia.rx` both honour a sticky hold. |
| `OVRN` | Receiver bit only. Full TDR write is dropped. Do not set `OVRN`. | Datasheet `OVRN` is unread RDR, not a TDR overwrite. ROMs that saw `OVRN` read RDR or issued `$03`. | Setting `OVRN` on TDR full is the old leak. Do not restore it. |
| Pump cap | `PUMP_LIMIT` (16) bytes per role per main-loop pass. | Unbounded `termToZ80` delayed `tdreHold`. | Raise or remove the cap if a path needs more than 16 bytes per pass at 115200. |
| FTDI emit | `readZ80` peeks, uses `ftdiNeed`, then `acia.rx`. BS/DEL need 3 TX slots. | `term.tx` blocks. One free slot plus backspace stalled Cog 0. | Blocking `term.tx` from the parser is the old stall. |
| Empty / `/RTS` RDR | Present `last_rdr`. Do not move `tx_tail`. | Datasheet keeps the last byte. `/RTS` high must not consume queued keys. | Presenting `0` and advancing the tail was the empty-FIFO junk path. |
| CTRL+ALT+DEL | Hold P5 1 ms, `masterReset` (FIFOs, `last_rdr`, `tdre_hold`, config `$03`), `tdreHold`, VGA `CS`, FTDI clear if 4 TX slots. Then release P5. | Panic must not block Cog 0 on `term.tx` while the Z80 runs. | Short pulse then blocking `term.clear`. |
| Z80 `CR_RESET` | Set `req_parse_idle` first. Zero FIFOs and `last_rdr`. **Keep `tdre_hold`.** | Parser is not a 6850 object. `$03` must not mean “FTDI has room.” Flag-first stops Spin tearing indexes. | Clearing `tdre_hold` on `$03`, or zeroing indexes before the flag. |
| `req_master` sample | Idle poll, `sync_irq`, and `wait_pin_high`. | `waitpeq /RD /WR` ignored `req_master` and deadlocked Cog 0. | Sample only in `sync_irq`. |
| XON/XOFF | Removed. No `term.rxFlow`. FTDI RX drops when full. | Binary XMODEM can contain `0x11`/`0x13`. Host cannot be paused on this header. | Restore `rxFlow` from `ea4502e` only for interactive paste. Wrap-over of FTDI RX. |
| Keyboard vs XMODEM | Skip `kbdToZ80` when `inXmodem` or `hostXmodem`. | Host→Z80 `SOH`/`STX` used to inject keys into RDR. | Gate on Z80 TDR `SOH` only. |
| Host CR | Z80 CR → `term.newLine` (CR+LF). `ftdiNeed` 2. | PST and typical hosts need CR. | `term.lineFeed` only. |
| Board reset button | Not sensed on P5 (floats, C12 200 pF). ROM `$03` is the ACIA path. | Polling P5 false-triggers. | Idle poll of P5. |

Hub writers: [references/remaining-errors.md](references/remaining-errors.md). Closed repair IDs P0-1…P3-5 live there. Residual: P0-3 button sense.

## VGA text path

- `wmf.init(VGA_BASE_PIN, @gTextCursX)` allocates screen/colour/cursor buffers and starts `hires_text_vga`.
- Default timing block in `hires_text_vga.spin` is selected by which CON section is uncommented; pixel rate `pr` is tuned for ~118 MHz.
- Screen bytes: bit7 = inverse; bits6..0 = glyph. Row colours are words `%%RRGGBB` style.
- `textOut` / CSI J K m skip WMF when `videoMode` is graphics. FTDI and ACIA still run.

## Build / upload

1. PropellerIDE (or compatible) with **`ux_module.spin` in the foreground**. Add `src/lib_vjet` to the library search path (`VJET_vUXM_vga`).
2. Program with an **FT232** Prop Plug (`proploader` on `/dev/cu.usbserial-*`, DTR reset). See `tool-propeller`. USB CDC (`/dev/cu.usbmodem*`, 8086net 5 V stick) is console only. Download on CDC was tried and failed (ROM handshake). Paused until an FT232 is available.
3. Toggle DTR on the FT232 to reboot stand-alone. CDC pin 1 is RTS, not DTR.

## Agent rules

1. Do not start lib_vjet VGA while `hires_text_vga` still owns P16–P23 and two cogs without an explicit mode switch that stops the text driver (`wmf.stop`). Stop VECTORJET render and VGA cogs before `wmf.init`. Do not build display lists on Cog 0 while the ACIA pump must run.
2. Keep ACIA base selection in one place (`PORT_DEFAULT` / `PORT_ROMWBW` in `ux_module.spin`).
3. Preserve non-blocking main loop behaviour; long work belongs in other cogs.
4. New shared Hub structures need a stated single writer. Only Cog 0 calls `acia.tx`. `req_master` is Spin→PASM. `req_parse_idle` is PASM→Spin.
5. Do not add XON/XOFF on the FTDI path.
6. Prose: `style-ste-writing`.

## Related

- Pins: `hw-ux-pcb`
- Spin/PASM: `lang-spin`, `lang-pasm`
- 3D library: `library-vjet`
