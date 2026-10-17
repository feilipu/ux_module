# 3D work plan — lib_vjet

This plan covers three stages. Stage 1 puts VECTORJET on the same firmware as the UX Module text console. Stage 2 chooses the command path from CP/M-IDE. Stage 3 adds the CP/M-IDE library and tools.

This document does not change firmware. Product `main` stays in text mode until stage 1 passes its checks.

Read the framebuffer section before the handoff, the diary, and stage 2. The diary records failed steps. The handoff records the beam-chase pictures.

## Names

| Name | Meaning |
|------|---------|
| UX Module | RC2014 board. Propeller 1 (P8X32A). Product top is `src/ux_module.spin`. |
| Text mode | `hires_text_vga` on P16–P23. Two VGA cogs. 640×480 cells, 80×40. |
| Graphics mode | `VJET_vUXM_vga` on P16–P23. One VGA cog. 256×240 logical lines. |
| VECTORJET | Scanline engine in `src/lib_vjet`. |
| Display list | Hub list of shapes. The render cogs read it. |
| Draw cog | Second Spin cog. It builds the display list. |
| Cog 0 | Product main loop. The only writer of `acia.tx`. |
| Console pair | 0x80 and 0x81. Text mode is the 6850. Graphics mode keeps this pair and changes the meaning. |
| Text shape | Glyphs on the graphics raster. Shape type 3 and `hexfont.spin`. Not the 80×40 console. |
| Cooked mesh | Vertices and faces after a one-time STL or OBJ convert. |

Use these names only. Clock, pins, and the ACIA model stay as in `ARCHITECTURE_UX_MODULE.md` and `ARCHITECTURE_LIB_VJET.md`.

## Test platform

The test machine is CP/M-IDE v3.0 on the RC2014 8085, with the Compact Flash module and the ACIA console. The shell prints `RC2014 - CP/M IDE Shell v3.0`. The UX Module is that ACIA. The console pair is 0x80 and 0x81. The CF card uses other ports. The line is 115200 8N2.

The BIOS console is interrupt driven. `acia_interrupt` in `8085-cf-acia/cpm22bios.asm` reads status, reads data, and writes control. A graphics session holds `/INT` inactive before the register meaning changes. The interrupt then stays out of the pair.

Host programs for this test are 8085. Before you write them, read the z88dk skill `cpu-8085` and `target-rc2014` for subtype `acia85`. The skill file is `/Users/phillip/Container/ubuntu-data/z88dk/.agents/skills/cpu-8085/SKILL.md`.

Assemble with `z88dk-z80asm -m8085` inside the Ubuntu container. Use Zilog mnemonics. I/O is `in a,(n)` and `out (n),a`. Locals live on the stack. Do not add a BSS scratch cell for a temporary.

## Machine limits

The clock stays `_clkmode = XTAL1 + PLL16X` and `_xinfreq = 7_372_800`. The system clock is about 118 MHz.

P16–P23 have one owner. Text VGA and VECTORJET VGA do not run together. Stop `wmf.stop` and `i2c.stopCog` before `VJET_vUXM_vga.start`. Stop the render cogs and the VECTORJET VGA cog before `wmf.init` and `i2c.startCog`.

The demo PLL is the 2021 setting. The NCO target is 10 MHz. CTRA uses VCO/4. VCO is 160 MHz. The pixel rate is 10 MHz.

A 5 MHz NCO with VCO/2 holds VCO at 80 MHz. That cold picture did not lock. The monitor menu read 1920×1080.

Cog count in each mode:

| Mode | Cogs in use | Free cog |
|------|-------------|----------|
| Text | Cog 0, FTDI, ACIA, PS/2, two text VGA, DDC | 1 |
| Graphics | Cog 0, FTDI, ACIA, PS/2, one VECTORJET VGA, two render, one draw | 0 |

Graphics mode has no spare cog. A second bus cog is not free. DDC stops because the draw cog needs that cog. DDC pins are P28 and P29. They are not the VGA pins.

Hub is 32 KB. That figure includes the linked image. Eight scan slots are 2 KB (`256 × 8 / 4` longs). One 900-long display list is 3600 bytes. Two lists are 7200 bytes.

`wmf.stop` frees a cog. It does not free text VAR, text DAT, `hexfont`, or the scan buffer. The mesh limit is the Hub that remains after those objects, the scan buffer, and the lists. Also reserve a command FIFO, a mesh pool, and a draw stack sized for `gl.polygon`. The stage 1 binary includes those three, so the size note is the real limit.

The text buffer may alias one idle list only after every graphics-mode `wmf` and `readZ80` path is shown not to write it. The mesh and the scan buffer do not use that alias. A short draw stack can overwrite the ACIA mailbox. Size the stack before the first `cognew`.

The 74HC4078 decodes `/IORQ` with A5–A1. The Propeller also sees A7, A6, and A0. The live windows are 0x00, 0x40, 0x80, and 0xC0, each with A0 as the second register. The ACIA cog matches one base. The product path keeps that match on `PORT_80`. `PORT_VJET` stays unused.

Cog 0 is the only `acia.tx` writer. The draw loop in `vjet_test.spin` blocks Cog 0. That loop must not move onto Cog 0 while the ACIA stays live.

`readZ80` writes the text buffer today. In graphics mode that call must not run. Stage 1 still copies host bytes to FTDI. Stage 2 uses those bytes as graphics commands, so FTDI does not echo them. The keyboard still feeds `acia.tx`.

One shape header is 8 bytes. A trapezoid stack adds a 16-byte header and 12 bytes per trapezoid. One simple triangle is at least 36 bytes. A 900-long list is the demo size in `vjet_test.spin`. Count real `gl.triangle` bytes in stage 2 before you promise a scene size.

## What works today

`vjet_test.spin` and `graphtest.spin` are their own tops. `vjet_test` starts three render cogs and one VGA cog. Cog 0 draws. The loop in that file is the 2021 handshake.

1. Wait until bit 16 of `vga_status` rises. That edge is the front porch.
2. Publish `dlist_ptr`.
3. Call `gl.start` on the other list.
4. Draw the scene.

The front porch writes line 240. Vertical sync and the back porch write line 0. The render cogs wait for line 0. A handshake that writes line 240 in every blanking phase tore at 720×480 at 60 Hz. Use the 2021 words.

`vjet_fb.spin` is the known-good picture. The monitor holds 720×480 at 60 Hz. The colours `$0055`, `$55AA`, and `$AAFF` stripe. `vjet_test.spin` stays the locked beam-chase reference. The bring-up does not use the beam chase.

`ux_module.spin` does not link `src/lib_vjet`. Boot is text only. `PORT_VJET` is a constant. No cog decodes 0xC0.

## What failed on 11 Sep 2026

EEPROM held a standalone `vjet_test` image from git `b272914` (16 Apr 2021). The picture locked. The monitor reported 720×480. That image is the old PLL and three render cogs. It is not the integration test.

The same day, a hot switch from text mode smeared, then went grey. Graphics integration stopped. The product firmware returned to text only.

A parked top from that day sits outside git. It is a note of the attempt. It is not the file to load. These points matter:

- The switch order was `wmf.stop`, `i2c.stopCog`, a 250 ms blank, then VECTORJET VGA and two render cogs.
- The draw cog used one 900-long list and rebuilt it in place. Two shorter lists aborted the scene. A single list tears if a render cog still reads it.
- The first host `>` requested graphics. A CP/M prompt contains `>`. That trigger is unsafe.
- The parked file still linked the product objects. The picture failed with the in-tree switch, not only as a standalone demo.

Stage 1 repeats the switch with the in-tree PLL, a safe trigger, and the `vjet_test` handshake. It records the picture before any command protocol.

## Size note

OpenSpin 1.00.81 compiled these tops on 16 Oct 2026. Hub is 32768 bytes. The binary file ends at the variable base. Free bytes sit above the initial stack pointer. The clock long is 117964800. The mode byte is $6F.

| Top | File | Code | Variables | Stack pointer | Free |
|-----|------|------|-----------|---------------|------|
| `ux_module.spin` | 12780 | 12764 | 6456 | 19252 | 13516 |
| `vjet_test.spin` | 6216 | 6200 | 9336 | 15580 | 17188 |
| `ux_module_vjet.spin` | 19452 | 19436 | 12712 | 32180 | 588 |

Two 900-long lists make the bring-up image 768 longs too large. The bring-up keeps one 900-long list. The draw cog rebuilds that list after vsync. The render cogs can still read it, so the picture can tear. The 588 free bytes are the Cog 0 stack. The draw cog has its own 128 longs.

The handoff section has the current bring-up size. The table above is an early note.

Compile the bring-up with both search paths.

`openspin -L src -L src/lib_vjet -b -o build/ux_module_vjet.binary src/ux_module_vjet.spin`

## Stage 1 — Text and graphics on one firmware

Goal: one binary runs the product console, enters graphics mode, shows the `vjet_test` scene, keeps the ACIA link, and returns to text.

The bring-up file is `src/ux_module_vjet.spin`. Product `src/ux_module.spin` stays text only.

The bring-up top is a copy of the product object tree plus the switch. Promote that switch into `src/ux_module.spin` only after the checks below pass. Boot still starts text mode. VECTORJET stays off until the operator asks.

### Switch order

1. Set a mode flag so Cog 0 stops `wmf` calls.
2. Call `wmf.stop`.
3. Call `i2c.stopCog`.
4. Wait a short blank so the text driver has left the pins. Start at 250 ms. Shorten it only after a lock.
5. Start `VJET_vUXM_vga` on pin group 2 (`16/8`).
6. Start two render cogs. Pass the same scan buffer, `dlist_ptr`, and status long.
7. Publish a cleared list, then set the render-ready flag.
8. Start the draw cog. Pass a stack sized for `gl.polygon`.
9. On the way back, clear the ready flag, stop the draw cog, stop both render cogs, and stop the VECTORJET VGA cog.
10. Call `wmf.init`, then `i2c.startCog`. A cleared text screen is acceptable.
11. On a failed `cognew`, stop every graphics cog that `start` already launched. Then run step 10.

Cog 0 does steps 1 to 3 and the return path. The draw cog does not call `acia.tx`. The ACIA cog stays up across the switch. Do not pulse the bus `/RESET` as part of the video switch. Two VGA drivers must not drive P16–P23.

### Draw cog

Copy the handshake from `vjet_test.spin`. Use two lists when the binary fits in Hub. Publish at the front porch. Wait for bit 17 before `gl.start` on the idle list.

If two 900-long lists do not fit, use one list for the first picture and record the tear. The size note records that result. The bring-up uses one list. Alias the text buffer to one idle list only after the graphics-mode paths are shown not to write it. A missed write corrupts the list the render cogs are reading.

The first scene is the spinning triangles and the centred text from `vjet_test.spin`. `hexfont.spin` links for that text. A later build can drop the font when the scene has no text shapes.

### Trigger and return

Use a PS/2 chord that the console does not emit. The chord is Ctrl+Alt+G. The same chord returns to text. A held key switches once. Do not use the first `>`.

The chord uses the same guard as Enter graphics. If `z80XmSess` or `hostXm` is set, stay in text mode. Handle the chord and Ctrl+Alt+Del before the `txCheck` leave in `kbdToZ80`. A full console TX FIFO currently takes that leave first, so the chord never runs.

The return chord, Ctrl+Alt+Del, Enter text, and a backplane `/RESET` all stop the draw cog, both render cogs, and the VECTORJET VGA cog. Then they call `wmf.init` and `i2c.startCog`. Product `panicReset` only wipes the ACIA and calls `textOut`. The bring-up stops VECTORJET, calls `screenInit`, and starts DDC after P5 is high.

Stopping the ACIA cog is not a video restore. Cog 0 runs this path. A wedged Cog 0 needs the FTDI DTR reset of the Propeller.

In graphics mode, `readZ80` still drains the ACIA receive FIFO and still writes FTDI. It still calls `wmf` so the FTDI edit column stays correct. The text VGA cog is already stopped, so those calls write Hub only. `kbdToZ80` and `termToZ80` stay. The pump cap stays. XMODEM parsing stays.

### Stage 1 checks

Run these in order. Stop on the first failure.

1. Build the current product top. Record the binary size and the Hub bytes left.
2. Load in-tree `vjet_test` with the demo PLL. The picture must lock on the target monitor. Record the on-screen mode line.
3. Load the bring-up top. Boot must show the text banner. The 8085 must still see the console at 0x80.
4. Enter graphics mode. The triangle scene must hold for 60 seconds with no smear and no grey field.
5. Type on the PS/2 keyboard. The 8085 must receive the bytes while the scene runs.
6. The 8085 must still send bytes to FTDI while the scene runs. Stage 1 leaves the pair as a 6850.
7. Return to text mode. The banner path must run. The keyboard and the 8085 console must work.
8. Repeat the switch ten times. Cog `start` must not fail for lack of a cog.

Record the monitor mode line for a cold in-tree `vjet_test` and for the hot switch. Keep the two results separate. The 720×480 line belongs to the old PLL image. Text mode is the 640×480 table at about 70 Hz. VECTORJET is a 256-wide line-doubled raster at a 10 MHz pixel rate. A 250 ms blank does not turn one raster into the other.

If the cold in-tree image greys, stop. The switch is not the cause. If only the hot switch greys, separate a text cog that still drives P16–P23, PLL settle, and the blank time. Fix the picture before stage 2.

### Cold load, 16 Oct 2026

The in-tree `vjet_test` image was loaded into RAM on the FTDI port. The EEPROM image was left unchanged. The loader reported 117964800 Hz and mode byte $6F.

The monitor shows a picture. The left side alternates white and light pink. That colour is the background triangle `$ECEC`. The drawing is torn into horizontal bands. The triangles do not hold still.

The monitor menu reads 1920×1080. A 1920×1080 signal is about 67.5 kHz. This raster is 31.25 kHz and 59.6 Hz. The 11 Sep lock was reported as 720×480. The input frequency pair is still unread.

The cold picture now holds. The bring-up image stays unloaded.

The second RAM load uses the demo PLL. The NCO is 10 MHz and CTRA uses VCO/4. The image is 6216 bytes. The EEPROM image was left unchanged.

That load locks at 720×480 at 60 Hz. The picture tears. The tear follows the later scanline handshake. The third RAM load restores the 2021 handshake on the same PLL.

The third load holds. The monitor reads 720×480 at 60 Hz. The triangles and the text stay whole. The reference photo is `docs/vjet_demo_720x480.jpg`.

The bring-up draw cog uses that handshake. Two lists of 300 longs. Two render cogs. Control-G on the FTDI console toggles graphics. The EEPROM image is this bring-up, so a relay open boots it. The product image can be written back with `ux-load`.

The text picture locks. The monitor reads 640×480 at 66 Hz. The active text table is 640×480, totals 800×525, with `pr` = 28. That table calculates to about 70 Hz.

Control-G then left a black picture. The monitor stayed locked. The VGA cog was running and the scan lines stayed clear.

That image stored `$8080` in `dlist_ptr` and set the ready flag before the draw cog started. A render cog that reads `$8080` can stay in the shape fixup. The first publish was also an empty list.

Cog 0 now builds the first list and stores that address before the ready flag. The draw cog builds the other list and publishes it at the front porch. The draw stack is 256 longs. The serial line prints `GFX` after the first list is built.

That list is valid. The serial line reported `GFX 00 01FF4CD4 00F1FF10 00000000`. The abort code is 00. The first shape is the background triangle, type 1, from scan line -240 to 241. A full-screen box was also invisible. The monitor stayed black at 720×480 at 60 Hz.

The render cogs never left their ready wait. `cognew` stores bits 15:2 of the parameter address. `gfxReady` was a byte, so the cogs watched a different byte and that byte stayed 0. `gfxReady` is now a long.

The long `gfxReady` image uses two render cogs. It shows the spinning triangles. The picture locks for part of the time. It then tears and the monitor shows the fail pictures.

The next EEPROM image stops the PS/2 cog for the graphics session and starts three render cogs. `vjet_test` uses three render cogs and holds this scene. The PLL and the 2021 handshake stay the same. The keyboard cog starts again on return to text.

That image was loaded. The file is 19500 bytes. One Control-G was sent after the 8085 prompt.

Three render cogs tear more than two. The triangles show, then the picture tears again.

`vjet_test` already uses this board clock: `_xinfreq` = 7_372_800 and `_clkmode` = XTAL1 + PLL16X. It uses the same VGA cog and the same renderer. It runs no ACIA cog and no FTDI cog. Cog 0 builds the list. The file is 6140 bytes. The user reports a clean spinning-triangle picture.

The next image is `vjet_acia.spin`. It is that demo plus the ACIA cog on port 0x80. P5 pulses low for 1 ms so the 8085 polls the console during the picture. The draw loop stays the demo loop. The file is 7532 bytes. The user reports clean triangles.

The next image is `vjet_ftdi.spin`. It adds the FTDI cog at 115200. The draw loop stays on Cog 0. Cog 0 does not pump the FIFOs. The file is 8660 bytes. The user reports clean triangles.

The next image is `vjet_spin.spin`. It adds one Spin cog. That cog repeats and reads one Hub long. Cog 0 still builds the list. If the new cog does not start, the picture stays blank. The file is 8684 bytes.

That second Spin cog tears the picture. The triangles are hardly visible. They lock for about half a second, then tear again. The ACIA cog and the FTDI cog stayed clean. One Spin cog is the limit for this scene.

The next EEPROM image is the bring-up with the draw loop on Cog 0. There is no draw cog. Three render cogs. The ACIA cog and the FTDI cog stay up. The PS/2 cog stops. Cog 0 checks Control-G once each frame and does not pump the FIFOs during the picture. The file is 19492 bytes. One Control-G was sent after the 8085 prompt.

The triangles showed about half the time. Then the signal stopped. Cog 0 has 2264 bytes of free Hub above the program. The demonstration has about 17KB. The draw on Cog 0 overran that 2KB. Hub wrapped and the video pins went idle.

The next image parks Cog 0 on `waitcnt`. The draw cog uses the text buffer as its stack. That buffer is 800 longs. Text VGA is stopped, and `screenInit` rebuilds the buffer on return. Three render cogs. The ACIA cog and the FTDI cog stay up. The file is 19564 bytes. Cog 0 has 2188 bytes free.

That image kept the signal. Triangles showed about half the time. About 2 seconds stayed locked, with flickers. About 4 seconds were torn. The picture then locked again, with small flickers.

The VGA cog now reads the next pixel group while the current group is on the screen. The last group of the line has no extra read. The PLL, the pixel scale, and the 2021 handshake stay the same. The file is 19580 bytes. Cog 0 has 2172 bytes free.

The locked part grew to about 60 percent. While locked, the picture is steadier. It still tears hard for several seconds each turn.

The clean demonstration starts VGA on cog 2 and the three render cogs on cogs 3, 4, and 5. The ACIA cog is cog 6. The previous bring-up left the ACIA cog on cog 4, so two render cogs moved up. This image holds the 8085 in reset through DDC and the keyboard start. The ACIA cog then starts on cog 6. Graphics stops text, DDC, and the keyboard, so VGA and the render cogs take 2, 3, 4, and 5.

The file is 19568 bytes. Cog 0 has 2184 bytes free. That image was loaded. One Control-G was sent after the 8085 prompt. The user reports that the stable picture is about 20 percent of the time, perhaps less.

The next image keeps that boot order. The ACIA cog stays on cog 6. VGA stays on cog 2. The draw cog starts after the first render cog, so the draw cog takes cog 4. The render cogs take 3, 5, and 7. The PLL, the pixel scale, the prefetch, and the 2021 handshake stay the same. The file is 19552 bytes. Cog 0 has 2200 bytes free. That image is now in EEPROM. One Control-G was sent after the 8085 prompt. The user reports about 10 percent locked, and that lock is fleeting. This is the worst bring-up picture. The signal is still present.

## Handoff — 17 Oct 2026

EEPROM holds `src/ux_module_vjet.spin`. The file is 19552 bytes. Cog 0 has 2200 bytes free above `dcurr`. The relay pid is 17307. One Control-G was sent after the 8085 `E>` prompt. Do not send a second Control-G until the next image is loaded.

The cog map after Control-G is fixed by `cognew` order.

| Cog | Work |
|-----|------|
| 0 | Park. `waitcnt` every 100 ms. |
| 1 | FTDI |
| 2 | VECTORJET VGA |
| 3 | Render stripe 0 |
| 4 | Draw. Spin. Stack is the 800-long text buffer. |
| 5 | Render stripe 1 |
| 6 | ACIA |
| 7 | Render stripe 2 |

### Pictures that stayed locked

Each of these uses the demo PLL, the 2021 porch words, and the `vjet_test` scene. The user confirmed each picture.

| Image | Spin | Cog map | File |
|-------|------|---------|------|
| `vjet_test` | Cog 0 draws | VGA 1. Render 2, 3, 4. | 6140 |
| `vjet_acia` | Cog 0 draws | That set, plus the ACIA cog. | 7532 |
| `vjet_ftdi` | Cog 0 draws | VGA 2. Render 3, 4, 5. ACIA 6. Cog 7 free. FTDI is cog 1. | 8660 |

`vjet_ftdi` is the clean reference for a bring-up that also has the FTDI cog and the ACIA cog.

### Pictures that tore

| Image | What changed | Result |
|-------|----------------|--------|
| `vjet_spin` | One extra Spin cog. It adds `framecount` in a loop. Render stays on 3, 4, and 5. | Tear. Lock for about half a second. 8684 bytes. |
| Bring-up, draw on Cog 0 | 2264 bytes free on Cog 0. | Triangles, then no signal. The stack wrapped. |
| Draw on the text buffer. Render 3, 5, 6. | 19564 bytes. No prefetch. | About 50 percent. About 2 s locked, then about 4 s torn. |
| Same, plus the VGA prefetch | 19580 bytes. | About 60 percent. Steadier while locked. A hard tear for several seconds. |
| Render 3, 4, 5. ACIA on cog 6. Draw on cog 7. | 19568 bytes. Prefetch kept. | About 20 percent, or less. |
| Render 3, 5, 7. Draw on cog 4. ACIA on cog 6. | 19552 bytes. This is the EEPROM image. | About 10 percent, fleeting. |

The clean demo keeps render cogs on adjacent IDs. The widest gap is the worst torn picture. A spare cog between render cogs is not the repair.

### Counted timing

The clean demo and the bring-up share `VJET_vUXM_vga.spin` and `VJET_vUXM_rendering.spin`. The constants below are the same in both.

The system clock is 117964800 Hz. FRQA is 364088889. The NCO is 10000000.003 Hz. CTRA selects VCO/4, so PLLA is 40000000.012 Hz. VCO is 160000000 Hz. That VCO is outside the 64–128 MHz range. Leave it. A 5 MHz NCO did not lock.

`visibleScale` is `(4 << 12) + 16`. The low 12 bits are 16 PLL clocks, and that is one visible `WAITVID`. The line holds 64 groups. That is 1024 PLL clocks and 256 pixels. The low 12 bits of `invisibleScale` are 256 PLL clocks. That `WAITVID` is the horizontal sync. 1024 + 256 = 1280 PLL clocks on every physical line. A blank line is `blankPixels` 1024 plus the same 256. It is also 1280.

The VGA cog shows each logical line twice. 240 logical lines make 480 active lines. The front porch is 11 lines. Vertical sync is 2. The back porch is 31. The total is 524 physical lines. The line rate is 31250.000 Hz. The frame rate is 59.637 Hz. The monitor reports 720×480 at 60 Hz.

One PLL clock is 2.94912 system clocks. One physical line is 3774.87 system clocks. One logical line is 7549.75 system clocks.

The VGA cog writes the logical line number once, before both copies. The low word is 0 through 239 while the picture is active. The front porch writes 240 and sets bit 16. Vertical sync and the back porch write 0. Bit 16 stays set for the whole blank.

### Render allowance

Three render cogs step by the logical index, not by the hardware cog ID. Cog stripe 0 draws lines 0, 3, 6, and so on. The line buffer slot is `(line & 7) << 8`. Eight slots are 256 bytes each.

The cog may start line L+3 when the VGA line number is greater than L. The VGA cog reads line L+3 two logical lines later. The allowance is 15099 system clocks.

Vertical sync plus the back porch is 33 physical lines before active line 0. That window is 124571 system clocks. The top-edge fixup runs there. The background triangle starts at Y −240. The clean demo finishes that fixup.

A clear writes 64 longs. A full-width span writes 64 longs. One `wrlong`, `add`, and `djnz` group takes 16 to 31 system clocks. A clear plus one full span is 2048 to 3968 clocks. Seven full spans plus the clear is 8192 to 15872 clocks. The slow end passes 15099 before the list walk is counted. The clean demo still draws the wide fan on cogs 3, 4, and 5. Those Hub waits stay inside the allowance for the whole turn.

### VGA margin

The shifter runs for 16 PLL clocks after `WAITVID`. That is 47.19 system clocks. The cog then executes `rdlong` (8 to 23 clocks), `add`, `or`, and `djnz` (4 clocks each). The work is 20 to 35 system clocks. The slack is 12 to 27 system clocks. The next `WAITVID` still meets the shifter at the slow Hub wait. The sync can stay locked while the shapes tear. The torn pictures did keep a signal.

The prefetch issues `rdlong` on the instruction after `WAITVID`. Keep it. The locked share rose from about 50 percent to about 60 percent, and the locked part got steadier. The prefetch did not remove the multi-second tear.

### Hub rule

The Propeller 1 manual gives each cog a Hub window every 16 clocks. The first Hub instruction waits 0 to 15 clocks, then takes 8. The total is 8 to 23 clocks. This rhythm stays the same no matter how many cogs run. A busy Spin cog does not add clocks to a render `wrlong`.

Eight windows fit in those 16 clocks. Neighbour cog IDs sit 2 clocks apart. A new ID moves only that cog onto another window.

### What the count rules out

The PLL, the 1280-clock line, and the 2021 porch words match the clean demo in every torn bring-up. Those constants are not the break. The stripe uses the logical index. A gap between hardware IDs does not move the stripe. The manual rules out a stolen Hub window. The second Spin cog does not slow a render `wrlong` by taking its slot.

### What still breaks the picture

`vjet_ftdi` is clean. Render cogs are 3, 4, and 5. Cog 7 is free. Cog 0 is the only Spin cog.

`vjet_spin` adds a Spin cog and tears, with those same render IDs. That is the smallest change that breaks the clean picture. The bring-up always runs two Spin cogs. Cog 0 wakes every 100 ms. The draw cog builds the list. The 100 ms wake matches the small flickers. It does not match a tear of several seconds.

Inside the torn bring-up, cog ID still changed the locked share: about 60 percent, then 20 percent, then 10 percent. The 60 percent map put the ACIA cog on cog 4 and render on 3, 5, and 6. The draw cog was cog 7. The same render IDs are clean in `vjet_ftdi` and torn in the 20 percent image. Window phase does not explain that pair. The second Spin cog is the difference. Phase can still push a wide line across the 15099-clock allowance, which is why the three torn maps do not score the same.

At the front porch the draw loop stores `dlist_ptr`, then calls `gl.start` on the other list. `gl.start` stores `$8080` in the link and clears 3 longs. A render cog reads `dlist_ptr` only in `new_frame`, and only when the VGA low word is 0. That moment is vertical sync, 11 lines after the publish. A cog that is still in the old list takes the broken link.

`sync_timeout` is 5000. Each wait is a `rdbyte`, a `cmp`, and a `djnz`, about 16 to 31 system clocks. The full wait is about 80000 to 155000 system clocks, or about 10 to 20 logical lines. One broken sync misses the beam for the rest of that frame. The sync can stay locked. The shapes tear. The clean demo reaches `new_frame` before `gl.start`. The wide part of the turn is the part that can still be inside the old list.

### Leave these alone

- Leave the PLL, `visibleScale`, and the porch lengths.
- Leave line 0 on vertical sync and on the back porch. Line 240 in every blanking phase tore.
- Do not draw on Cog 0. About 2 KB is free there. The signal stopped.
- Do not add a fourth render cog.
- Do not spread the render cogs again. The even spread is the 10 percent picture.
- Do not stop the ACIA cog. The 8085 then sticks on `/WAIT`.
- Do not start VECTORJET from `src/ux_module.spin`.
- Two 900-long lists do not fit. The bring-up uses two 300-long lists.

### First load from the handoff

Do not use that load. It kept the beam chase and changed one call. The beam chase is the part that is too tight. The next load is `vjet_fb.spin`, in the framebuffer section.

## Frame buffer — 18 Oct 2026

The beam chase shares one deadline with the render cogs. A wide line has about 15099 system clocks. A clear plus seven full spans can pass that. One late line can drop the rest of the frame. The next picture does not use that deadline.

EEPROM holds the framebuffer demo in the Stripes section. Do not send Control-G. This demo has no ACIA.

### What the OBEX drivers do

Three Propeller 1 drivers keep the plotter off the video deadline.

| Driver | Store | VGA cog |
|--------|--------|---------|
| Chip Gracey, `VGA_512x384_Bitmap` | One bit per pixel. 24 KB. Two colours in each 32×32 tile. | One `WAITVID` per 32 pixels. The plotter writes at any speed. |
| Kwabena Agyeman, VGA64 | One or two bits per pixel. The buffer must fit in Hub. | One cog. The resolution divides 640×480. |
| Parallax `VGA.spin` | Two bits per pixel in a tile. Four colours in one long. | One `rdlong`, then `WAITVID`. |

A colour long holds four bytes. Four-colour mode uses two bits to select one byte. The manual calls the clocks FrameClocks and PixelClocks. Both are PLLA clocks. A full long is 16 pixels in four-colour mode, or 32 pixels in two-colour mode.

The UX monitor locks on the 2021 line. That line is 1280 PLL clocks. Keep that PLL, those porches, and `VCFG`. Do not copy the 1024×768 timing from the 512×384 driver.

### Why the scanline engine misses

The scanline engine stores an 8-bit colour in every pixel. One line is 64 hub longs. The VGA cog reads a line about two logical lines after the render cog may start it. That allowance is 15099 system clocks. The wide fan sits on that limit for several seconds of the turn.

`vjet_ftdi` stays locked. Cog 0 is the only Spin cog. `vjet_spin` adds one Spin loop and tears, on the same render cog ids. The bring-up always runs two Spin cogs. The locked share was about 60 percent, then about 20 percent, then about 10 percent. A wider cog gap made that worse. The hub window is every 16 clocks for each cog. A second Spin cog does not steal a render `wrlong`. It still breaks a deadline that has almost no spare.

### The new split

`src/lib_vjet/vjet_fb.spin` is the next load. It keeps the display list, the three render cogs, and the `vjet_test` scene. It changes the store.

- The bitmap is 128 by 240. Each pixel is two bits. Each line has four colours.
- Two bitmaps and two palettes. The pair is 17280 bytes.
- The VGA cog scans the front bitmap only. It never waits for a render cog.
- PixelClocks is 8. FrameClocks is 16. That is two source pixels per `WAITVID`. Each source pixel is twice as wide as a 2021 pixel. 128 source pixels fill the same 1024 PLL clocks.
- The VGA cog swaps buffers in the back porch when `done` changes. A late frame repeats. The sync does not wait.
- The render cogs pack every second pixel of the 256-wide span. A fifth colour on that line uses colour 0.
- Cog 0 calls `gl.start` only after `done` matches `go`. The render cogs are not in that list.
- The render cogs start the next frame only after the VGA cog shows the buffer they filled, and after Cog 0 publishes.

The program is 6912 bytes. The buffers, the palettes, the scratch, and the two 300-long lists add 20488 bytes. About 5368 bytes remain above that image. Cog 0 draws. That is the same role as in `vjet_test`.

The binary does not start the ACIA cog and does not start the FTDI cog. Stop the relay before the load. The relay open resets the Propeller.

### What the first picture must show

1. The monitor stays on 720×480 at 60 Hz.
2. The triangles stay whole while they turn. A repeated frame is acceptable. A torn line is not.
3. Centre lines can share colours. Some wedges will use one colour. Horizontal detail is half of `vjet_test`.

If the monitor leaves 720×480 at 60 Hz, stop. The next edit is the visible `VSCL` only. Leave the PLL and the porches.

If the signal drops and the monitor had locked, the next edit moves the draw off Cog 0. Leave the bitmap code.

### Edge state — 18 Oct 2026

The first framebuffer picture locked. The triangles were cut. Three render cogs each ran the top fixup, so one cog wrote the Y 0 edges over edges another cog had already walked. The sync wait then gave up after 5000 tries and kept the bad edges. A triangle that starts above the screen then loses its lower part. A small triangle does this only while a vertex is above the screen, and the stale edges draw that piece at the bottom.

Cog 0 now runs the top fixup alone. It writes `fixup` at control offset 24. The other cogs wait for that long. A later line waits until the sync byte matches. It does not give up. `fixup` is the seventh control long. Clear it before `boot`. That load did not change the picture.

### Colours — 18 Oct 2026

The clean driver gives every four pixels their own colour long. The first framebuffer kept one colour long for the whole line. A fifth colour on that line was drawn as colour 0. A narrow triangle then painted the rest of that line. It cut the white triangle as the narrow triangle moved up.

One load stored four colour longs on every line and kept one display list. The program was 6964 bytes. About 850 bytes remained for the stack. The monitor showed no triangles. Do not load that image again.

The packer now stores each even line. The store is 120 lines. Each stored line has eight colour longs. One long covers 16 pixels. The VGA cog shows each stored line four times. Odd lines still walk the edges. They are not stored. Two display lists remain. The PLL, the porches, and the visible VSCL stay on the 2021 line. Cog 0 still does the top fixup alone. The sync wait does not give up.

This program is 6964 bytes. The two bitmaps, the two palette tables, the scratch, and the two 300-long lists leave 7156 bytes for the stack. Cog 0 draws. That image stopped the full-width streaks.

### Intersections — 18 Oct 2026

A group of 16 pixels still held only four colours. At a crossing, the packer drew a fifth colour as colour 0. That colour cut a small hole in the rainbow and in the white triangle.

The packer now keeps four colours for each group of 8 pixels. A fifth colour in that group uses the nearest of the four. A pair of source pixels keeps a one-pixel wedge. The store is 80 lines, lines 0, 3, 6, and so on. The VGA cog shows each stored line six times. Every line uses colour byte 2. The bitmap and the palette table still use 15360 bytes together. The PLL, the porches, and the visible VSCL stay on the 2021 line.

The first 7012-byte load stayed black. The colour store patched the source field, so every palette byte stayed 0. The store now patches the destination field. Vertical steps are one stored line taller than the 120-line image. The user confirmed that picture. Colours and shapes were clean.

### Edges — 17 Oct 2026

The 80-line picture is clean. Colours and shapes match. The steps are taller than the 120-line picture. A stored line is six screen lines. The 120-line picture used four.

A finer vertical store does not fit beside the 8-pixel colours and two buffers. One display list saves 1200 bytes. That is not enough for 120 stored lines at 16 colour longs.

Horizontal steps return to one pixel. The store is 256 pixels on the same 80 lines. Each pixel is 4 PLL clocks. FrameClocks stays 16. 256 pixels fill 1024 PLL clocks. Each colour long covers 16 pixels.

A fifth colour still uses the nearest of the four. The packer no longer keeps a one-pixel wedge from a pixel pair. Every source byte is one pixel. The program is 6900 bytes. The two bitmaps and the two palette tables use 20480 bytes together. About 2100 bytes remain for the stack.

Cog 0 draws. The PLL and the porches stay on the 2021 line. Visible VSCL is `(4 << 12) + 16`. The 6900-byte file was the EEPROM image before the stripe load.

### Stripes — 17 Oct 2026

The 6900-byte picture uses one colour byte on every screen line. The 2021 demo uses two bytes. An even line uses the low byte. An odd line uses the high byte. The VGA cog shows each logical line twice. The screen pattern is two bright lines, then two dark lines.

The framebuffer stores every third logical line and shows it six times. Six repeats of one byte would make a band of six lines. The 2021 pattern repeats every four screen lines.

A set bit 0 in the colour byte means the dark lines are $55 lower. The VGA cog ORs $03, so bits 1 and 0 are not a visible colour. The packer sets the bit when the high byte is the low byte minus $55. The colours $0055, $55AA, and $AAFF stripe. Equal bytes stay solid. The background, the wide fan, and the text stay solid.

Even stored lines show bright, bright, dark, dark, bright, bright. Odd stored lines show the inverse. The program is 8044 bytes. About 944 bytes remain for the stack. EEPROM holds this image.

The user accepted this picture on 17 Oct 2026. It is the known-good graphics image. Leave that image in EEPROM until a bring-up picture locks.

### Leave the beam-chase objects

`VJET_vUXM_vga.spin` and `VJET_vUXM_rendering.spin` stay on the 2021 path. `vjet_test`, `vjet_acia`, and `vjet_ftdi` stay the clean references. The new files are `VJET_vUXM_vga_fb.spin`, `VJET_vUXM_rendering_fb.spin`, and `vjet_fb.spin`.

## Stage 2 — Command path

The 8085 must build scenes without a new Propeller binary for each model. The Propeller does not parse STL or OBJ for each frame. A cooker on CP/M or on the Mac converts the file once.

### Roles

| Option | Role in this plan |
|--------|-------------------|
| STL | Authoring file for triangles. ASCII or binary. No colour in the file. The cooker assigns one colour byte per solid or per facet. |
| OBJ | Authoring file when a face is a convex quad. One convex face becomes one `gl.polygon`. |
| Cooked mesh | The bytes that move to the UX Module. Int16 object-space vertices. Faces are indexes plus a colour byte. Weld duplicate STL corners. |
| Command FIFO | Hub ring for graphics payloads on 0x81. The ACIA cog is the only writer. Graphics status is a separate Hub long, not `acia_status`. |
| Console pair | The only command path. Text mode is the 6850. Graphics mode changes the meaning of 0x80 and 0x81. |
| Text shape | Labels on the graphics raster. The 80×40 console is stopped for the whole graphics session. |
| GSX | Later CP/M compatibility layer for 2D programs. It calls the same port commands. |
| ReGIS | 2D text grammar for experiments on a host terminal. The 3D matrix helpers in that library stay on the sender. |
| Master System / MSX VDP | Pattern for a control port plus a data port. The tile and sprite engine is a different machine. |

### One address pair

Text mode and graphics mode do not share the screen. A label on the picture is a text shape. `vjet_test.spin` already draws one with `gl.text_centered` and `hexfont.spin`. That string uses the display list. It does not use the 80×40 text cogs, and it does not need a second I/O address.

The product path uses 0x80 and 0x81 in both modes. `PORT_VJET` stays a constant. No cog decodes 0xC0. The ACIA cog does not change `port_active_mask`. There is no A6 test. P24 and P25 stay with that cog.

In text mode the pair is the 6850. Status and control are 0x80. Data is 0x81. In graphics mode a Hub flag selects the table below on the same match.

| Access | Graphics meaning |
|--------|------------------|
| 0x80 write | Command |
| 0x81 write | Payload byte into the command FIFO |
| 0x80 read | Graphics status. Room, mode, overflow, and key ready. Not `acia_status`. |
| 0x81 read | Next PS/2 key, or 0 when the key FIFO is empty |

The graphics path releases `/WAIT` on every exit, including an unknown command. It does not fall into `receive_command`, `transmit_status`, or `sync_irq`. A payload of `$03` must not master-reset the console FIFOs. The new instructions must `fit` in the cog. If they do not fit, shorten the handler. No Hub operation sits between `waitpne` and `waitpeq`.

Cog 0 writes the mode flag. The chord and the enter sequence are the two writers. The ACIA cog only reads the flag. Enter text is a command. The ACIA cog stores that request in its own Hub byte. Cog 0 reads the byte, restores text, and clears the mode flag.

The draw cog is the only consumer of payload bytes. It does not exist until graphics mode has started.

The pair is still a 6850 until the flag is set. The program sends `di`, then a short data sequence. Cog 0 sees that sequence in `readZ80` and sets the flag. Cog 0 ignores the sequence during XMODEM. Stage 1 does not send it. Stage 1 uses the PS/2 chord and leaves the pair as a 6850.

Cog 0 swallows the enter sequence. It does not print those bytes on the text screen or on FTDI.

On entry the cog saves `acia_config` and holds `/INT` inactive. `acia_interrupt` then does not run. On Enter text the cog restores `acia_config` and Cog 0 clears the flag after the video cogs are back. The program sends `ei` only after the status read says text mode.

The program does not call BDOS character I/O, `acia_putc`, or `acia_getc` while the flag is set. Those calls expect a 6850. CF disk ports are separate. A disk error that prints still uses the console, so the program does not call BDOS until text mode has returned.

`kbdToZ80` still fills the key FIFO. The 8085 reads 0x81 often enough that the FIFO does not fill, and before it waits on room. The console TX FIFO holds 511 bytes. When it is full, `kbdToZ80` leaves on `txCheck` before Ctrl+Alt+Del. Handle the chord before that test.

A second window is the worse fit on this machine. The BIOS interrupt already owns 0x80 whenever `/INT` is active, so 0xC0 would not keep the console safe. An A6 test can also steal 0x80, as the review recorded. One pair, with `/INT` held off, is the command path. Leave 0xC0 unused.

If a later program must call BDOS console output while a picture is showing, reopen that note. This plan does not build that program.

### Command set to try

Keep the first set small. Multi-byte values are little-endian on 0x81. A write to 0x80 selects the command. Following writes to 0x81 are the payload. The enter sequence is the only graphics request that travels as 6850 data.

| Command | Payload | Effect |
|---------|---------|--------|
| Enter graphics | none | Same switch as stage 1. The 6850 data sequence, or the PS/2 chord, sets the flag. Ignored during XMODEM. Stage 1 uses the chord only. |
| Enter text | none | Reverse switch. Also the recovery command. |
| Clear | colour word | Empty both lists to that colour. |
| Load mesh | count, then cooked bytes | Store one resident mesh. Reject the load if Hub cannot hold it. |
| Set pose | yaw, pitch, roll, scale | Draw cog uses this on the resident mesh. |
| Stream frame | count, then screen triangles | Replace the dynamic frame. No resident mesh. |
| Draw | none | Draw cog flips at the next front porch. |
| Text | x, y, scale, count, then bytes | One text shape from `hexfont.spin`. |
| Status | none | Read on 0x80 while the flag is set. FIFO room, mode, overflow, list room, and key ready. |

The draw cog shifts pixel integers to 16.16 before `gl.triangle`. A raw pixel in 0..239 has a high word of 0. `gl.triangle` then treats the face as flat. The 8085, or a CP/M cooker, owns the projection.

`gl.polygon` is only for one convex face the host has already clipped. The stream primitive is `gl.triangle`. A text shape uses the same list. Pass the hex font pointer and a Hub string.

The resident path is for a mesh that fits in Hub. The draw cog rotates it, drops back faces, clips, and emits triangles. Sort by centroid Z, then by start scanline. Stop before `gl.done` would abort the list. Set the overflow bit in the status byte.

Colour values stay in the packed word the renderer already reads. The cooker maps its colour byte to that word.

### Who runs the maths

Try both paths on one cube. The cube is 8 vertices and 12 faces.

1. Resident mesh. The draw cog spins it from `Set pose`.
2. Stream frame. A Spin table pretends to be the 8085 and sends 12 projected triangles.

Time both from bit 17 to the next front porch. That window is most of the frame, not the porch alone. On a miss, skip the flip and set the overflow bit. Record which path meets that bar for 12 faces and for a larger cooked file. Twelve `gl.triangle` calls can fit. A long `gl.polygon` or a large Spin rotate is the miss to watch.

The product library will expose both. The default for a small file is the resident mesh. The default for a file that does not fit is the stream frame.

### GSX

GSX is CP/M graphics by BDOS call 115 (`C = 73h`, `DE` = parameter block). The block points at control, integer in, point in, integer out, and point out. Coordinates are signed 16-bit values. Source: [GSX notes](https://www.seasip.info/Cpm/gsx.html) and the GSX programmer guide ([PDF](http://www.z80.eu/downloads/gsx-pgr.pdf)).

A full GDOS, `ASSIGN.SYS`, and a `.PRL` driver are a large CP/M piece. RC2014 users do not boot that stack today. Ease of use is a small library. GSX is the compatibility coat on that library.

Map a subset after the port commands are stable.

| GSX function | UX command |
|--------------|------------|
| 1 Open workstation | Enter graphics. Return width 256 and height 240. |
| 2 Close workstation | Enter text. |
| 3 Clear | Clear. |
| 5 Escape 2 | Enter graphics. |
| 5 Escape 3 | Enter text. |
| 6 Polyline | One `gl.line` per segment. `gl.line` builds a trapezoid. It is not `gl.box`. Reject the call when the list would overflow. |
| 9 Filled polygon | Convex only. The CP/M side splits or rejects a concave outline. |
| 11 GDP bar | `gl.box`. |
| 8 Text | `gl.text` when the font is linked. |

Other GSX functions return a safe empty result. Cell array, locator, and writing mode are out of the first driver. GSX colour indexes map through a fixed table to packed colour words.

The driver runs on the 8085 test machine. Read `cpu-8085` before you write it. The Propeller does not implement BDOS.

### ReGIS

ReGIS is an ASCII graphics language on a serial console. The command letters include position, vector, curve, fill, text, screen, and write. The local reference is [feilipu/ReGIS](https://github.com/feilipu/ReGIS). That tree also has 3D matrix helpers. Those helpers run on the sender. They are not a Propeller parser.

A ReGIS string is easy to type and easy to show on an xterm build with ReGIS. It is a poor product path for 3D on this board.

- The bytes would arrive on the console port.
- Cog 0 would parse them, or it would copy them into a buffer for the draw cog.
- Cog 0 must stay short. The pump cap is 16 bytes per pass.
- A binary XMODEM block can contain the same bytes as a ReGIS string.
- A private 3D letter would no longer be VT125 or VT340 ReGIS.

Use ReGIS on the host when you want to compare a 2D picture. Do not parse ReGIS on the Propeller in the product path. If a later experiment wants a 3D noun, add it in the CP/M sender. The sender emits `Stream frame` or `Set pose`.

### Master System and MSX

The Master System article describes a Z80 and a VDP that descend from the TMS9918. The CPU writes a control port and a data port. Video RAM holds tiles, a name table, and sprites. Mode 4 is 256×192, with later 224 and 240 line modes. Source: [Master System architecture](https://www.copetti.org/writings/consoles/master-system/).

MSX computers use that same VDP family. The port pair is the idea to keep. The tile engine is not VECTORJET. VECTORJET already rasterises triangles, boxes, and text. A TMS9918 emulator would replace that renderer and would need a cog plan of its own.

Borrow these habits only:

- Two I/O addresses, control then data.
- A status read that tells the CPU when the device can take more bytes.
- Updates take effect on the next frame. They do not change the line the VGA cog is sending.

### Stage 2 checks

1. Count the Hub bytes of the stage 1 binary. State the largest resident mesh and the largest display list that still link.
2. Count the bytes of one `gl.triangle` and one `gl.polygon` in a real list.
3. Time `/WAIT` with the mode flag clear and with it set. Text mode must still boot and run `DIR`. With the flag set, `/INT` stays inactive.
4. Show the resident cube and the streamed cube. Record the frame time for each. Show one text shape on the same picture.
5. Overflow on purpose. The status bit must set. The list must stay sealed. `gl.done` must not walk into the next Hub object.
6. Fill the command FIFO. The 8085 must still read keys from 0x81. The return chord must still run.
7. Issue Enter text from 0x80 and from the key chord. Both must restore the 6850 and the text console.
8. Start an XMODEM receive on 0x80. Send Enter graphics, and press the chord. The mode must stay text until the transfer ends.

## Stage 3 — CP/M-IDE

Start this stage in `/Users/phillip/Container/ubuntu-data/CPM-IDE` only after the stage 2 command bytes are frozen. The UX Module tree keeps the Propeller code. The CP/M tree keeps the 8085 code for the `8085-cf-acia` build.

### Library

A small 8085 library is the interface programmers call. Read `cpu-8085` before the first function.

| Call | Port use |
|------|----------|
| `vjet_open` | `di`, then the enter sequence. Read 0x80 until the mode flag is set. |
| `vjet_close` | Enter text. `ei` only after status says text mode. |
| `vjet_load` | Load mesh from a memory block. |
| `vjet_pose` | Set pose. |
| `vjet_stream` | Stream frame on 0x81. Read keys from 0x81 when status says a key is ready. |
| `vjet_draw` | Draw. |
| `vjet_status` | Status read. |

The first demo is a `.COM` that loads one cooked cube, opens graphics, spins the pose, and closes on a key. Assemble with `z88dk-z80asm -m8085` inside the Ubuntu container. Follow `cpu-8085` for opcodes and stack locals. The host `PATH` does not carry `z88dk-z80asm`.

### Cooker

Accept ASCII STL, binary STL, and OBJ. Write a cooked mesh file the `.COM` can read from the CP/M disk.

Rules for the cooker:

- STL facets become triangles.
- A convex OBJ face becomes one polygon record. A concave face is split on the host.
- Weld vertices that share the same coordinates.
- Attach the colour byte from the solid name, the OBJ group, or a command-line value.
- Print the vertex count, the face count, and the cooked size.
- Refuse a file that exceeds the Hub limit recorded in stage 2.

A Mac cooker may exist for the same byte layout. The CP/M cooker is the one users run on the target. The Propeller never sees the STL text.

### Transfer

Load the `.COM` and the cooked file with the existing CP/M tools. `hget` stays on the RC2014 console at 115200 8N2. Hardware flow for that transfer is the console adapter, not the Propeller 6-pin header. The header is the programming port. During `hget` the pair stays a 6850. The graphics meaning starts only after `vjet_open`.

### GSX driver

Write the subset driver only after `vjet_open` and `vjet_stream` work in the demo. Ship it as a separate `.COM` or `.PRL`. Document the functions in the table above. A program that needs 3D calls the library. It does not go through GSX.

## Ordered work

Do the rows in order. A later row waits for the exit text of the row above.

| Step | Work | Exit |
|------|------|------|
| 1 | Measure the product binary and the free Hub. | A written size note. |
| 2 | Load in-tree `vjet_test` on the target monitor. | Mode line recorded. A grey picture stops the plan. |
| 3 | Bring-up top. Text boot, chord into graphics, draw cog, two render cogs. | 60 s stable scene. Keyboard and FTDI still move. |
| 4 | Return path and Ctrl+Alt+Del back to text. Ten switches. | Text console works after each return. |
| 5 | Promote the switch into the product top. Boot remains text. | Same checks on `ux_module.spin`. |
| 6 | Measure list bytes and `/WAIT`. | Numbers recorded in this file. |
| 7 | Mode flag on the existing 0x80 match. Graphics status on a read of 0x80. Handler must `fit`. | `DIR` works in text mode. `/INT` stays inactive in graphics mode. |
| 8 | Cube, resident and streamed. | Frame-time note. Overflow bit proven. |
| 9 | Freeze the command bytes. | A version byte in the status block. |
| 10 | CP/M library, cooker, and cube `.COM` for `8085-cf-acia`. | Cube spins. A key returns to the CCP. The 6850 interrupt works again. |
| 11 | GSX subset driver. | Open, clear, bar, convex fill, close. |

Status on 17 Oct 2026. Steps 1 and 2 are done. The locked picture is the framebuffer in the Stripes section. Step 3 is next.

The product image leaves 13516 bytes free. The framebuffer variables are 23776 bytes. Those variables do not fit in the free Hub. Step 3 has to shrink the store or share the text buffers before the bring-up can link the framebuffer objects. Do not replace the EEPROM image until that bring-up locks.

## Risks

| Risk | What to do |
|------|------------|
| Grey or smeared picture | Stay in stage 1. Compare the standalone in-tree demo on the same monitor. |
| Hub too small for two lists | One list and a recorded tear, or a smaller list. Do not shrink the ACIA FIFOs for this. |
| Graphics path too long for the cog | Shorten the handler. Do not add a bus cog. Do not open 0xC0. |
| Draw cog misses the porch | Stream fewer triangles, or move projection to the 8085. |
| BIOS ISR during graphics | Hold `/INT` inactive. The program stays in `di` until status says text mode. |
| Graphics mode with no exit | Return chord, Enter text, Ctrl+Alt+Del, and backplane `/RESET` stop VECTORJET, clear the mode flag, and restore `acia_config` before `wmf.init`. Handle the chord before `txCheck`. |
| XMODEM mistaken for commands | Ignore the chord and the enter sequence while a transfer is active. |
| Two writers of the mode flag | Cog 0 writes the flag. The ACIA cog writes only the Enter-text request. The draw cog writes only the display list. |

## Sources

| Document | Use |
|----------|-----|
| `ARCHITECTURE_UX_MODULE.md` | Clock, cogs, ACIA, text path |
| `ARCHITECTURE_LIB_VJET.md` | Display list, PLL, handshake, cog split |
| `.agents/skills/module-ux/SKILL.md` | Cog 0 rules, pump, XMODEM |
| `.agents/skills/library-vjet/SKILL.md` | List layout and VGA rules |
| `.agents/skills/hw-ux-pcb/SKILL.md` | Pin map and 74HC4078 |
| `src/lib_vjet/vjet_test.spin` | Handshake and first scene |
| `src/acia_rc2014.spin` | Port constants and the wait loop |
| `cpu-8085` skill | 8085 opcodes, stack locals, and `in` / `out` before any host program |
| `8085-cf-acia/cpm22bios.asm` | `acia_interrupt` and the 6850 console the test BIOS expects |
| [GSX](https://www.seasip.info/Cpm/gsx.html) | BDOS 115 and the function list |
| [GSX programmer guide](http://www.z80.eu/downloads/gsx-pgr.pdf) | Digital Research manual |
| [feilipu/ReGIS](https://github.com/feilipu/ReGIS) | ReGIS grammar and sender-side 3D matrices |
| [Master System](https://www.copetti.org/writings/consoles/master-system/) | VDP port pair and tile model |

## Review

An adversarial review checked this plan against the ACIA wait loop, the cog map, `kbdToZ80`, and the display-list calls. The sections above already include the changes.

| Point | Change in this plan |
|-------|---------------------|
| A6 test | Closed. The product path does not change the mask. A test of `OUTA` would still see carry if a later edit opens 0xC0. |
| Second bus cog | Removed. That cog cannot pull `/WAIT` low. P24 stays with the ACIA cog. |
| Mode flag | Cog 0 writes it. The ACIA cog reads it. Enter text is a separate request byte. |
| Graphics status | A read of 0x80 in graphics mode. It does not call `sync_irq`. |
| Backpressure | The 8085 reads keys from 0x81. A full key FIFO blocks Ctrl+Alt+Del. |
| Hub | The 32 KB figure includes the program image. Stage 1 reserves the FIFO, the stack, and the mesh pool. |
| Pixels | Shift to 16.16 before `gl.triangle`. Stream with `gl.triangle`. `gl.polygon` is one clipped convex face. |
| GSX | Polyline uses `gl.line`. The CP/M side splits or rejects a concave fill. |
| Chord | Same XMODEM guard as Enter graphics. Handle it before `txCheck`. |
| Recovery | Stop VECTORJET before `wmf.init`. `panicReset` today does not do that. |
| 8085 | Test platform is CP/M-IDE v3.0 `8085-cf-acia`. Assemble with `-m8085`. Read `cpu-8085` first. |
| Grey field | A cold in-tree picture and the hot switch are separate results. A grey cold picture stops the plan. |
| Other bases | 0xC0 stays undecoded. Do not move graphics to 0x00 or 0x40. |

## Address pair

A second pass asked whether 0xC0 is useful if text mode and graphics mode never share the screen.

They do not share it. P16–P23 have one owner. Text on the picture is already a VECTORJET text shape. `hexfont.spin` and `gl.text_centered` do that job in `vjet_test.spin`. A scrolling 80×40 console is not part of graphics mode.

The test BIOS will not share the pair either. `acia_interrupt` treats 0x80 and 0x81 as a 6850 for the whole time `/INT` is active. A graphics window at 0xC0 would leave that interrupt on the console pair. The session still has to stop the interrupt. One pair, with `/INT` held off and `di` in the program, is enough.

The command path is therefore 0x80 and 0x81, with the meaning switched by the mode flag. `PORT_VJET` remains unused. Host code for the test stays on the 8085 CF ACIA build, and it starts from `cpu-8085`.

The review said `hget` has no hardware pause on the Propeller header. `hget` uses the RC2014 console adapter. Flow control for that transfer stays on the adapter. The Propeller header remains the programming port.

These parts held. Stage 1 starts from the PS/2 chord. P16–P23 have one owner. The draw cog stays off Cog 0. The Propeller does not parse ReGIS. The plan does not emulate a TMS9918.
