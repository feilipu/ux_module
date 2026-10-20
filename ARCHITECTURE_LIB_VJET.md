# Architecture — VECTORJET (`lib_vjet`)

This note describes the 2D/3D scanline engine under `src/lib_vjet`.  
Agent edit rules: `.agents/skills/library-vjet`, `hw-propeller`, `lang-pasm`.  
Prose style: `.agents/skills/style-ste-writing`.

## Purpose

VECTORJET builds a display list in Spin, renders scanlines with one or more PASM cogs, and outputs VGA with a dedicated PASM cog. The UXM-prefixed files are a specialisation for the RC2014 UX Module pinout and clock. Upstream credit in the sources: IRQsome Software, with VGA lineage from Kwabena W. Agyeman / Parallax-style video generators.

The 2020 and 2021 objects keep the IRQsome mark. A new file uses (C)2026 feilipu. A file derived from an IRQsome object states that source and uses 2026. `hexfont.spin` is the Aaron Amar font.

The product top `ux_module.spin` does not link this library. The six library objects stay in `src/lib_vjet/`. Compile tops and both heads are in `src/lib_vjet/demo/`. Display lists are in `src/lib_vjet/scene/`. The two demos are `src/lib_vjet/demo/vjet_test.spin` and `src/lib_vjet/demo/vjet_fb.spin`. Compile a demo with `-L src -L src/lib_vjet`.

## Files

| File | Layer |
|------|-------|
| `VJET_v01_displaylist.spin` | Spin API: clip, shapes, text, list packing |
| `VJET_vUXM_rendering.spin` | PASM renderer cog program |
| `VJET_vUXM_vga.spin` | PASM VGA output cog |
| `hexfont.spin` | Font blob for text shapes |
| `VJET_vUXM_rendering_fb.spin` | Framebuffer solution. PASM render cogs. |
| `VJET_vUXM_vga_fb.spin` | Framebuffer solution. PASM VGA cog. |
| `demo/head_slice.spin` | Beam-chase head. A top includes it. Not a compile top. |
| `demo/head_fb.spin` | Framebuffer head. A top includes it. Not a compile top. |
| `scene/scene_triangles.spin` | Spinning triangles. Both heads can include it. |
| `scene/scene_graph.spin` | Graph picture. Beam-chase head only. |
| `scene/scene_probe.spin` | Orbit probe. Beam-chase head. |
| `scene/scene_cube.spin` | Cube mesh. Framebuffer head only. |
| `scene/scene_card.spin` | Test card. No compile top includes it. |
| `demo/vjet_test.spin` | Original demo. Beam chase. Spinning triangles. |
| `demo/vjet_fb.spin` | Framebuffer demo. The same picture. |
| `demo/vjet_acia.spin` | Beam-chase triangles plus the ACIA cog. |
| `demo/vjet_ftdi.spin` | Beam-chase triangles plus the ACIA cog and the FTDI cog. |
| `demo/vjet_spin.spin` | Beam-chase triangles plus one extra Spin cog. The picture tears. |
| `demo/vjet_fb_cube.spin` | Stage 2 cube harness. Not a demo. |
| `demo/vjet_fb_probe.spin` | Stripe and glass check. Not a demo. |
| `demo/graphtest.spin` | Graph drawing sample. Not one of the two demos. |

## Runtime pipeline

```
Application (Spin top object)
    │
    │  build display list into back buffer
    │  publish pointer in dlist_ptr
    │
    ├───────────────► Render cog 0 ──┐
    ├───────────────► Render cog 1 ──┼──► shared scanline buffer (Hub)
    └───────────────► Render cog N ──┘              │
                                                    ▼
                                            VGA cog (WAITVID)
                                                    │
                                                    ▼
                                            pins P16–P23 (group 2)
```

`demo/vjet_test.spin` starts three render cogs and one VGA cog. It waits for vertical blank through `vga_status`, publishes the completed list, waits for vsync so the render cogs copy the pointer, then rebuilds the other list.

## Scanline handshake (tear / flicker)

The Hub scan buffer holds eight logical lines (`LINE_BUFFERS`). The VGA cog displays line `N` from slot `N & 7` and writes `N` into `vga_status`.

Front porch writes line 240. Vsync and the back porch write line 0. Render cogs wait for line 0, then stay behind the VGA cog.

Each render cog takes every third line. It rebuilds both edges from the initial edges and the slopes. It does not wait on the sync byte. The line wait still holds the cog until the beam has passed that slot.

It records the spans before the slot write. The slot write is one fill and then the spans. A full-width first span fills with that colour.

The live painter writes those longs into the Hub VGA slot. The VGA cog scans that slot twice. A write during those two scans tears the line. Failed repairs of that race are in `3D_PROCESS_LIB_VJET.md`.

One scan line keeps 24 records. A box, a point, a line, a polygon, or a text shape uses one record. A text shape is stored in list order with the spans. A shape after these 24 records on that line is skipped. The skipped shapes are the front shapes.

Even logical lines use the low colour byte. Odd logical lines use the high colour byte. The VGA cog shows each logical line twice. It forces the low two bits of every colour byte on.

A later handshake wrote line 240 in every blanking phase. With the demo PLL the monitor read 720×480 at 60 Hz and the picture tore. The demo uses the 2021 handshake.

## Video PLL

`VJET_vUXM_vga` sets CTRA PLL internal, VCO/4. The NCO target is 10 MHz. VCO is 160 MHz. PLLA is 40 MHz on that divider. VSCL uses 4 clocks per pixel, so the pixel rate is 10 MHz.

A 5 MHz NCO with VCO/2 holds VCO at 80 MHz. That picture did not lock. The monitor menu read 1920×1080. The demo PLL stays until a locked replacement is measured.

`hires_text_vga` uses a different PLL setup (`pr` in MHz, VCO/2) for 640×480 text. Do not copy VECTORJET FRQA into the text driver or the reverse.

## Resolution and buffers

Rendering constants in `VJET_vUXM_rendering.spin`:

- Width: 256 pixels
- Height: 240 scanlines

The VGA cog repeats each logical line (tile counter) so the analogue timing fills a taller raster. The Hub scan buffer is `linebuffers[(WIDTH*LINE_BUFFERS)/4]` longs (eight line slots).

Display lists are Hub longs. The beam-chase demos use two lists of 900 longs. That size does not fit beside the UX text buffers. The framebuffer tops use two lists of 300 longs. Each of those lists is 1200 bytes.

## Framebuffer

`demo/vjet_fb.spin` is the framebuffer demo. The user accepted that picture on 17 Oct 2026. The VGA cog scans a finished 256 by 80 bitmap. Two bits select one of four colours in each group of 16 pixels. The renderer stores lines 0, 3, 6, and so on. The VGA cog shows each stored line six times.

Bit 0 of a colour byte marks a stripe. Dark lines of that band show the colour $55 lower. Even stored lines are bright, bright, dark, dark, bright, bright. Odd stored lines use the inverse order. The colours `$0055`, `$55AA`, and `$AAFF` stripe. Equal bytes stay solid.

The program on disk is 8044 bytes. The variables are 23776 bytes. The PLL, the porches, and `VCFG` stay on the 2021 line. PixelClocks is 4. FrameClocks is 16. Do not copy that `VSCL` into `VJET_vUXM_vga.spin`.

Each frame draws 13 triangles and one text shape. The list uses at most 632 bytes. Each of the two lists is 1200 bytes. A flat triangle is 36 bytes and a general triangle is 48 bytes. A box is 16 bytes and a text shape is 20 bytes. The shape rules are in `3D_WORKPLAN_LIB_VJET.md`.

The stripe test is general for a high byte that is the low byte minus $55. Any other pair stays solid. Later shapes overwrite earlier spans. There is no depth buffer.

Bit 1 of the low colour byte asks for a 50 percent mix with the pixel already on the line. The mix runs only when the control long `blend` is set. That long follows `fixup`. A clear `blend` leaves every span solid.

A solid span returns. It does not enter the mix. The mix reads and writes one byte at a time. It averages red, green, and blue as separate pairs.

The repair record is `3D_PROCESS_LIB_VJET.md`. The forward plan is `3D_WORKPLAN_LIB_VJET.md`.

## Line slice — 18 Oct 2026

The framebuffer and the display list are two stores. The render cogs read the list and write the bitmap. The VGA cog scans the bitmap. Both stores stay for the whole program. The next frame overwrites the back list from the first byte.

Two bitmaps and two palettes at 80 lines are 20480 bytes. The bring-up stores 10 content lines. That pair does not fit beside the text console. The VGA cog repeats each stored line six times. Those repeats use no extra Hub.

The beam-chase path keeps eight line slots. The slice is 2048 bytes. Each slot is one byte per pixel. The render cogs fill the slot ahead of the scan. The VGA cog reads the slot for the line that is due. `LINE_BUFFERS` is 8.

The demo source starts three render cogs. A trial on 16 Oct 2026 used two render cogs. That picture tore. The original renderer used two cogs. Three cogs on this slice must stay ahead of the scan.

The next bring-up load uses that slice. `demo/vjet_fb.spin` stays the accepted picture. `STORED_LINES` stays 80.

## Hub-paint and tear — 20 Oct 2026

The live bring-up paints Hub slots in place. EEPROM holds 16460 bytes from commit `6615776`. Graphics mode builds `scene/scene_triangles.spin`. The field is one full-screen triangle.

The picture still tears on doubled scanlines. Pace, a Hub edge cache, a cog-RAM `linebuf`, and a Hub scratch copy all failed. Those loads also broke keys, doubled line feeds, or blocked the return to text. The process file lists each load. Do not restore them.

## Display list model

Each shape starts with an 8-byte header:

1. Link word to the next shape (0 = end)
2. Sync byte for renderer coordination
3. Shape type byte
4. Start scanline word
5. End scanline word

Types:

| ID | Name | Role |
|----|------|------|
| 1 | Trapezoid stack | Filled poly/triangle decomposition with per-trap slopes |
| 2 | Box | Axis-aligned span with colours |
| 3 | Text | Scaled glyphs from a font pointer + string pointer |

The Spin builder exposes helpers such as `triangle`, `polygon`, `box`, `line`, `point`, and `text_centered`. Many coordinates use 16.16 fixed point. `set_clip` limits geometry. `done` seals the list and breaks the link if the builder ran out of space (`ABORT`).

## Renderer cog behaviour

On `start(cognum, totalcogs, scanbuffer, dlistPtrAdr, videoSync, readyptr)` the object copies parameters into DAT longs and `cognew`s the PASM entry.

Each cog:

1. Waits until `vga_status` low word is `>= 240` (blanking)
2. Reads the current display-list pointer
3. Optionally fixes trapezoids that start above Y0 (top clip)
4. Renders every Nth scanline (`cognum`, `cognum+totalcogs`, …)
5. Writes pixels into the shared scanline buffer for the VGA cog
6. Waits if the next line would wrap onto a slot the VGA cog still displays

Call `render.stop` before you start text VGA on the same pins.

Init instructions are overlaid by live variables after boot. Do not treat early DAT labels as free code space without reading the reuse comments.

## VGA cog behaviour

`VJET_vUXM_vga.start(pinGroup, lineBuffers, statusLong)`:

- Programs `VCFG` for VGA on the selected pin group
- Starts CTRA in PLL video mode
- Loops active lines with `WAITVID`, then front porch, vertical sync, and back porch
- Publishes phase flags in `statusLong` so Spin can wait for blanking
- Writes line 240 on the front porch only. Vertical sync and the back porch write line 0.

For the UX Module, demos pass `pinGroup = 16/8` (group 2 → P16–P23), which matches the board VGA connector.

## Integration with UX firmware (exclusive video mode)

Pins P16–P23 have one owner. `hires_text_vga` (two cogs, 640×480 cells) and `VJET_vUXM_vga` (one cog, 256×240 scanlines) must not run at the same time.

| Mode | Video cogs | Other cogs that stay | Free |
|------|------------|----------------------|------|
| Text | 2 (`hires_text_vga`) + 1 I2C DDC | Spin, FTDI, ACIA, PS/2 (4) | 1 |
| Graphics | 1 slice VGA + 3 render + 1 draw | Spin, ACIA, and the input that requested graphics. The other input stops. | 0 |

The product firmware does not call `enterGraphics`. When graphics work resumes, stop the text pair and `i2c.stopCog` before VECTORJET VGA. Stop VECTORJET, then `wmf.init` and `i2c.startCog`. After `cogstop`, those cogs leave the pins. Then start the other driver.

The final graphics build keeps the PS/2 keyboard. Graphics has no free cog. The keyboard shares the FTDI cog. Detail is in `ARCHITECTURE_UX_MODULE.md`. The shared driver is not in the tree. The bring-up keeps the input that requested graphics and stops the other input.

Do **not** build the display list on Cog 0 if the ACIA pump must stay live. Cog 0 is the only `acia.tx` writer. `vjet_test` blocks Cog 0 in `Vblank` + `draw`. That starves keyboard, FTDI, and Z80 I/O.

Recommended product split:

1. **Text mode** — current `ux_module` path. Z80 console on VGA text.
2. **Graphics mode** — stop text VGA and DDC. Start the framebuffer VGA cog and three render cogs. Start a second Spin cog for the display list. Cog 0 keeps the ACIA pump. Keep PS/2 on the FTDI cog. That uses all eight cogs.
3. **Standalone demo** — `vjet_test` / `graphtest` as now (no ACIA). Three render cogs on Cog 0 as the draw loop.

The product top has no graphics hooks. `PORT_VJET` remains a reserved ACIA base. Serial tests use the text boot path.

Hub cost for the beam chase is the scan buffer and the lists. Eight line slots are 2 KB. Two lists of 900 longs are about 7 KB. The framebuffer store is the larger cost. Two bitmaps and two palettes are 20480 bytes. The two 300-long lists are 2400 bytes.

`PORT_VJET = acia#PORT_C0` is reserved for a later Z80 command port. There is no I/O protocol in-tree yet. A first protocol can be: command byte, then words that Spin copies into the back list, then a flip at vblank.

## Extension points

Useful work while keeping the architecture intact:

1. When graphics work resumes, start a Spin draw cog (not Cog 0). The accepted picture is the framebuffer demo `demo/vjet_fb.spin`. The bring-up path is in `3D_WORKPLAN_LIB_VJET.md`. The repair record is `3D_PROCESS_LIB_VJET.md`.
2. The framebuffer demos keep lists of 300 longs. The bring-up lists are 64 longs, because ten stored lines fill the Hub. Two 900-long lists overflow the bring-up by 768 longs.
3. Drive the back list from Z80 I/O at `PORT_VJET` (needs a command protocol)
4. Tune render cog count against available cogs and fill rate
5. Keep display-list field layouts documented in one place (builder comments ↔ renderer reads)
6. Link `hexfont.spin` only when text shapes are required. Do not start VECTORJET from product `main` until that draw cog exists.

## External references

| Doc | Use |
|-----|-----|
| `pcb/P8X32A-Propeller-Datasheet-v1.4.0_0.pdf` §4.10 | Video generator, WAITVID |
| `docs/Propeller Quick Reference v1.7.pdf` | PASM opcodes |
| `ARCHITECTURE_UX_MODULE.md` | Board cog and pin budget |
| Demo sources | `src/lib_vjet/demo/vjet_test.spin`, `src/lib_vjet/demo/vjet_fb.spin` |
