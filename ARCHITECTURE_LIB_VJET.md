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

`vjet_test.spin` starts three render cogs and one VGA cog. It waits for vertical blank through `vga_status`, then swaps which Hub list is live and rebuilds the other list.

## Resolution and buffers

Rendering constants in `VJET_vUXM_rendering.spin`:

- Width: 256 pixels
- Height: 240 scanlines

The VGA cog repeats each logical line (tile counter) so the analogue timing fills a taller raster. The Hub scan buffer is allocated in the top object as `linebuffers[(WIDTH*8)/4]` longs in the current demos (eight line slots for the active strip).

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

1. Waits until the frame request scanline is 0
2. Reads the current display-list pointer
3. Optionally fixes trapezoids that start above Y0 (top clip)
4. Renders every Nth scanline (`cognum`, `cognum+totalcogs`, …)
5. Writes pixels into the shared scanline buffer for the VGA cog

Init instructions are overlaid by live variables after boot. Do not treat early DAT labels as free code space without reading the reuse comments.

## VGA cog behaviour

`VJET_vUXM_vga.start(pinGroup, lineBuffers, statusLong)`:

- Programs `VCFG` for VGA on the selected pin group
- Starts CTRA in PLL video mode
- Loops active lines with `WAITVID`, then front porch, vertical sync, and back porch
- Publishes phase flags in `statusLong` so Spin can wait for blanking

For the UX Module, demos pass `pinGroup = 16/8` (group 2 → P16–P23), which matches the board VGA connector.

## Integration constraints with UX firmware

| Resource | UX text firmware | VECTORJET demos |
|----------|------------------|-----------------|
| P16–P23 | `hires_text_vga` | `VJET_vUXM_vga` |
| Cogs | ~7 used | 1 VGA + N render + Spin |
| Screen model | Character cells | Scanline framebuffer + display list |

A future combined firmware must define an exclusive video mode. Both engines must not drive the VGA pins at the same time. Cog math must leave room for ACIA, keyboard, and UART if those stay live.

`ux_module.spin` already reserves `PORT_VJET = acia#PORT_C0` as a named alternate ACIA base for experiments. There is no VJET I/O protocol in-tree yet.

## Extension points

Useful work while keeping the architecture intact:

1. Stop text VGA and start VECTORJET from a mode switch in `ux_module`
2. Drive the display list from Z80 I/O at `PORT_VJET` (needs a command protocol)
3. Tune render cog count against available cogs and fill rate
4. Keep display-list field layouts documented in one place (builder comments ↔ renderer reads)

## External references

| Doc | Use |
|-----|-----|
| `pcb/P8X32A-Propeller-Datasheet-v1.4.0_0.pdf` §4.10 | Video generator, WAITVID |
| `docs/Propeller Quick Reference v1.7.pdf` | PASM opcodes |
| `ARCHITECTURE_UX_MODULE.md` | Board cog and pin budget |
| Demo sources | `vjet_test.spin`, `graphtest.spin` |
