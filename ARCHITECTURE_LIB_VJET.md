# Architecture — VECTORJET (`lib_vjet`)

This note describes the 2D/3D scanline engine under `src/lib_vjet`.  
Agent edit rules: `.agents/skills/library-vjet`, `hw-propeller`, `lang-pasm`.  
Prose style: `.agents/skills/style-ste-writing`.

## Purpose

VECTORJET builds a display list in Spin, renders scanlines with one or more PASM cogs, and outputs VGA with a dedicated PASM cog. The UXM-prefixed files are a specialisation for the RC2014 UX Module pinout and clock. Upstream credit in the sources: IRQsome Software, with VGA lineage from Kwabena W. Agyeman / Parallax-style video generators.

The 2020 and 2021 objects keep the IRQsome mark. A new file uses (C)2026 feilipu. A file derived from an IRQsome object states that source and uses 2026. `hexfont.spin` is the Aaron Amar font.

The product top `ux_module.spin` links this library. Boot is the text console. A good sealed list starts graphics. The library objects stay in `src/lib_vjet/`. Compile tops and the beam-chase head are in `src/lib_vjet/demo/`. Display lists are in `src/lib_vjet/scene/`. The beam-chase demo is `src/lib_vjet/demo/vjet_test.spin`. Compile a demo with `-L src -L src/lib_vjet`. The framebuffer sources were removed. Git history keeps them.

## Files

| File | Layer |
|------|-------|
| `VJET_v01_displaylist.spin` | Spin API: clip, shapes, text, list packing |
| `VJET_vUXM_rendering.spin` | PASM renderer cog program |
| `VJET_vUXM_vga.spin` | PASM VGA output cog |
| `hexfont.spin` | Font blob for text shapes |
| `demo/head_slice.spin` | Beam-chase head. A top includes it. Not a compile top. |
| `scene/scene_triangles.spin` | Spinning triangles. Beam-chase head. |
| `scene/scene_graph.spin` | Graph picture. Beam-chase head only. |
| `scene/scene_probe.spin` | Orbit probe. Beam-chase head. |
| `scene/scene_cube.spin` | Cube mesh. The head does not include it. |
| `scene/scene_card.spin` | Test card. Beam-chase head. Polygons. |
| `scene/scene_stress.spin` | Stress picture. Polygons, scaled text, clip, stacked spans. |
| `demo/vjet_test.spin` | Original demo. Beam chase. Spinning triangles. |
| `demo/vjet_acia.spin` | Beam-chase triangles plus the ACIA cog. |
| `demo/vjet_ftdi.spin` | Beam-chase triangles plus the ACIA cog and the FTDI cog. |
| `demo/vjet_probe.spin` | Beam-chase orbit probe. |
| `demo/vjet_spin.spin` | Beam-chase triangles plus one extra Spin cog. The picture tears. |
| `demo/graphtest.spin` | Graph drawing sample. |
| `demo/vjet_card.spin` | Beam-chase test card. |
| `demo/vjet_stress.spin` | Beam-chase stress picture. |

## Runtime pipeline

The product top has two picture sources. A sealed list from the host replaces the local test card. With no sealed list, the draw cog builds `scene/scene_card.spin`.

```
Host console ($1C, length, payload)
        |
        v
Cog 0 stores the payload in the idle list
        |
        | good chain
        v
Draw cog publishes that list on the front porch
        |
        +-------> Render cog 0 --+
        +-------> Render cog 1 --+--> eight line slots (Hub)
        +-------> Render cog 2 --+
                                 |
                                 v
                           VGA cog (WAITVID)
                                 |
                                 v
                           pins P16–P23 (group 2)
```

`demo/vjet_test.spin` has no host list. Cog 0 builds one list and then builds the other. It starts three render cogs and one VGA cog. It waits for the front porch through `vga_status`, publishes the finished list, and lets the render cogs copy that pointer at the next line 0.

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

The VGA cog repeats each logical line so the analogue timing fills a taller raster. The Hub scan buffer is eight line slots, 2048 bytes.

The product top keeps two lists of 1149 longs. Each list is 4596 bytes. The text screen is the first 3200 bytes of list A. List B stays next to list A.

`demo/head_slice.spin` sets the demo list size. Triangles use 900 longs. The graph and the stress picture use 500. The card uses 400. The orbit probe uses 160.

The removed framebuffer tops used two lists of 300 longs. That record is in the next section.

## Framebuffer

The framebuffer sources were removed. Git history keeps them. This section is the record. The user accepted that picture on 17 Oct 2026. The demo was `demo/vjet_fb.spin`. The VGA cog scans a finished 256 by 80 bitmap. Two bits select one of four colours in each group of 16 pixels. The renderer stores lines 0, 3, 6, and so on. The VGA cog shows each stored line six times.

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

The live bring-up uses that slice. The framebuffer demo was removed.

## Hub-paint and tear — 20 Oct 2026

The live picture paints Hub slots in place. The tear bands from the earlier loads are gone. The handoff is in `3D_PROCESS_LIB_VJET.md`. The shell steps are in `3D_WORKPLAN_LIB_VJET.md`.

The 27 Oct 2026 compile is 17284 bytes. It is not in EEPROM. The font table is at 16820. The lists are at 17364 and 21960. Each list is 4596 bytes. A sealed list replaces the test card. A text-mode list is stored at `dlist1`. The copy does not add a Hub base.

EEPROM still holds the 20 Oct clean point until the next load. That image is 17700 bytes. The font table is at 17236. The lists are at 17752 and 19752. Each of those lists is 2000 bytes. A host program must use the pair that matches the image in the chip.

The text painter clamps glyph writes to the slot. `:linewait` restarts a frame only after a non-zero published line. `restoreText` waits 250 ms after VECTORJET stops. Pace, a Hub edge cache, a cog-RAM `linebuf`, and a Hub scratch copy all failed. Those loads also broke keys, doubled line feeds, or blocked the return to text. The process file lists each load. Do not restore them.

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

`enterGraphics` stops text VGA, DDC, and the input that did not request graphics. It then starts the slice VGA cog, three render cogs, and the draw cog. `restoreText` stops VECTORJET, then starts text VGA and DDC. After `cogstop`, those cogs leave the pins.

Graphics runs one input cog. Control-G keeps the FTDI cog. The PS/2 chord keeps the keyboard cog. A shared keyboard and FTDI driver is not in the tree. Detail is in `ARCHITECTURE_UX_MODULE.md`.

Cog 0 stays on the ACIA pump. Cog 0 is the only `acia.tx` writer. The draw cog builds the test card, or it publishes a sealed list. `vjet_test` blocks Cog 0 in the draw loop. That demo has no ACIA pump.

The product split is:

1. **Text mode.** The Z80 console is on VGA text. Boot stays in this mode.
2. **Graphics mode.** A good sealed list, `$07`, FTDI Control-G, or Ctrl+Alt+G starts it. The request input stays. This mode uses all eight cogs.
3. **Standalone demo.** `vjet_test` and `graphtest` have no ACIA. Cog 0 is the draw loop.

`PORT_VJET` stays a reserved base at `acia#PORT_C0`. The sealed list uses the text console.

Hub cost for the product picture is the scan buffer and the two lists. Eight line slots are 2048 bytes. The two lists are 9192 bytes. The text screen sits inside list A.

## Frames

Three programs make one picture. The plan names are cook, send, and show. This note uses the work each program does.

```
STL or OBJ
    |
    v
Author the list          tools/vjet_cook.py writes one .vjb blob
    |
    v
Transfer the list        the host adds the Hub address and writes $1C
    |
    v
Present the list         Cog 0 stores the payload. The porch publishes it.
    |
    v
Render cogs and VGA cog  the published list stays until the next porch
```

A program does its own work. The author does not open the ACIA. The host does not build a slope. The Propeller does not read STL or OBJ.

### Author the list

`tools/vjet_cook.py` writes one sealed display list from an STL file or an OBJ file. Python 3 and the standard library are enough. The script runs on macOS, Linux, and Windows.

The view is orthographic. Model Y points up. Screen Y points down. Low Z is drawn first. The script does not weld vertices.

The file suffix is `.vjb`. One command writes one picture. `--asm` writes `DEFB` and `DEFW`. `--inc` writes a binary include of the `--out` file.

The blob is little-endian.

| Field | Bytes | Meaning |
|-------|------:|---------|
| Payload length | 2 | Display-list bytes. This length skips the header. |
| Reloc count | 2 | Words the host must fix. |
| Font hub | 2 | Font address. Zero when the list has no text. |
| Payload | N | The display list. A link is an offset into this payload. |
| Reloc offsets | 2 each | Byte offset of one word in the payload. |

The last link stays 0. A text shape stores the font hub as an absolute word. A string pointer is an offset when the string sits in the payload.

The script refuses a chain it cannot walk. A coordinate that is not finite is an error. The script refuses a payload above 2000 bytes. Each product list holds 4596 bytes. Keep the script limit until a larger payload is tested.

Pass `--font 16820` for the 17284-byte compile. EEPROM still uses 17236 until the next load. A list with no text stores font 0. The font argument is then unused.

```sh
python3 tools/vjet_cook.py --check
python3 tools/vjet_cook.py --stl tools/vjet/triangle.stl --colour FFFF --font 16820 --out triangle.vjb
python3 tools/vjet_cook.py --obj tools/vjet/square.obj --colour C0C0 --font 16820 --asm square.asm
```

### Transfer the list

The host library is `vjet` in z88dk-libraries. One C89 source builds the 8085 library and the Z80 library.

`vjet_send_list(blob, dest, size)` adds `dest` to each reloc word. It then writes `$1C`, the payload length, and the payload. A bad link returns before the first byte. `size` is the full blob length.

`dest` is the Hub address of `dlist1` or `dlist2`. The same payload can fill either list. The first picture uses `dlist1`.

On the 6850 path, `$FF` uses BDOS function 2. Every other byte uses function 6. Function 2 expands TAB `$09`. A list can contain `$09`. Those bytes use function 6.

`vjet_graphics` writes one `$07`. A good list already starts graphics. A `$07` in the next 250 ms is not a return to text. A later `$07` returns to text. Pictures after the first do not write `$07`.

`vjet_load` reads one CP/M file into RAM. A file above the buffer returns -1. `vjet_font` sets the image font. A font of 0 skips the check.

| Image | Where it runs | Font | List A | List B | List bytes |
|-------|---------------|-----:|-------:|-------:|-----------:|
| 17284-byte compile | not in EEPROM | 16820 | 17364 | 21960 | 4596 |
| 17700-byte clean point | EEPROM until the next load | 17236 | 17752 | 19752 | 2000 |

A host program must use the row for the image in the chip. `G:SPINTRI`, `G:ORBIT`, `G:TVTEST`, `G:STRESS`, and `G:TESTART` use the 17700-byte row.

### Present the list

`src/ux_module.spin` stores the list and the porch shows it. Cog 0 reads the ACIA ring. The mark is `$1C`. The next word is the payload length. Cog 0 copies that many bytes into the idle list.

The copy stores the bytes as they arrive. The host has already fixed the reloc words. A count of 0 is ignored. The parser discards a count above 4596 bytes. It leaves that payload off the screen.

`listChainOk` walks the links. The sync byte must be `$FF`. A box is at least 16 bytes. Text is at least 20 bytes. A trap stack is at least 36 bytes. The trap heights cover the shape.

The walk stops at 250 shapes. The porch leaves a bad chain unpublished. Text mode then draws the banner again. The list and the console share Hub.

A good chain sets `listReady`. In text mode that call starts graphics. The draw cog publishes the list on the front porch. The local test card stops. Three render cogs scan the published list on every frame.

Text mode stores the list at `dlist1`. Graphics stores the list that `dlist_ptr` does not name. A return to text uses `dlist1` again when no list is waiting.

`gfx_flag` stays clear, so the pair stays a 6850. Control-G on FTDI and Ctrl+Alt+G use the same switch. A `$07` with no list shows the test card. The title on that card is `UX Module`.

### A stream of pictures

A game sends one sealed list for each new picture. The previous picture stays on the screen until the porch publishes the next list. The VGA frame is about 60 Hz. The picture changes when a full list arrives.

```
picture N                         picture N+1
    |                                 |
    v                                 v
author one sealed list            author one sealed list
    |                                 |
    v                                 v
transfer into the idle list       transfer into the idle list
    |                                 |
    v                                 v
porch publishes that list         porch publishes that list
    |
    +---- the render cogs keep the published list on every frame
```

1. Author the first list. For the 17284-byte compile, pass font 16820.
2. Load the program and the `.vjb` file with XMODEM. The console stays a 6850 during that transfer.
3. Call `vjet_send_list` with the address of `dlist1`.
4. Wait until the porch shows that list. The test card stops after that publish.
5. Author or select the next pose.
6. Call `vjet_send_list` with the address of `dlist2`. The reloc words must name `dlist2`.
7. On the next front porch the draw cog publishes `dlist2`. `dlist1` is then free.
8. Alternate the two addresses. Send the next list only after the previous publish.
9. Write one `$07` to return to text. The next list uses `dlist1` again.

Cog 0 copies 16 bytes while the blanking bit is set. On a visible line it copies 2 bytes and then waits 1 ms. The copy writes the idle list. The render cogs keep the published list, so the shown picture stays whole during the transfer.

Text mode discards a second `$1C` that arrives before the publish. In graphics that mark waits at most 250 ms. A gap of 250 ms with no list byte returns the parser toward idle. Text mode draws the banner again when the abandoned state was the payload.

One list of 2000 bytes holds 55 flat triangles, 41 general triangles, or 125 boxes. One list of 4596 bytes holds 127 flat triangles, 95 general triangles, or 287 boxes. The author stops at 2000 bytes. A flat triangle is 36 bytes. A general triangle is 48 bytes. A box is 16 bytes. A text shape is 20 bytes.

The 8085 sends bytes that are already a sealed list. A mesh that stays in 8085 RAM, and a screen record that the draw cog slopes, are later work in `3D_WORKPLAN_LIB_VJET.md`.

## Extension points

Useful work while keeping the architecture intact:

1. The draw cog is in `src/ux_module.spin`. The live picture is the eight-line scan. The plan is `3D_WORKPLAN_LIB_VJET.md`. The repair record is `3D_PROCESS_LIB_VJET.md`.
2. The product lists hold the test card. Each list is 1149 longs. The text screen is the first 3200 bytes of list A. Do not restore the framebuffer bitmap.
3. A command port at `PORT_VJET` is still open. The console path in Frames already stores a sealed list.
4. Tune render cog count against available cogs and fill rate
5. Keep display-list field layouts documented in one place (builder comments ↔ renderer reads)
6. Link `hexfont.spin` only when text shapes are required. The product `main` keeps the `font.get` call so the font stays in the image.

## External references

| Doc | Use |
|-----|-----|
| `pcb/P8X32A-Propeller-Datasheet-v1.4.0_0.pdf` §4.10 | Video generator, WAITVID |
| `docs/Propeller Quick Reference v1.7.pdf` | PASM opcodes |
| `ARCHITECTURE_UX_MODULE.md` | Board cog and pin budget |
| Demo sources | `src/lib_vjet/demo/vjet_test.spin` |
