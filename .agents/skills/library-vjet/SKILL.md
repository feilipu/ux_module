---
name: library-vjet
description: >
  VECTORJET (lib_vjet) scanline 3D/2D engine for the UX Module: display-list
  Spin API, multi-cog PASM renderer, VGA output cog, double-buffered lists,
  shape types (trap stack, box, text). Use when editing src/lib_vjet or
  integrating graphics with the UX firmware. See ARCHITECTURE_LIB_VJET.md.
---

# Library — VECTORJET (`src/lib_vjet`)

Human architecture note: `ARCHITECTURE_LIB_VJET.md`. The 2020 and 2021 objects keep the IRQsome mark. A new file uses (C)2026 feilipu. A file derived from an IRQsome object states that source and uses 2026.

## Files

| File | Role |
|------|------|
| `VJET_v01_displaylist.spin` | Spin display-list builder (API) |
| `VJET_vUXM_rendering.spin` | PASM render cog(s); beam-chase scanlines |
| `VJET_vUXM_vga.spin` | PASM VGA output cog; beam chase |
| `VJET_vUXM_rendering_fb.spin` | PASM render cogs; framebuffer bitmap |
| `VJET_vUXM_vga_fb.spin` | PASM VGA cog; scans the finished bitmap |
| `hexfont.spin` | Bitmap font for `text*` shapes |
| `demo/head_slice.spin` | Beam-chase head. Not a compile top. |
| `demo/head_fb.spin` | Framebuffer head. Not a compile top. |
| `scene/scene_triangles.spin` | Spinning triangles. Both heads can include it. |
| `scene/scene_graph.spin` | Graph picture. Beam-chase head only. |
| `scene/scene_probe.spin` | Orbit probe. Beam-chase head. One box and nine triangles. |
| `scene/scene_cube.spin` | Cube mesh. Framebuffer head only. |
| `scene/scene_card.spin` | Test card. No compile top includes it. |
| `demo/vjet_test.spin` | Original demo. Defines the triangle scene. Includes the beam-chase head. |
| `demo/vjet_fb.spin` | Framebuffer demo. The same picture. Includes the framebuffer head. |
| `demo/vjet_acia.spin` | Beam-chase triangles plus the ACIA cog. |
| `demo/vjet_ftdi.spin` | Beam-chase triangles plus the ACIA cog and the FTDI cog. |
| `demo/vjet_spin.spin` | Beam-chase triangles plus one extra Spin cog. The picture tears. |
| `demo/vjet_fb_cube.spin` | Stage 2 cube harness. Not a demo. |
| `demo/vjet_probe.spin` | Beam-chase orbit probe. Eight line slots. Do not load the framebuffer probe. |
| `demo/vjet_fb_probe.spin` | Old framebuffer copy of the orbit probe. Do not load it. |
| `demo/graphtest.spin` | Graph drawing sample. Not one of the two demos. |

The six library objects stay in `src/lib_vjet/`. Compile tops and both heads are in `demo/`. Display lists are in `scene/`. A top in `demo/` defines one `SCENE_*` macro and includes one head. The head includes `scene/scene_*.spin`. Compile the top with `-L src -L src/lib_vjet`.

`demo/head_fb.spin` defines `SCENE_FB` before the triangle scene. That branch drops two unused local names. The framebuffer image then matches the earlier compile.

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

The beam-chase picture stays clean with one Spin cog. A second cog in a tight Spin loop tears that picture. Do not draw that path on Cog 0. The free Hub there is 1160 bytes. Cog 0 keeps a 256-long stack and 16 longs of `_FREE`. 18 longs remain above that pair.

The bring-up is `src/ux_module_vjet.spin`. It stops text VGA, DDC, and the input that did not request graphics. It starts the beam-chase VGA cog, three render cogs, and one draw cog. The draw cog uses `drawStack` (192 longs). Cog 0 returns to the ACIA pump. The slice is eight lines. Graphics mode shows the spinning triangles. Boot stays the text console. Far triangles are drawn first. This renderer has no 50 percent mix. The render wait starts the next line when the beam has passed current + cogs - 8. With three cogs that lead is 7 logical lines. Each render cog rebuilds both edges from the initial edges and the slopes. The cog does not read the sync byte. The cog does not write the edges in the list. The draw cog waits until the front porch, then builds the next list. The cog records the spans before the slot write. The slot write is one fill and then those spans. A full-width first span fills with that colour. A shape that starts above line 0 is walked from its initial edges. This cog does not write those edges.

One scan line keeps 24 records. A box, a point, a line, a polygon, or a text shape uses one record. A text shape is stored in list order with the spans. A shape after these 24 records on that line is skipped. The skipped shapes are the front shapes.

The final build keeps the keyboard. Graphics has no free cog, so the keyboard shares the FTDI cog. That driver is not in the tree.

Handshake: front porch writes line 240. Vsync and the back porch write line 0. Render cogs wait for line 0. The variant that writes line 240 in every blanking phase tore at 720×480 at 60 Hz. The demo uses the 2021 handshake.

`vjet_test` sets `dlist_ptr` to `$8080`, sets the ready flag, then Cog 0 publishes a real list on the next vblank. That order stays clean. `$8080` is ROM. A render cog that still has that pointer reads ROM on every line, so Cog 0 must publish on that next vblank. Do not hand the publish to a cog that is not running yet.

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

A polygon is a trap stack. It stores 24 bytes plus 12 bytes for each trapezoid. A trap height of 0 ends the shape. When two chains meet on one scanline, the builder advances both chains. It does not store a height of 0. The last trapezoid includes the bottom scanline. A sloped line stores 36 bytes. A horizontal line stores 16 bytes. The builder skips the 8 current-edge bytes. The beam-chase cog does not write them. The framebuffer cog writes them while it walks.

Coordinates in the Spin API often use **16.16** fixed point (shift `<<16`). Colours are packed words consumed by the renderer/VGA path (two paint colours common in demos, e.g. `$ECEC`).

Builder calls:

- `start(ptr,size)` / `done` — begin/end list; `done` aborts link on overflow
- `set_clip(t,b,l,r)`
- `triangle` / `polygon` / `box` / `line` / `point` / `text*`

Overflow uses Spin `ABORT`. Callers in demos use `\draw` to trap it. `done` returns a negative value when the list overflowed. There is no room query.

## Caller contract

`box`, `point`, and `text` take integer pixels. `triangle`, `line`, and `polygon` take 16.16 values. `set_clip` takes 16.16 values. Call `set_clip` before the first shape. A clip of 0 draws nothing.

`polygon` stores one convex face. Pass `ccw` as -1, 0, or +1. A value of 0 detects the winding from the top vertex. A flat top can detect the wrong side.

The host clips the face in Y. The builder does not clip X. The span recorder clamps X to the screen.

The face must reach its bottom scanline. A short face stays linked. The trap walk then reads the next shape. One scan line keeps 24 records. The builder does not report a skipped shape.

Catch overflow with `\` and call `done`. `done` seals the list. One cog calls this object. Two cogs must not share it.

`start` writes the first link to `$8080`. That address is ROM. Publish the pointer passed to `start`.

On the beam-chase path, an even line uses the low colour byte. An odd line uses the high byte. Equal bytes are a solid colour. The VGA cog sets the low two bits of each byte. This path has no 50 percent mix. A framebuffer stripe pair is a different picture.

The text string stays outside the list. `text_inline` copies it in. The font stays in Hub for the whole frame. Pair `VJET_vUXM_vga.spin` with `VJET_vUXM_rendering.spin`. The framebuffer files are the other engine.

## Double buffering

Demos flip `dlist_ptr` each frame and rebuild the inactive buffer. Render cogs read `dlist_ptr` through `dlistPtrAdr` at frame start, when the VGA low word is 0. Wait until bit 16 rises (front porch), publish the pointer, then call `gl.start` on the other list. The front porch low word is 240. Vertical sync and the back porch use a low word of 0.

## Streamed lists

The ACIA receive ring is the pipe. Cog 0 is its only reader. A complete list is written into the display list that `dlist_ptr` does not name. `dlist1` and `dlist2` are that pair. Each is 1184 bytes.

The first list is copied there before `enterGraphics`. Later lists use the same pair. Cog 0 appends bytes as the ring drains. The draw cog publishes the filled pointer on the front porch, then the other list is the next fill target. A list that is still filling stays unpublished. The published list stays on screen.

The draw cog does not call `gl.start` on a list Cog 0 is filling. The ACIA cog does not write either list.

The lead-in and the parser states are in `3D_WORKPLAN_LIB_VJET.md`. Command bytes are not frozen. The pair stays a 6850 for this trial.

Compile `src/ux_module_vjet.spin` with `openspin -u`. `main` calls `font.get` so the font stays. EEPROM holds the 16460 byte image. The mode flag powers up clear. Boot is the text console. Graphics mode shows the spinning triangles on the eight-line renderer. The field is one full-screen triangle. Do not load a framebuffer image. Do not replace that triangle with a box to skip a tall trap. Do not add a hub edge cache.

`startVectorjet` does not clear a list that is ready or still filling. While `listReady` is set, Cog 0 leaves the next mark in the receive ring. After `listShown` is set, the draw cog does not rebuild the test card.

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

The accepted scene draws 13 triangles and one text shape. That list uses at most 632 bytes. A flat triangle is 36 bytes. A general triangle is 48 bytes. A box is 16 bytes and a text shape is 20 bytes.

Each framebuffer list is 1200 bytes. That holds 33 flat triangles or 25 general triangles. Each beam-chase demo list is 3600 bytes. That holds 100 flat triangles or 75 general triangles. The larger list adds 67 flat triangles or 50 general triangles. The slice bring-up lists stay 296 longs.

The bring-up scene is the spinning triangles. The demo does not call `set_lines`.

`VJET_vUXM_vga.spin` and `VJET_vUXM_rendering.spin` stay the beam-chase pair. Do not copy the framebuffer `VSCL` into those files.

The 80-line bitmap pair is 20480 bytes. The list stays allocated beside it. The bring-up no longer keeps that pair. `LINE_BUFFERS` is 8. The slice is 2048 bytes.

Three render cogs write that slice ahead of the scan. The original renderer used two cogs. Leave `STORED_LINES` at 80. Leave `demo/vjet_fb.spin` as the accepted picture.

## Agent rules

1. Keep display-list field sizes and offsets matched between `VJET_v01_displaylist.spin` comments and renderer PASM readers.
2. Do not change `WIDTH` / `NUM_LINES` / `LINE_BUFFERS` in one file only; scan buffer size in the top object must match `(WIDTH*LINE_BUFFERS)/4` longs. VGA wrap is `tilesCounter & (LINE_BUFFERS-1)`.
3. Keep the top-edge trap fixup as a block comment. The line walk reads the initial edges. Keep per-cog scanline striping (`currentscanline += total_cogs`).
4. Treat UXM files as board-specialised; do not assume stock VECTORJET v1.0 timing.
5. Keep the demo handshake. Vsync and the back porch publish line 0. A render cog restarts its frame when the VGA line is 0 and its own line is 16 or more.
6. Stop text VGA (`wmf.stop`) and the I2C DDC cog (`i2c.stopCog`) before `VJET_vUXM_vga.start`. Stop VECTORJET VGA and `render.stop` before `wmf.init` and `i2c.startCog`. Never two VGA engines on P16–P23. The product top has no `enterGraphics` yet.
7. On the slice bring-up, Cog 0 keeps the ACIA pump. The draw cog uses `drawStack`. Stop that cog before `screenInit`. Three render cogs stay. Graphics then has no free cog. The bring-up keeps the input that requested graphics and stops the other input. Cog 0 does not call `term.tx` while the FTDI cog is stopped.

   The FTDI arm calls `termToZ80`. The PS/2 arm calls `kbdToZ80`. The final build keeps the keyboard on the FTDI cog and calls `kbdToZ80` in that branch. The shared driver is not in the tree. Do not load a guess. On the beam-chase path, a second tight Spin loop tears the picture.
8. Prose: `style-ste-writing`.
9. Leave the six library objects in `src/lib_vjet/`. OpenSpin resolves a bare object name from the current directory, each `-L` path, and the top file's directory. Include a scene as `scene/name.spin`. Do not compile a head or a scene file.
10. Keep the IRQsome mark on the 2020 and 2021 objects. A new file uses (C)2026 feilipu. A derived file states the IRQsome source and uses 2026. `hexfont.spin` stays the Aaron Amar font.

## Related

- Hardware video: `hw-propeller`
- Board pins: `hw-ux-pcb`
- Product cog budget: `module-ux`
- PASM detail: `lang-pasm`
