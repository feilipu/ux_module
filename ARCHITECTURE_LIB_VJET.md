# Architecture — VECTORJET (`lib_vjet`)

This note describes the 2D/3D scanline engine under `src/lib_vjet`.  
Agent edit rules: `.agents/skills/library-vjet`, `hw-propeller`, `lang-pasm`.  
Prose style: `.agents/skills/style-ste-writing`.

## Purpose

VECTORJET builds a display list in Spin, renders scanlines with one or more PASM cogs, and outputs VGA with a dedicated PASM cog. The UXM-prefixed files are a specialisation for the RC2014 UX Module pinout and clock. Upstream credit in the sources: IRQsome Software, with VGA lineage from Kwabena W. Agyeman / Parallax-style video generators.

The library is **not** linked from `ux_module.spin` today. Demos use their own top objects (`vjet_test.spin`, `graphtest.spin`).

## Files

| File | Layer |
|------|-------|
| `VJET_v01_displaylist.spin` | Spin API: clip, shapes, text, list packing |
| `VJET_vUXM_rendering.spin` | PASM renderer cog program |
| `VJET_vUXM_vga.spin` | PASM VGA output cog |
| `hexfont.spin` | Font blob for text shapes |
| `vjet_test.spin` | Demo: spinning triangles + centred text |
| `graphtest.spin` | Demo: graph-style drawing |

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

`vjet_test.spin` starts three render cogs and one VGA cog. It waits for vertical blank through `vga_status`, publishes the completed list, waits for vsync so the render cogs copy the pointer, then rebuilds the other list.

## Scanline handshake (tear / flicker)

The Hub scan buffer holds **eight** logical lines (`LINE_BUFFERS`). The VGA cog displays line `N` from slot `N & 7` and writes `N` into `vga_status`. During blanking it writes line **240** plus phase bits.

Render cogs:

1. Wait until the status line is `>= 240` (blanking).
2. Fill slots 0..7 while they treat the raster as line 0.
3. Then wait until they are fewer than eight lines ahead of the live VGA line.

Do not publish line 0 during vsync or back porch. The old status longs used a low word of 0. Render cogs treated that as scanline 0, ran 16 lines, and overwrote the first eight slots before active video. A faster system clock (118 MHz vs 80 MHz) made that overrun worse.

Spin must publish `dlist_ptr` at front porch, then wait for vsync bit 17 (`$02_00_00`) before it rebuilds the other list. If Spin rebuilds a list that a render cog still reads, the frame tears.

## Video PLL

`VJET_vUXM_vga` sets CTRA PLL internal, VCO/2. The NCO target is 5 MHz. VCO is 80 MHz (spec 64–128 MHz). PLLA is 40 MHz. VSCL uses 4 clocks per pixel, so the pixel rate is 10 MHz (256-wide VGA).

The old 10 MHz NCO with VCO/4 made VCO 160 MHz. That is out of spec and the PLL can unlock (jitter, tear, roll).

`hires_text_vga` uses a different PLL setup (`pr` in MHz, VCO/2) for 640×480 text. Do not copy VECTORJET FRQA into the text driver or the reverse.

## Resolution and buffers

Rendering constants in `VJET_vUXM_rendering.spin`:

- Width: 256 pixels
- Height: 240 scanlines

The VGA cog repeats each logical line (tile counter) so the analogue timing fills a taller raster. The Hub scan buffer is `linebuffers[(WIDTH*LINE_BUFFERS)/4]` longs (eight line slots).

Display lists are ordinary Hub longs (for example `dlist1[900]`, `dlist2[900]`). Size is a demo choice, not a hardware limit.

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
- Writes line 240 during front porch, vsync, and back porch (never line 0)

For the UX Module, demos pass `pinGroup = 16/8` (group 2 → P16–P23), which matches the board VGA connector.

## Integration with UX firmware (exclusive video mode)

Pins P16–P23 have one owner. `hires_text_vga` (two cogs, 640×480 cells) and `VJET_vUXM_vga` (one cog, 256×240 scanlines) must not run at the same time.

| Mode | VGA cogs | Other cogs that stay | Free for VECTORJET |
|------|----------|----------------------|--------------------|
| Text (today) | 2 (`hires_text_vga`) | Spin, FTDI, ACIA, PS/2 (4) | none (2 spare) |
| Graphics | 1 (`VJET_vUXM_vga`) | Spin, FTDI, ACIA, PS/2 (4) | 3 (render, or 2 render + 1 Spin draw) |

`wmf.stop` stops the text pair. `vga.stop` (VECTORJET) and `render.stop` stop graphics. After `cogstop`, those cogs leave the pins. Then start the other driver.

Do **not** build the display list on Cog 0 if the ACIA pump must stay live. Cog 0 is the only `acia.tx` writer. `vjet_test` blocks Cog 0 in `Vblank` + `draw`. That starves keyboard, FTDI, and Z80 I/O.

Recommended product split:

1. **Text mode** — current `ux_module` path. Z80 console on VGA text.
2. **Graphics mode** — stop text VGA. Start VECTORJET VGA + two render cogs. Start a **second Spin cog** that waits for blanking and builds lists. Cog 0 only pumps ACIA / keyboard / FTDI and writes a small mailbox (camera, mode, flip). That uses all eight cogs: 4 I/O + 1 draw + 1 VGA + 2 render.
3. **Standalone demo** — `vjet_test` / `graphtest` as now (no ACIA). Three render cogs on Cog 0 as the draw loop.

Hooks in `ux_module.spin` (boot stays in text mode):

1. `enterGraphics` sets `videoMode`, calls `wmf.stop`, starts VECTORJET VGA plus two render cogs, publishes an empty list.
2. `enterText` stops VECTORJET and calls `screenInit`.
3. `inGraphics` is the mode flag for `readZ80` (`textOut` is a no-op in graphics).
4. Mailbox: `vjetStatus`, `vjetDlistPtr`, `vjetReady`. Cog 0 writes the pointer and ready flag at the switch. A later draw cog may own the lists.

Do not call `enterGraphics` from `main` until that draw cog exists. Serial tests use the text boot path.

Hub cost: eight line slots are 2 KB. Two lists of 900 longs are about 7 KB. The text screen is 80×40 bytes plus colours. 32 KB Hub cannot keep a large text buffer and two fat lists at once. Reuse the text screen region for lists when you leave text mode.

`PORT_VJET = acia#PORT_C0` is reserved for a later Z80 command port. There is no I/O protocol in-tree yet. A first protocol can be: command byte, then words that Spin copies into the back list, then a flip at vblank.

## Extension points

Useful work while keeping the architecture intact:

1. Start a Spin draw cog from `enterGraphics` (not Cog 0)
2. Drive the back list from Z80 I/O at `PORT_VJET` (needs a command protocol)
3. Tune render cog count against available cogs and fill rate
4. Keep display-list field layouts documented in one place (builder comments ↔ renderer reads)

## External references

| Doc | Use |
|-----|-----|
| `pcb/P8X32A-Propeller-Datasheet-v1.4.0_0.pdf` §4.10 | Video generator, WAITVID |
| `docs/Propeller Quick Reference v1.7.pdf` | PASM opcodes |
| `ARCHITECTURE_UX_MODULE.md` | Board cog and pin budget |
| Demo sources | `vjet_test.spin`, `graphtest.spin` |
