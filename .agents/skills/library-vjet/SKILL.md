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
| `VJET_vUXM_rendering.spin` | PASM render cog(s); beam-chase scanlines |
| `VJET_vUXM_vga.spin` | PASM VGA output cog; beam chase |
| `VJET_vUXM_rendering_fb.spin` | PASM render cogs; framebuffer bitmap |
| `VJET_vUXM_vga_fb.spin` | PASM VGA cog; scans the finished bitmap |
| `hexfont.spin` | Bitmap font for `text*` shapes |
| `demo/vjet_test.spin` | Original demo. Beam chase. Spinning triangles. |
| `demo/vjet_fb.spin` | Framebuffer demo. The same picture. |
| `vjet_fb_cube.spin` | Stage 2 cube harness. Not a demo. |
| `vjet_fb_probe.spin` | Stripe and glass check. Not a demo. |
| `graphtest.spin` | Graph drawing sample. Not one of the two demos. |

## Pipeline

```
Spin app
  ├─ Vblank (bit 16 rises, front porch) then dlist_ptr := listA
  ├─ gl.start(listB) / draw / gl.done
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

`demo/vjet_test.spin` starts **3** render cogs + **1** VGA cog. That alone needs four cogs plus Spin. It cannot run beside the full UX text stack without stopping other drivers (`module-ux` cog budget).

`ux_module.spin` does not link this library. Demos are their own tops. Do not start VECTORJET from product `main`.

One busy Spin cog during the picture. `vjet_test`, plus the ACIA cog, plus the FTDI cog, stays clean while Cog 0 builds the list. A second cog in a tight Spin loop tears that picture.

Cog 0 in the bring-up has about 2KB of free Hub. Drawing there overrun that space, the picture tore, then the signal stopped. Park Cog 0 on `waitcnt`. Run the draw loop on another cog. Use the text buffer as that stack while text VGA is stopped. The text buffer is 800 longs. Stop that cog before `screenInit`.

The stage-1 bring-up keeps the ACIA cog and the FTDI cog. The PS/2 cog stops for that session. Three render cogs, as in `vjet_test`. Cog 0 does not pump the FIFOs during the picture.

Handshake: front porch writes line 240. Vsync and the back porch write line 0. Render cogs wait for line 0. The variant that writes line 240 in every blanking phase tore at 720×480 at 60 Hz. The demo uses the 2021 handshake.

`vjet_test` sets `dlist_ptr` to `$8080`, sets the ready flag, then Cog 0 publishes a real list on the next vblank. That order stays clean. A render cog that keeps reading `$8080` can stay in the shape fixup, so Cog 0 must publish on that next vblank. Do not hand the publish to a cog that is not running yet.

Pass `render.start` a long-aligned ready flag. `cognew` keeps only bits 15:2 of that address. A byte flag makes the render cogs wait on a different byte.

Video PLL: demo setting is NCO 10 MHz, VCO/4, VCO 160 MHz. A 5 MHz NCO with VCO/2 did not lock on the target monitor. Keep the demo PLL until a locked replacement is measured.

## Display list format

Shape header (8 bytes), then type-specific body:

```
WORD  pointer to next shape or 0
BYTE  renderer sync line
BYTE  shape type
WORD  start scanline
WORD  end scanline
```

| Type | Name | Body after the 8-byte header | Stored |
|------|------|------------------------------|--------|
| 1 | `SHP_TRAPSTACK` | 16-byte edges + N×12-byte trapezoids | 36 flat, 48 general |
| 2 | `SHP_BOX` | left, right, colours, unused | 16 |
| 3 | `SHP_TEXT` | scale, font, string, colours, x, unused | 20 |

A polygon is a trap stack. It stores 24 bytes plus 12 bytes for each trapezoid. A sloped line stores 36 bytes. A horizontal line stores 16 bytes. The builder skips the 8 current-edge bytes. The renderer writes them.

Coordinates in the Spin API often use **16.16** fixed point (shift `<<16`). Colours are packed words consumed by the renderer/VGA path (two paint colours common in demos, e.g. `$ECEC`).

Builder calls:

- `start(ptr,size)` / `done` — begin/end list; `done` aborts link on overflow
- `set_clip(t,b,l,r)`
- `triangle` / `polygon` / `box` / `line` / `point` / `text*`

Overflow uses Spin `ABORT`. Callers in demos use `\draw` to trap it.

## Double buffering

Demos flip `dlist_ptr` each frame and rebuild the inactive buffer. Render cogs read `dlist_ptr` through `dlistPtrAdr` at frame start, when the VGA low word is 0. Wait until bit 16 rises (front porch), publish the pointer, then call `gl.start` on the other list. The front porch low word is 240. Vertical sync and the back porch use a low word of 0.

## VGA cog (`VJET_vUXM_vga.spin`)

- `start(pinGroup, lineBuffers, statusLong)` — `pinGroup` 0..3; UX uses `16/8` → group 2
- Sets `VCFG` VGA mode, CTRA PLL video mode, drives eight pins
- Writes phase codes into `statusLong` (front porch / vsync / back porch / active). The front porch low word is 240. Vsync and the back porch use a low word of 0.
- Visible pixels: prime one group, then `WAITVID`, then read the next group while that group shifts. The last group of the line has no read past the line. Keep `visibleScale` at `(4 << 12) + 16`.

## Framebuffer path

`demo/vjet_fb.spin` does not chase the beam. The VGA cog scans a finished 256×80 bitmap, two bits per pixel. Each group of 16 pixels has four colours. The cog shows each stored line six times. The renderer stores lines 0, 3, 6, and so on. Two buffers. A late frame repeats. The PLL, the porches, and `VCFG` stay on the 2021 line. PixelClocks for the visible pixels is 4. Visible FrameClocks stays 16.

Bit 0 of a colour byte marks a stripe. The dark lines of that band show the colour $55 lower. The flag is set only when the high byte is the low byte minus $55. Any other pair stays solid.

Bit 1 of that byte asks for a 50 percent mix when the control long `blend` (after `fixup`) is set. A clear `blend` leaves the span solid. A solid span returns. It does not enter the mix. The mix averages red, green, and blue as separate pairs.

Even stored lines are bright, bright, dark, dark, bright, bright. Odd stored lines use the inverse order. The user accepted this picture on 17 Oct 2026. It is the known-good image. The forward plan is `3D_WORKPLAN_LIB_VJET.md`. The repair record is `3D_PROCESS_LIB_VJET.md`.

The accepted scene draws 13 triangles and one text shape. That list uses at most 632 bytes. Each list is 1200 bytes. A flat triangle is 36 bytes. A general triangle is 48 bytes. A box is 16 bytes and a text shape is 20 bytes.

`VJET_vUXM_vga.spin` and `VJET_vUXM_rendering.spin` stay the beam-chase pair. Do not copy the framebuffer `VSCL` into those files.

## Agent rules

1. Keep display-list field sizes and offsets matched between `VJET_v01_displaylist.spin` comments and renderer PASM readers.
2. Do not change `WIDTH` / `NUM_LINES` / `LINE_BUFFERS` in one file only; scan buffer size in the top object must match `(WIDTH*LINE_BUFFERS)/4` longs. VGA wrap is `tilesCounter & (LINE_BUFFERS-1)`.
3. Preserve top-edge trap fixup and per-cog scanline striping (`currentscanline += total_cogs`).
4. Treat UXM files as board-specialised; do not assume stock VECTORJET v1.0 timing.
5. Keep the demo handshake. Vsync and the back porch publish line 0. A render cog restarts its frame when the VGA line is 0 and its own line is 16 or more.
6. Stop text VGA (`wmf.stop`), the I2C DDC cog (`i2c.stopCog`), and the PS/2 cog before `VJET_vUXM_vga.start`. Stop VECTORJET VGA and `render.stop` before `wmf.init` and `i2c.startCog`. Never two VGA engines on P16–P23. The product top has no `enterGraphics` yet.
7. Park Cog 0 on `waitcnt` during the picture. A tight Spin loop beside the draw cog tears the scene. Do not draw on Cog 0. Free Hub above the bring-up is about 2KB, and the scene overruns it. Give the draw cog the text buffer as its stack, and stop that cog before `screenInit`. Leave the ACIA cog running. Cog 0 does not pump `acia.tx` during the picture.
8. Prose: `style-ste-writing`.

## Related

- Hardware video: `hw-propeller`
- Board pins: `hw-ux-pcb`
- Product cog budget: `module-ux`
- PASM detail: `lang-pasm`
