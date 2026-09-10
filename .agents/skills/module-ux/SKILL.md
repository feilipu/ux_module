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
└── wmf_terminal_vga.spin      ' terminal services + screen buffer
    └── hires_text_vga.spin    ' dual-cog VGA text (Chip Gracey)
```

Archive demos under `archive/` are not part of the production tree.

## Cog budget (production path)

| Cog role | Source |
|----------|--------|
| Spin main (Cog 0) | `ux_module` event loop: `kbdToZ80` / `termToZ80` / `readZ80` |
| FTDI UART | `terminal_ftdi` PASM |
| ACIA bus | `acia_rc2014` PASM |
| PS/2 | `keyboard_ps2` PASM |
| VGA text ×2 | `hires_text_vga` (two cogs) |

That is six cogs when all start successfully. Two cogs remain. Only the main Spin cog calls `acia.tx`. VECTORJET needs a VGA cog plus multiple render cogs — it does **not** fit beside the full text stack without stopping text VGA / other drivers. See `library-vjet`.

## Main loop data paths

```
PS/2 keyboard ──kbdToZ80──┐
                          ├── acia.tx ──► ACIA tx FIFO ──► Z80
FTDI rx ──termToZ80───────┘
Z80 writes data ──► ACIA rx FIFO ──readZ80──► VGA + FTDI
```

`readZ80` is a non-blocking parser (idle / ESC / CSI / XMODEM). Do not type on the keyboard during XMODEM. Main skips `kbdToZ80` in that case. If FTDI TX is full, `readZ80` holds ACIA `TDRE`. `term.rxFlow` sends XON/XOFF except during XMODEM.

Boot banner `"UX Module Initialised"` goes to FTDI and VGA.

## ACIA emulation (agent-critical)

- One PASM cog watches the decoded I/O address with `WAITPNE` / `WAITPEQ`.
- Match uses `waitpeq … wr` so `/WAIT` asserts via **destination += mask**. Do not drop `wr`. Loop contract: `lang-pasm/references/acia-wait.md`.
- Handler releases `/WAIT` with `or outa, bus_wait` after it places data or captures a write.
- Hub block at `PAR`: `rx_head`, `rx_tail`, `tx_head`, `tx_tail`, `acia_base`, `acia_config`, `acia_status`, `buffer_ptr`, then rx/tx byte FIFOs.
- Perspective: Z80 “receive” is Propeller `tx_*` (host→Z80); Z80 “transmit” is Propeller `rx_*`.
- Spin `tx` sets `RDRF` when CR5/CR6 is not `/RTS` high. Spin `rx` sets `TDRE`. `rxCount` / `rxCheck` are counts only.
- Empty RDR: present 0, do not move `tx_tail`. Full TDR: set `OVRN`, do not store.
- CR5/CR6 is a two-bit field (TIE vs `/RTS` high vs Break). Master reset `$03` zeros both FIFOs.
- `/INT` is a **level** from this cog only (`sync_irq`). Spin must not touch `DIRA[25]`.

Edit with `lang-pasm` + `hw-ux-pcb`. Datasheet: `docs/MC6850.pdf`. OBEX idioms: `lang-pasm/references/obex-pasm.md`.

## VGA text path

- `wmf.init(VGA_BASE_PIN, @gTextCursX)` allocates screen/colour/cursor buffers and starts `hires_text_vga`.
- Default timing block in `hires_text_vga.spin` is selected by which CON section is uncommented; pixel rate `pr` is tuned for ~118 MHz.
- Screen bytes: bit7 = inverse; bits6..0 = glyph. Row colours are words `%%RRGGBB` style.

## Build / upload

1. PropellerIDE (or compatible) with **`ux_module.spin` in the foreground**.
2. Program via FTDI (“Prop Plug” in the IDE).
3. Toggle DTR to reboot stand-alone.

## Agent rules

1. Do not start lib_vjet VGA while `hires_text_vga` still owns P16–P23 and two cogs without an explicit mode switch that stops the text driver.
2. Keep ACIA base selection in one place (`PORT_DEFAULT` / `PORT_ROMWBW` in `ux_module.spin`).
3. Preserve non-blocking main loop behaviour; long work belongs in other cogs.
4. New shared Hub structures need a stated single writer.
5. Prose: `style-ste-writing`.

## Related

- Pins: `hw-ux-pcb`
- Spin/PASM: `lang-spin`, `lang-pasm`
- 3D library: `library-vjet`
