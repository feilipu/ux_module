# 3D implementation process — lib_vjet

This file records the repairs from 11 Sep 2026 through 17 Oct 2026. The forward plan is `3D_WORKPLAN_LIB_VJET.md`.

Compile tops now live in `src/lib_vjet/demo/`. Display lists live in `src/lib_vjet/scene/`. Names in this record are the files from those dates.

The beam-chase bring-up did not hold a stable picture. The framebuffer demo did. That file is now `demo/vjet_fb.spin`. The user accepted that picture on 17 Oct 2026.

## What failed on 11 Sep 2026

EEPROM held a standalone `vjet_test` image from git `b272914` (16 Apr 2021). The picture locked. The monitor reported 720×480. That image is the old PLL and three render cogs. It is not the integration test.

The same day, a hot switch from text mode smeared, then went grey. Graphics integration stopped. The product firmware returned to text only.

A parked top from that day sits outside git. It is a note of the attempt. It is not the file to load. These points matter:

- The switch order was `wmf.stop`, `i2c.stopCog`, a 250 ms blank, then VECTORJET VGA and two render cogs.
- The draw cog used one 900-long list and rebuilt it in place. Two shorter lists aborted the scene. A single list tears if a render cog still reads it.
- The first host `>` requested graphics. A CP/M prompt contains `>`. That trigger is unsafe.
- The parked file still linked the product objects. The picture failed with the in-tree switch, not only as a standalone demo.

## Cold load, 16 Oct 2026

The in-tree `vjet_test` image was loaded into RAM on the FTDI port. The loader reported 117964800 Hz and mode byte $6F.

The first picture tore. The left side alternated white and light pink. That colour is the background triangle `$ECEC`. The monitor menu read 1920×1080. A 5 MHz NCO with VCO/2 does not lock on this monitor.

The second RAM load used the demo PLL. The NCO is 10 MHz and CTRA uses VCO/4. The image was 6216 bytes. That load locked at 720×480 at 60 Hz and tore. The tear followed a later scanline handshake.

The third load restored the 2021 handshake on the same PLL. The monitor read 720×480 at 60 Hz. The triangles and the text stayed whole. The reference photo is `docs/vjet_demo_720x480.jpg`.

The bring-up then used that handshake, two lists of 300 longs, and Control-G on the FTDI console. The text picture locked at 640×480. The monitor read 66 Hz. The active text table calculates to about 70 Hz.

Control-G then left a black picture. The monitor stayed locked. That image stored `$8080` in `dlist_ptr` and set the ready flag before the draw cog started. The first publish was an empty list. Cog 0 then built the first list before the ready flag. The list was valid. The serial line reported `GFX 00 01FF4CD4 00F1FF10 00000000`. The abort code was 00. The field stayed black.

The render cogs never left their ready wait. `cognew` stores bits 15:2 of the parameter address. `gfxReady` was a byte, so the cogs watched a different byte and that byte stayed 0. `gfxReady` is now a long.

The long `gfxReady` image used two render cogs. It showed the spinning triangles. The picture locked for part of the time, then tore.

Three render cogs tore more than two. The file was 19500 bytes.

`vjet_test` on this board clock, with no ACIA cog and no FTDI cog, was 6140 bytes. The user reported a clean spinning-triangle picture. `vjet_acia.spin` added the ACIA cog and stayed clean at 7532 bytes. `vjet_ftdi.spin` added the FTDI cog and stayed clean at 8660 bytes.

`vjet_spin.spin` added one Spin cog that only reads `framecount`. The file was 8684 bytes. That second Spin cog tore the picture. Lock lasted about half a second.

The bring-up with the draw loop on Cog 0 was 19492 bytes. Triangles showed about half the time. Then the signal stopped. Cog 0 had 2264 bytes free. The draw overran that space.

The next image parked Cog 0 on `waitcnt`. The draw cog used the 800-long text buffer as its stack. The file was 19564 bytes. The signal stayed. About 2 seconds locked, then about 4 seconds torn.

The VGA cog then read the next pixel group during the current group. The file was 19580 bytes. The locked part grew to about 60 percent. It still tore hard for several seconds.

Cog order changed the locked share. Render cogs on 3, 4, and 5 with the ACIA cog on 6 scored about 20 percent. Render cogs on 3, 5, and 7 with the draw cog on 4 scored about 10 percent. That 19552-byte image was the worst bring-up picture. The signal stayed. A wider cog gap is not a repair.

## Handoff count — 17 Oct 2026

The clean demo and the torn bring-up shared `VJET_vUXM_vga.spin` and `VJET_vUXM_rendering.spin`.

The system clock is 117964800 Hz. FRQA is 364088889. The NCO is 10000000.003 Hz. CTRA selects VCO/4, so PLLA is 40000000.012 Hz. VCO is 160000000 Hz. That VCO is outside the 64–128 MHz range. A 5 MHz NCO did not lock, so this VCO stayed.

`visibleScale` is `(4 << 12) + 16`. One visible `WAITVID` is 16 PLL clocks. The line holds 64 groups. That is 1024 PLL clocks and 256 pixels. Horizontal sync is 256 PLL clocks. Every physical line is 1280 PLL clocks. A blank line is also 1280.

The VGA cog shows each logical line twice. 240 logical lines make 480 active lines. The front porch is 11 lines. Vertical sync is 2. The back porch is 31. The total is 524 physical lines. The line rate is 31250 Hz. The frame rate is 59.637 Hz. The monitor reports 720×480 at 60 Hz.

One PLL clock is 2.94912 system clocks. The shifter runs for 16 PLL clocks after `WAITVID`. That is 47.19 system clocks. A 16-PLL window holds at most 11 instructions of 4 clocks.

Three render cogs step by the logical index. The allowance before the VGA cog reads the line is 15099 system clocks. A clear plus seven full spans can pass that allowance. The clean demo still draws the wide fan. The bring-up does not.

The Hub window is every 16 clocks for each cog. A busy Spin cog does not add clocks to a render `wrlong`. Neighbour cog IDs sit 2 clocks apart.

### Pictures that stayed locked

| Image | Spin | Cog map | File |
|-------|------|---------|------|
| `vjet_test` | Cog 0 draws | VGA 1. Render 2, 3, 4. | 6140 |
| `vjet_acia` | Cog 0 draws | That set, plus the ACIA cog. | 7532 |
| `vjet_ftdi` | Cog 0 draws | VGA 2. Render 3, 4, 5. ACIA 6. FTDI is cog 1. | 8660 |

### Pictures that tore

| Image | What changed | Result |
|-------|----------------|--------|
| `vjet_spin` | One extra Spin cog. Render stays on 3, 4, and 5. | Tear. Lock for about half a second. 8684 bytes. |
| Bring-up, draw on Cog 0 | 2264 bytes free on Cog 0. | Triangles, then no signal. |
| Draw on the text buffer. Render 3, 5, 6. | 19564 bytes. | About 50 percent locked. |
| Same, plus the VGA prefetch | 19580 bytes. | About 60 percent locked. |
| Render 3, 4, 5. ACIA on cog 6. | 19568 bytes. | About 20 percent locked. |
| Render 3, 5, 7. Draw on cog 4. | 19552 bytes. | About 10 percent locked. |

`vjet_ftdi` is clean. `vjet_spin` is the smallest change that tears it. The bring-up always runs two Spin cogs. At the front porch the draw loop stores `dlist_ptr`, then `gl.start` writes `$8080` into the other list. A render cog that is still in the old list takes the broken link. `sync_timeout` of 5000 can burn about 10 to 20 logical lines.

These edits did not repair the beam chase. Do not repeat them.

- Leave the PLL, `visibleScale`, and the porch lengths on the beam-chase files.
- Leave line 0 on vertical sync and on the back porch.
- Do not draw on Cog 0 in the bring-up. About 2 KB is free there. The signal stopped.
- Do not add a fourth render cog.
- Do not spread the render cogs. The even spread is the 10 percent picture.
- Do not stop the ACIA cog. The 8085 then sticks on `/WAIT`.
- Do not start VECTORJET from `src/ux_module.spin` until stage 1 has an exit.
- Two 900-long lists do not fit.

## Frame buffer repairs

The beam chase shares one deadline with the render cogs. The framebuffer does not. The VGA cog scans a finished bitmap. A late frame repeats.

The first store was 128 by 240, two bits per pixel, one colour long per line. The program was 6912 bytes. The picture locked. A fifth colour on a line was drawn as colour 0, so a narrow triangle painted the rest of the line.

Three render cogs each ran the top fixup. One cog wrote the Y 0 edges over edges another cog had walked. Cog 0 now runs that fixup alone and writes `fixup` at control offset 24. The other cogs wait. A later line does not give up. A dedicated `fixup_ptr` exceeded the PASM origin `$1F0`. The address stays `ctrl_base+24`.

Four colour longs on every line, with one display list, was 6964 bytes and about 850 bytes of stack. The monitor showed no triangles. Do not load that image.

The 120-line store, eight colour longs per line, stopped the full-width streaks. The program was 6964 bytes. About 7156 bytes remained for the stack. Crossings still lost a fifth colour inside a group.

The packer then kept four colours for each group of 8 pixels. A fifth colour used the nearest of the four. The store was 80 lines. The first 7012-byte load stayed black. `find_color` patched the source field with `movs`, so every palette byte stayed 0. `movd` patches the destination field. The user then confirmed that colours and shapes were clean. Vertical steps were six screen lines.

The 256-wide store uses 4 PLL clocks per pixel. FrameClocks stays 16. Each colour long covers 16 pixels. The program was 6900 bytes. The two bitmaps and the two palette tables use 20480 bytes. About 2100 bytes remained for the stack. A copy of that binary is `/tmp/vjet_fb_6900.binary`.

### Stripes

The 6900-byte picture used one colour byte on every screen line. The 2021 demo uses two bytes. An even logical line uses the low byte. An odd logical line uses the high byte. The VGA cog shows each logical line twice, so the screen pattern is two bright lines, then two dark lines.

The framebuffer stores every third logical line and shows it six times. Six repeats of one byte would make a band of six lines. The accepted rule does not do that.

Bit 0 of the stored colour byte means the dark lines are $55 lower. The VGA cog ORs $03, so bits 1 and 0 are not a visible colour. The packer sets the bit when the high byte is the low byte minus $55, and the low byte is at least $55. The colours `$0055`, `$55AA`, and `$AAFF` stripe. Equal bytes stay solid.

Even stored lines show bright, bright, dark, dark, bright, bright. Odd stored lines show the inverse. Across two stored lines the pattern is bright, bright, dark, dark, repeated. The program is 8044 bytes. About 944 bytes remain for the stack. The user accepted this picture on 17 Oct 2026.

`VJET_vUXM_vga.spin` and `VJET_vUXM_rendering.spin` stay on the 2021 path. The framebuffer cogs are `VJET_vUXM_vga_fb.spin` and `VJET_vUXM_rendering_fb.spin`. The demo of that picture is `demo/vjet_fb.spin`.

## Probe — 17 Oct 2026

`vjet_fb_probe.spin` uses those framebuffer cogs and a new scene. The program is 6676 bytes. The stripe rule is unchanged.

The scene has a horizontal mover, a vertical mover, a diagonal mover, a crossing pair, and four triangles on a shallow ellipse. Far triangles are drawn first. EEPROM holds this image so the rule can be watched while the triangles move. `demo/vjet_fb.spin` stays the accepted scene. `build/vjet_fb.binary` is that image.

The bring-up `ux_module_vjet.spin` still links the beam-chase objects. It compiles to 19552 bytes with 2200 bytes free. It was not loaded for this probe.

## Glass load — 17 Oct 2026

The probe set `blend` and gave bit 1 to five colours. The picture froze. It was a full frame of red and pale bands. No triangle moved.

A solid span of six pixels or fewer drew, then entered the mix loop. The loop count was already 0. `djnz` then walked every Hub byte. The VGA cog kept the last bytes it could scan.

The solid span now reaches the return. The mix loop sits after that return and jumps back when it finishes. `demo/vjet_fb.spin` still leaves `blend` clear.

The repaired probe showed the triangles in motion. Black under a semi-transparent red became yellow. The mix shifted the whole colour byte. Red bits moved into green. The mix now averages bits 7:6, bits 5:4, and bits 3:2 as separate pairs. That program is 6696 bytes.

The accepted picture now lives in `src/lib_vjet/demo/vjet_fb.spin`, beside `demo/vjet_test.spin`. Those two files are the demos. The framebuffer cogs stay the solution.

The accepted scene draws 13 triangles and one text shape. The probe draws one box and nine triangles. A full accepted frame stores up to 632 bytes. The probe stores 340 bytes. Those sizes are in `3D_WORKPLAN_LIB_VJET.md`.

## Line slice — 18 Oct 2026

The short framebuffer bring-up is on the board. Ten content lines fill the top band. The black line fills the rest. The prompt loop from the long graphics session ended after a hardware reset. Control-Option-G still toggles.

The bitmap holds the pixels. The list holds the commands. The list stays allocated. The 80-line pair is 20480 bytes. The bring-up cannot keep that pair.

The next trial returns to the eight-line slice. The earlier beam-chase tears used the wide fan and a second Spin cog. This trial keeps three render cogs and the short scene. The original renderer used two cogs. Do not change the 2021 handshake, the PLL, or `visibleScale`.

The 18 Oct 2026 load is 18304 bytes. 4824 bytes remain above the stack. EEPROM holds that image. Control-Option-G shows a full blue field, the text GFX, and two spinning triangles. The triangles sit in the top half. The blue field is the box `$1818` on all 240 logical lines. The triangles are drawn near logical line 80. The user did not report a tear. The accepted framebuffer demo is unchanged.

The same slice then ran the orbit probe. That scene is one box, four triangles on a shallow ellipse, and five moving triangles. Far orbit triangles are drawn first. The user confirmed that this picture holds.

The list holds 340 bytes. Each bring-up list is 160 longs. The program is 18588 bytes. 3708 bytes remain above the stack. The beam-chase renderer has no 50 percent mix. A later triangle covers an earlier one.

The lead change is on EEPROM. The program is 18668 bytes. 3372 bytes remain above the stack. Each render cog starts the next line after the beam passes that slot. With three cogs the lead is 7 logical lines. The previous wait kept a lead of about 5 lines. The PLL, the 2021 handshake, and visibleScale stay the same.

A return to text sends the line Text mode on FTDI. The VGA banner does not go out on FTDI. The draw stack is 192 longs. Those longs sit in front of the FTDI ring indexes. healRings masks an index that is outside the ring.

The edge tear is not yet confirmed. Watch a triangle that meets the screen edge.

The input split is on EEPROM. The program is 18828 bytes. 3208 bytes remain above the stack. Clock and mode are unchanged.

Control-G keeps the FTDI cog and stops the PS/2 cog. A second Control-G returns to text and sends the line Text mode. The PS/2 chord keeps the keyboard cog and stops the FTDI cog. That arm was not tested. There is no keyboard on the bench.

## Independent edges — 18 Oct 2026

The dark full-width lines were the black clear. A render cog cleared its slot, then waited on the previous cog. That wait could run for about 15 logical lines. The lead is 7 logical lines. The cog then painted the stored edges and wrote them back. The next cog missed the same byte.

The picture showed dark rules, broken triangles, and offset copies. Each cog owns every third line. It reads the initial edges and the slopes. A saturating multiply of 16 adds replaces the line-by-line add. The result matches repeated ADDS, including values that reach the 32-bit rails. The cog does not wait on the sync byte.

It does not write the edges back. The top fixup still runs. The scanline path does not read those edges. The line wait, the PLL, and visibleScale stay the same. Three render cogs stay.

The program is 18848 bytes. 3188 bytes remain above the stack. Clock is 117964800 Hz. The mode byte is $6F. EEPROM held that image before the span records.

## Scan line time — 18 Oct 2026

The photos show fewer torn lines after the independent edges. Flickered lines and repeated lines remain. Pixel samples of both photos give the cause.

A solid red triangle keeps one colour through its body. The body stays red from its upper lines to its base. Those lines finish before the beam reads the slot.

The lead is 7 logical lines. Each logical line is two physical lines, about 7550 system clocks. Seven lines are about 52800 system clocks. The box and the triangles on one line use a small part of that lead. The long fill locks to the Hub window. Each later long write takes 16 clocks.

The flickered lines are the two colour bytes. An even logical line uses one byte. The next logical line uses the other byte. The VGA cog shows each logical line on two physical lines. $0055, $55AA, $66BB, $AAFF, and $80C0 therefore alternate by pairs. $C0C0, $7474, $4848, and $F0F2 use two equal bytes and stay steady.

The repeated lines are the same double scan. The two physical lines of one logical line carry the same pixels. The stripe follows the scan line number. A triangle that moves down lets that stripe travel through the shape.

The overlap stutter is a separate fault. An overlap line walked the list and wrote pixels in the open slot. A slow line left the lower object half drawn. The cog now records each span before the slot write. The record holds the left edge, the right edge, and the colour. The slot write is one fill and then those spans.

A full-width first span fills with that colour. The 7-line lead and the three render cogs stay. The program is 19228 bytes. 2808 bytes remain above the stack. EEPROM holds this image. The user confirmed this picture on 18 Oct 2026.

## Scan line records — 18 Oct 2026

A general list uses the same records as the orbit scene. One scan line keeps 24 records. A box, a point, a line, a polygon, or a text shape uses one record when its range includes that line. A shape after these 24 records on that line is skipped. The skipped shapes are the front shapes.

Text used to paint after every span. A later triangle could not cover a label. A text shape now stores its list address in order with the spans. The slot write paints that text between the spans. The orbit scene has no text, so its picture stays the same.

A flat triangle stores 36 bytes. A general triangle stores 48 bytes. A box, a point, or a horizontal line stores 16 bytes. A sloped line stores 36 bytes. A text shape stores 20 bytes. The string stays outside the list, except for text_inline.

A polygon stores 24 bytes plus 12 bytes for each trapezoid. The polygon uses one record on a scan line. Each trapezoid above that line costs two saturating multiplies. A filled triangle uses one record. A wireframe triangle uses three line records.

The bring-up list is 160 longs. The orbit scene stores 340 bytes and draws 10 shapes. The beam-chase demo list is 900 longs. The demo draws 13 triangles and one text shape. Even lines use the low colour byte. Odd lines use the high colour byte.

The VGA cog shows each logical line twice. It forces the low two bits of every colour byte on. The program size stays 19228 bytes. 2808 bytes remain above the stack.
