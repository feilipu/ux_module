---
name: library-vjet
description: >
  VECTORJET (lib_vjet) scanline 3D/2D engine for the UX Module: display-list
  Spin API, multi-cog PASM renderer, VGA output cog, double-buffered lists,
  shape types (trap stack, box, text). Use when editing src/lib_vjet or
  integrating graphics with the UX firmware. See ARCHITECTURE_LIB_VJET.md.
---

# Library — VECTORJET (`src/lib_vjet`)

Human architecture note: `ARCHITECTURE_LIB_VJET.md`. Author mark in sources: IRQsome Software (UXM specialisation).

## Files

| File | Role |
|------|------|
| `VJET_v01_displaylist.spin` | Spin display-list builder (API) |
| `VJET_vUXM_rendering.spin` | PASM render cog(s); fills scanline buffer |
| `VJET_vUXM_vga.spin` | PASM VGA output cog; consumes scanlines |
| `hexfont.spin` | Bitmap font for `text*` shapes |
| `vjet_test.spin` / `graphtest.spin` | Top-object demos |

## Pipeline

```
Spin app
  ├─ Vblank (status bit 16) then dlist_ptr := listA
  ├─ WaitListTaken (status bit 17) then gl.start(listB) / draw / gl.done
  ├─ render.start(i, N, scanbuf, @dlist_ptr, @vga_status, @ready)  × N
  └─ vga.start(pinGroup, scanbuf, @vga_status)
         │
         ▼
  render cogs traverse display list → write scanline tiles into scanbuf
         │
         ▼
  VGA cog WAITVID from scanbuf, signals phase in vga_status
```

Resolution in UXM rendering: **WIDTH=256**, **NUM_LINES=240**, **LINE_BUFFERS=8**. VGA driver doubles lines (tileCounter) for display.

`vjet_test.spin` starts **3** render cogs + **1** VGA cog. That alone needs four cogs plus Spin. It cannot run beside the full UX text stack without stopping other drivers (`module-ux` cog budget).

`ux_module.spin` links VGA, rendering, and the display-list builder. Boot stays in text mode. Product graphics uses **2** render cogs plus 1 VGA cog. The spare cog is for a later Spin draw loop. Next slice: start that draw cog from `enterGraphics`, wait `vjetStatus` `$01_00_00` / `$02_00_00`, and grow the lists. Do not call `enterGraphics` from `main`.

Handshake: VGA writes line **240** in every blanking phase (not 0). Render cogs wait for `>= 240`, fill slots 0..7, then stay fewer than eight lines ahead of the live line. Spin publishes `dlist_ptr` at front porch and waits for vsync bit 17 before it rebuilds the other list.

Video PLL: NCO 5 MHz, VCO/2, VCO 80 MHz (spec 64–128). Do not restore 10 MHz NCO + VCO/4 (VCO 160 MHz).

## Display list format

Shape header (8 bytes), then type-specific body:

```
WORD  pointer to next shape or 0
BYTE  renderer sync line
BYTE  shape type
WORD  start scanline
WORD  end scanline
```

| Type | Name | Body (after header) |
|------|------|---------------------|
| 1 | `SHP_TRAPSTACK` | 16-byte trap header + N×12-byte trapezoids |
| 2 | `SHP_BOX` | left, right, colours, unused (words) |
| 3 | `SHP_TEXT` | scale, font ptr, string ptr, colours, x |

Coordinates in the Spin API often use **16.16** fixed point (shift `<<16`). Colours are packed words consumed by the renderer/VGA path (two paint colours common in demos, e.g. `$ECEC`).

Builder calls:

- `start(ptr,size)` / `done` — begin/end list; `done` aborts link on overflow
- `set_clip(t,b,l,r)`
- `triangle` / `polygon` / `box` / `line` / `point` / `text*`

Overflow uses Spin `ABORT`. Callers in demos use `\draw` to trap it.

## Double buffering

Demos flip `dlist_ptr` each frame and rebuild the inactive buffer. Render cogs read `dlist_ptr` through `dlistPtrAdr` at frame start. Wait for vertical blank via `vga_status` bit 16 (`Vblank`), publish the pointer, then wait for vsync bit 17 (`WaitListTaken`) before `gl.start` on the other list.

## VGA cog (`VJET_vUXM_vga.spin`)

- `start(pinGroup, lineBuffers, statusLong)` — `pinGroup` 0..3; UX uses `16/8` → group 2
- Sets `VCFG` VGA mode, CTRA PLL video mode, drives eight pins
- Writes phase codes into `statusLong` (front porch / vsync / back porch / active). Low word is 240 in all three blanking phases.

## Agent rules

1. Keep display-list field sizes and offsets matched between `VJET_v01_displaylist.spin` comments and renderer PASM readers.
2. Do not change `WIDTH` / `NUM_LINES` / `LINE_BUFFERS` in one file only; scan buffer size in the top object must match `(WIDTH*LINE_BUFFERS)/4` longs. VGA wrap is `tilesCounter & (LINE_BUFFERS-1)`.
3. Preserve top-edge trap fixup and per-cog scanline striping (`currentscanline += total_cogs`).
4. Treat UXM files as board-specialised; do not assume stock VECTORJET v1.0 timing.
5. Do not write line 0 during vsync or back porch. Do not let a render cog write more than `LINE_BUFFERS` lines ahead of VGA.
6. Stop text VGA (`wmf.stop`) **and** the I2C DDC cog (`i2c.stopCog`) before `VJET_vUXM_vga.start`. Stop VECTORJET VGA and `render.stop` before `wmf.init` and `i2c.startCog`. Never two VGA engines on P16–P23. Product switch is `enterGraphics` / `enterText` in `ux_module.spin`. Do not call `enterGraphics` from `main`.
7. Do not put the display-list builder on Cog 0 if ACIA must keep pumping (`module-ux`).
8. Prose: `style-ste-writing`.

## Related

- Hardware video: `hw-propeller`
- Board pins: `hw-ux-pcb`
- Product cog budget: `module-ux`
- PASM detail: `lang-pasm`
