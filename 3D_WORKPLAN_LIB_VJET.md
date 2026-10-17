# 3D work plan — lib_vjet

This plan covers three stages. Stage 1 puts the known-good framebuffer on the same firmware as the UX Module text console. Stage 2 chooses the command path from CP/M-IDE. Stage 3 adds the CP/M-IDE library and tools.

The repair history is `3D_PROCESS_LIB_VJET.md`. This file does not repeat those loads.

Product `main` stays in text mode until stage 1 passes its checks.

## Names

| Name | Meaning |
|------|---------|
| UX Module | RC2014 board. Propeller 1 (P8X32A). Product top is `src/ux_module.spin`. |
| Text mode | `hires_text_vga` on P16–P23. Two VGA cogs. 640×480 cells, 80×40. |
| Graphics mode | The framebuffer VGA cog on P16–P23. One VGA cog. 256×240 logical lines. |
| Beam chase | `VJET_vUXM_vga` and `VJET_vUXM_rendering`. Demo is `demo/vjet_test.spin`. |
| Framebuffer | `VJET_vUXM_vga_fb` and `VJET_vUXM_rendering_fb`. Demo is `demo/vjet_fb.spin`. |
| Display list | Hub list of shapes. The render cogs read it. |
| Draw cog | Second Spin cog. It builds the display list. |
| Cog 0 | Product main loop. The only writer of `acia.tx`. |
| Console pair | 0x80 and 0x81. Text mode is the 6850. Graphics mode keeps this pair and changes the meaning. |
| Text shape | Glyphs on the graphics raster. Shape type 3 and `hexfont.spin`. Not the 80×40 console. |
| Cooked mesh | Vertices and faces after a one-time STL or OBJ convert. |

Use these names only. Clock, pins, and the ACIA model stay as in `ARCHITECTURE_UX_MODULE.md` and `ARCHITECTURE_LIB_VJET.md`.

## Test platform

The test machine is CP/M-IDE v3.0 on the RC2014 8085, with the Compact Flash module and the ACIA console. The shell prints `RC2014 - CP/M IDE Shell v3.0`. The UX Module is that ACIA. The console pair is 0x80 and 0x81. The CF card uses other ports. The line is 115200 8N2.

The UX FTDI console uses that same frame. Host tools set two stop bits. The FTDI relay leaves `CRTSCTS` clear.

The BIOS console is interrupt driven. `acia_interrupt` in `8085-cf-acia/cpm22bios.asm` reads status, reads data, and writes control. A graphics session holds `/INT` inactive before the register meaning changes. The interrupt then stays out of the pair.

Host programs for this test are 8085. Before you write them, read the z88dk skill `cpu-8085` and `target-rc2014` for subtype `acia85`. The skill file is `/Users/phillip/Container/ubuntu-data/z88dk/.agents/skills/cpu-8085/SKILL.md`.

Assemble with `z88dk-z80asm -m8085` inside the Ubuntu container. Use Zilog mnemonics. I/O is `in a,(n)` and `out (n),a`. Locals live on the stack. Do not add a BSS scratch cell for a temporary.

## Machine limits

The clock stays `_clkmode = XTAL1 + PLL16X` and `_xinfreq = 7_372_800`. The system clock is 117964800 Hz. The EEPROM mode byte is $6F.

P16–P23 have one owner. Text VGA and the framebuffer VGA cog do not run together. Stop `wmf.stop` and `i2c.stopCog` before the framebuffer VGA start. Stop the render cogs and that VGA cog before `wmf.init` and `i2c.startCog`.

The PLL, the porches, and `VCFG` stay on the 2021 line. The NCO is 10 MHz. CTRA uses VCO/4. VCO is 160 MHz. PLLA is 40 MHz. PixelClocks is 4. FrameClocks is 16. Visible `VSCL` is `(4 << 12) + 16`. Do not copy that `VSCL` into `VJET_vUXM_vga.spin`.

A 5 MHz NCO with VCO/2 did not lock. The monitor menu read 1920×1080.

Cog count in each mode:

| Mode | Cogs in use | Free cog |
|------|-------------|----------|
| Text | Cog 0, FTDI, ACIA, PS/2, two text VGA, DDC | 1 |
| Graphics | Cog 0, FTDI, ACIA, one framebuffer VGA, three render cogs, one draw | 0 |

The PS/2 cog stops in this bring-up. Three render cogs publish the frame. Cog 0 of the renderer waits for the other two stripes, then writes `done`. Two cogs never write `done`.

The final build keeps the PS/2 keyboard. Graphics has no free cog. The keyboard must share the FTDI cog.

`keyboard_ps2.spin` is 332 cog longs. `terminal_ftdi.spin` is 107 cog longs. The limit is 496 longs. A straight sum leaves 57 longs.

The keyboard driver waits until the clock falls. A command to the keyboard holds that clock low for about 122 µs. One bit at 115200 is 8.68 µs. A blocking wait drops UART bits.

A polled driver can share the cog. It samples the PS/2 pins once each UART bit. A PS/2 half-clock is about 30 µs, so the poll sees the edge. That driver is not in the tree. Do not load a guess.

The FTDI cog already sends 8N2. Transmit uses 11 bit times. One mark, one start, eight data, and one stop. The next byte adds one more mark. Host tools set `CSTOPB`.

Cog 0 keeps the ACIA pump. DDC stops. A second bus cog is not free.

Hub is 32 KB. OpenSpin 1.00.81 measured these images.

| Top | File | Free above the stack | Note |
|-----|------|----------------------|------|
| `ux_module.spin` | 12780 | 13516 | Text only. |
| `demo/vjet_test.spin` | 6140 | — | Stored beam-chase demo. Current compile is 6156. |
| `vjet_ftdi.spin` | 8660 | — | Beam chase plus ACIA and FTDI. Clean. |
| `demo/vjet_fb.spin` | 8044 | about 944 | Accepted file `build/vjet_fb.binary`. Current source compiles to 8216. |
| `vjet_fb_probe.spin` | 6696 | — | Stripe and glass check. Was on EEPROM. Not a demo. |
| `vjet_fb_cube.spin` | 7520 | — | Stage 2 harness. Current source compiles to 7676. Not loaded. |
| `ux_module_vjet.spin` | 20408 | 1148 | Framebuffer bring-up. Ten content lines. |

The accepted bitmap does not fit in the bring-up. Two bitmaps and two palettes at 80 lines are 20480 bytes. The bring-up keeps 10 content lines and one black line. Each content line needs 256 bytes.

1148 bytes remain above the initial stack pointer. The reserved stack is 256 longs. The current `demo/vjet_fb.spin` source compiles to 8216 bytes. The stored accepted file stays 8044 bytes.

`wmf.stop` frees a cog. It does not free the text buffer. The text buffer is 3200 bytes. That alias does not close the gap. The ACIA and FTDI buffers stay live.

The 74HC4078 decodes `/IORQ` with A5–A1. The live windows are 0x00, 0x40, 0x80, and 0xC0. The product path keeps the match on `PORT_80`. `PORT_VJET` stays unused.

On 18 Oct 2026 the full bitmap is the costly store. The list and the bitmap both stay. The VGA cog scans the bitmap. The next bring-up uses the eight-line slice from `VJET_vUXM_rendering.spin`.

Three render cogs write that slice ahead of the scan. The original renderer used two cogs. Three cogs must stay ahead. The accepted framebuffer demo is unchanged.

Cog 0 is the only `acia.tx` writer. Do not draw on Cog 0 while the ACIA stays live.

One shape header is 8 bytes. A flat triangle is 36 bytes. A general triangle is 48 bytes. A box is 16 bytes. A text shape is 20 bytes. The scene counts are in Capabilities.

Two 300-long lists are 2400 bytes. Two 900-long lists overflow by 768 longs. The framebuffer demos use the 300-long lists. The bring-up lists are 64 longs each. The short scene fits in that list. Two 300-long lists do not fit beside the ten stored lines.

## Known-good mechanisms

`demo/vjet_fb.spin` is the framebuffer demo. The user accepted that picture on 17 Oct 2026. The monitor holds 720×480 at 60 Hz. `demo/vjet_test.spin` is the original beam-chase demo of the same picture.

The VGA cog scans a finished 256 by 80 bitmap. It does not wait for a render cog. A late frame repeats. The renderer stores logical lines 0, 3, 6, and so on. The VGA cog shows each stored line six times. Two bits select one of four colours in each group of 16 pixels. A fifth colour in that group uses the nearest of the four. The compare masks both bytes with `$FC`.

The line buffer is cleared to 0. The VGA cog ORs `$03` at display, so bits 1 and 0 are not a visible colour. A stored 0 displays as `$03`.

### Stripe rule

The rule is one test on the colour word. It is not a table of the three demo colours.

1. Read the low byte and the high byte.
2. Clear bits 1 and 0 of the low byte.
3. If the low byte is below $55, leave the flag clear.
4. If the high byte equals the low byte minus $55, set bit 0.

A set flag means the dark screen lines show that byte $55 lower. Equal bytes stay solid. `$0055`, `$55AA`, `$AAFF`, and any other pair with the same step all stripe. `$66BB` is such a pair. `$80C0` is not. `$80C0` stays solid.

The phase belongs to the raster, not to the triangle. Even stored lines show bright, bright, dark, dark, bright, bright. Odd stored lines show the inverse. Across the screen the pattern is bright, bright, dark, dark, repeated. A triangle that moves in Y slides through that pattern. The stripes do not travel with the triangle.

The beam chase can show any high byte on the odd line. This store cannot. One flag bit records only the $55 step. That is the limit of the rule.

### Occlusion and crossings

There is no depth buffer. Later shapes in the list overwrite earlier spans. A far triangle is drawn first. A near triangle is drawn after it. Where they overlap, the near triangle covers the far one.

A crossing is that overwrite, plus the four-colour limit. Five colours in one group of 16 pixels become the nearest of the four. A muddy patch there is the palette limit.

Bit 1 of the low colour byte asks for a 50 percent mix with the pixel already stored. The mix runs only when the control long `blend` is set. `demo/vjet_fb.spin` leaves that long clear, so the accepted picture stays solid. The mix is one byte at a time.

A solid span returns. It does not enter the mix. The mix averages red, green, and blue as separate pairs. A right shift of the whole byte moves red into green and green into blue. A glass triangle that fills many pixels can make the renderer miss a frame. The VGA cog then repeats the last finished bitmap.

Vertical edges step by six screen lines, because only every third logical line is stored. Horizontal edges step by one pixel.

### Leave in place

- The PLL, the porches, `VCFG`, and visible `VSCL` on the framebuffer VGA cog.
- `movd` in `find_color`. `movs` stores black.
- Cog 0 as the only top-edge fixup. The flag is the control long at offset 24.
- The beam-chase files. They are the reference, not the bring-up.

### Capabilities

The framebuffer demo is `demo/vjet_fb.spin`. Each frame draws 13 triangles and one text shape. The probe scene draws one box and nine triangles. Both tops keep two lists of 300 longs. One list is 1200 bytes. The two lists are 2400 bytes.

A shape starts with an 8-byte header. The header holds the link word, the sync byte, the type byte, and the two scanline words. A flat triangle stores 36 bytes. A general triangle stores 48 bytes. A box stores 16 bytes. A text shape stores 20 bytes.

The string for a text shape stays outside the list. The background triangle in the accepted scene is flat. The other twelve triangles store 48 bytes when the three scanlines differ. That frame stores up to 632 bytes. The probe stores 340 bytes. One list holds 33 flat triangles or 25 general triangles.

One list also holds 75 boxes or 60 text shapes. A polygon stores 24 bytes plus 12 bytes for each trapezoid. A sloped line stores 36 bytes. A horizontal line stores 16 bytes.

The bitmap is 256 pixels by 80 stored lines. Two bits select the colour. Each group of 16 pixels has four colours. One bitmap is 5120 bytes. One palette table is 5120 bytes. Two bitmaps and two palettes are 20480 bytes.

The scratch lines are 768 bytes. The accepted file `build/vjet_fb.binary` is 8044 bytes. The variables of that scene are 23776 bytes. The current `demo/vjet_fb.spin` source compiles to 8060 bytes. `blend` stays clear in that top. The probe source compiles to 6696 bytes.

EEPROM holds the probe loaded before this comment pass. The list check now counts the unused bytes on a box and on a text shape. Those scenes still fit, so the picture is unchanged. `blend` is set only in the probe.

## Stage 1 — Text and graphics on one firmware

Goal: one binary runs the product console, enters graphics mode, shows a framebuffer scene, keeps the ACIA link, and returns to text.

The bring-up file is `src/ux_module_vjet.spin`. It links the framebuffer objects. Product `src/ux_module.spin` stays text only.

Promote the switch into `src/ux_module.spin` only after the checks below pass. Boot still starts text mode.

The Hub limit is the bitmap store. The accepted frame uses at most 632 bytes. The bring-up scene is one box, two triangles, and the text " GFX". That list uses at most 132 bytes. Each bring-up list is 256 bytes.

Step 3 uses its own bitmap. Ten content lines fill the top of the picture. The VGA cog still scans 480 lines. Lines after the tenth show a black line in the buffer.

The last bright line of an even band reads the next palette. At the black line that read stays on the black line. The odd bands then stay black.

That picture differs from `demo/vjet_fb.spin`. Accept it on the monitor before it replaces the accepted scene. Leave `STORED_LINES` in the accepted renderer unchanged.

### Switch order

1. Set a mode flag so Cog 0 stops `wmf` calls.
2. Call `wmf.stop`.
3. Call `i2c.stopCog`.
4. Call `kbd.stop` in this bring-up only. Graphics has no free cog. The final build keeps the keyboard on the FTDI cog.
5. Wait a short blank so the text driver has left the pins. Start at 250 ms. Shorten it only after a lock.
6. Start the framebuffer VGA cog on pin group 2 (`16/8`).
7. Start three render cogs. Pass the same buffers and the same control block.
8. Start the draw cog. It posts the first list and increments `go`.
9. Set the render-ready flag after `go` is 1. The render cogs wait on that flag.
10. On the way back, clear the ready flag, stop the draw cog, stop the three render cogs, and stop the framebuffer VGA cog.
11. Call `wmf.init`, then `i2c.startCog`, then `kbd.start`. A cleared text screen is acceptable.
12. On a failed `cognew`, stop every graphics cog that `start` already launched. Then run step 11.

Cog 0 does steps 1 to 3 and the return path. The draw cog does not call `acia.tx`. The ACIA cog stays up across the switch. Do not pulse the bus `/RESET` as part of the video switch.

### Trigger and return

Use Ctrl+Alt+G. The same chord returns to text. A held key switches once. Do not use the first `>`.

The bench keyboard sends Ctrl+Alt+G. On a Mac that chord is Control-Option-G. Control-G (`$07`) on the FTDI relay is the same toggle. One BEL toggles. The framebuffer demo has no ACIA and no FTDI, so BEL does nothing there.

The chord uses the same guard as Enter graphics. If `z80XmSess` or `hostXm` is set, stay in text mode. Handle the chord and Ctrl+Alt+Del before the `txCheck` leave in `kbdToZ80`.

The return chord, Ctrl+Alt+Del, Enter text, and a backplane `/RESET` all stop the draw cog, the three render cogs, and the framebuffer VGA cog. Then they call `wmf.init`, `i2c.startCog`, and `kbd.start`.

In graphics mode, `readZ80` still drains the ACIA receive FIFO and still writes FTDI. The text VGA cog is already stopped. `termToZ80` stays. This bring-up does not call `kbdToZ80` while `gfxMode` is set. The final build calls `kbdToZ80` in that branch.

### Stage 1 checks

Run these in order. Stop on the first failure.

1. Build the current product top. Record the binary size and the Hub bytes left.
2. Load the accepted framebuffer on the target monitor. The picture must hold 720×480 at 60 Hz.
3. Load the bring-up top. Boot must show the text banner. The 8085 must still see the console at 0x80.
4. Enter graphics mode. The scene must hold for 60 seconds with no smear and no grey field.
5. The 8085 must still send bytes to FTDI while the scene runs. Stage 1 leaves the pair as a 6850.
6. Return to text mode. The banner path must run. The 8085 console must work.
7. Repeat the switch ten times. Cog `start` must not fail for lack of a cog.

`vjet_fb_probe.spin` is the check that the stripe rule holds on moving triangles. It is not step 3. The bring-up still has to boot in text and switch.

## Stage 2 — Command path

The 8085 must build scenes without a new Propeller binary for each model. The Propeller does not parse STL or OBJ for each frame. A cooker on CP/M or on the Mac converts the file once.

Stage 1 steps 3 to 5 stay open. The cube harness starts the maths trial. The command cog waits for the bring-up switch, because that flag sits on the ACIA cog.

### Cube harness

`src/lib_vjet/vjet_fb_cube.spin` uses the framebuffer cogs. The mesh has 8 vertices and 12 triangles. Far faces are drawn first. RES draws the resident mesh. STR draws the same faces from a stream table. The label switches about once a second.

The stream record is six signed pixels and one colour word. That is 14 bytes on the wire. Twelve triangles are 168 bytes. The harness keeps each pixel in a long so the sign survives. The program compiles to 7520 bytes. It is not loaded. `blend` stays clear.

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

Text mode and graphics mode do not share the screen. A label on the picture is a text shape. `demo/vjet_test.spin` already draws one with `gl.text_centered` and `hexfont.spin`.

The product path uses 0x80 and 0x81 in both modes. `PORT_VJET` stays a constant. No cog decodes 0xC0. There is no A6 test. P24 and P25 stay with the ACIA cog.

In text mode the pair is the 6850. Status and control are 0x80. Data is 0x81. In graphics mode a Hub flag selects the table below on the same match.

| Access | Graphics meaning |
|--------|------------------|
| 0x80 write | Command |
| 0x81 write | Payload byte into the command FIFO |
| 0x80 read | Graphics status. Room, mode, overflow, and key ready. Not `acia_status`. |
| 0x81 read | Next PS/2 key, or 0 when the key FIFO is empty |

The graphics path releases `/WAIT` on every exit, including an unknown command. It does not fall into `receive_command`, `transmit_status`, or `sync_irq`. A payload of `$03` must not master-reset the console FIFOs. The new instructions must `fit` in the cog. No Hub operation sits between `waitpne` and `waitpeq`.

Cog 0 writes the mode flag. The ACIA cog only reads the flag. Enter text is a command. The ACIA cog stores that request in its own Hub byte. Cog 0 reads the byte, restores text, and clears the mode flag.

The draw cog is the only consumer of payload bytes. It does not exist until graphics mode has started.

The pair is still a 6850 until the flag is set. Stage 1 does not send the enter sequence. Stage 1 uses the chord and leaves the pair as a 6850.

On entry the cog saves `acia_config` and holds `/INT` inactive. On Enter text the cog restores `acia_config`. The program sends `ei` only after the status read says text mode.

The program does not call BDOS character I/O while the flag is set. Those calls expect a 6850. CF disk ports are separate.

A second window is the worse fit on this machine. The BIOS interrupt already owns 0x80 whenever `/INT` is active. One pair, with `/INT` held off, is the command path. Leave 0xC0 unused.

### Command set to try

Keep the first set small. Multi-byte values are little-endian on 0x81. A write to 0x80 selects the command. Following writes to 0x81 are the payload.

| Command | Payload | Effect |
|---------|---------|--------|
| Enter graphics | none | Same switch as stage 1. Ignored during XMODEM. Stage 1 uses the chord only. |
| Enter text | none | Reverse switch. Also the recovery command. |
| Clear | colour word | Empty both lists to that colour. |
| Load mesh | count, then cooked bytes | Store one resident mesh. Reject the load if Hub cannot hold it. |
| Set pose | yaw, pitch, roll, scale | Draw cog uses this on the resident mesh. |
| Stream frame | count, then screen triangles | Replace the dynamic frame. No resident mesh. |
| Draw | none | Draw cog flips at the next front porch. |
| Text | x, y, scale, count, then bytes | One text shape from `hexfont.spin`. |
| Status | none | Read on 0x80 while the flag is set. FIFO room, mode, overflow, list room, and key ready. |

The draw cog shifts pixel integers to 16.16 before `gl.triangle`. The 8085, or a CP/M cooker, owns the projection.

`gl.polygon` is only for one convex face the host has already clipped. The stream primitive is `gl.triangle`.

Colour values stay in the packed word the renderer already reads. A stripe colour is a pair whose high byte is the low byte minus $55. The cooker maps its colour byte to that word.

### Who runs the maths

Try both paths on one cube. The cube is 8 vertices and 12 faces.

1. Resident mesh. The draw cog spins it from `Set pose`.
2. Stream frame. A Spin table pretends to be the 8085 and sends 12 projected triangles.

On a miss, skip the flip and set the overflow bit. Record which path meets the frame for 12 faces and for a larger cooked file.

The product library will expose both. The default for a small file is the resident mesh. The default for a file that does not fit is the stream frame.

### GSX

GSX is CP/M graphics by BDOS call 115 (`C = 73h`, `DE` = parameter block). Coordinates are signed 16-bit values. Source: [GSX notes](https://www.seasip.info/Cpm/gsx.html) and the GSX programmer guide ([PDF](http://www.z80.eu/downloads/gsx-pgr.pdf)).

A full GDOS is a large CP/M piece. RC2014 users do not boot that stack today. GSX is the compatibility coat on a small library.

Map a subset after the port commands are stable.

| GSX function | UX command |
|--------------|------------|
| 1 Open workstation | Enter graphics. Return width 256 and height 240. |
| 2 Close workstation | Enter text. |
| 3 Clear | Clear. |
| 5 Escape 2 | Enter graphics. |
| 5 Escape 3 | Enter text. |
| 6 Polyline | One `gl.line` per segment. Reject the call when the list would overflow. |
| 9 Filled polygon | Convex only. The CP/M side splits or rejects a concave outline. |
| 11 GDP bar | `gl.box`. |
| 8 Text | `gl.text` when the font is linked. |

Other GSX functions return a safe empty result. The driver runs on the 8085. The Propeller does not implement BDOS.

### ReGIS

ReGIS is an ASCII graphics language on a serial console. The local reference is [feilipu/ReGIS](https://github.com/feilipu/ReGIS). The 3D matrix helpers in that tree run on the sender.

Do not parse ReGIS on the Propeller. The sender emits `Stream frame` or `Set pose`.

### Master System and MSX

The port pair is the idea to keep. The tile engine is not VECTORJET. Source: [Master System architecture](https://www.copetti.org/writings/consoles/master-system/).

Borrow these habits only:

- Two I/O addresses, control then data.
- A status read that tells the CPU when the device can take more bytes.
- Updates take effect on the next frame.

### Stage 2 checks

1. Count the Hub bytes of the stage 1 binary. State the largest resident mesh and the largest display list that still link.
2. Count the bytes of one `gl.triangle` and one `gl.polygon` in a real list.
3. Time `/WAIT` with the mode flag clear and with it set. Text mode must still boot and run `DIR`. With the flag set, `/INT` stays inactive.
4. Show the resident cube and the streamed cube. Record the frame time for each. Show one text shape on the same picture.
5. Overflow on purpose. The status bit must set. The list must stay sealed.
6. Fill the command FIFO. The 8085 must still read keys from 0x81. The return chord must still run.
7. Issue Enter text from 0x80 and from the key chord. Both must restore the 6850 and the text console.
8. Start an `XMODEM.COM` receive on 0x80. The mode must stay text until the transfer ends.

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

The first demo is a `.COM` that loads one cooked cube, opens graphics, spins the pose, and closes on a key. Assemble with `z88dk-z80asm -m8085` inside the Ubuntu container.

### Cooker

Accept ASCII STL, binary STL, and OBJ. Write a cooked mesh file the `.COM` can read from the CP/M disk.

Rules for the cooker:

- STL facets become triangles.
- A convex OBJ face becomes one polygon record. A concave face is split on the host.
- Weld vertices that share the same coordinates.
- Attach the colour byte from the solid name, the OBJ group, or a command-line value.
- Print the vertex count, the face count, and the cooked size.
- Refuse a file that exceeds the Hub limit recorded in stage 2.

The Propeller never sees the STL text.

### Transfer

`xget` is the shell command. It receives one XMODEM-128 checksum file onto the FAT volume. The host sends with the checksum. There is no `hget`.

After `cpm` starts, `XMODEM.COM` sends and receives on the CP/M drive. That program uses the CRC.

Load the `.COM` and the cooked file with `xget` or with `XMODEM.COM`. During the transfer the pair stays a 6850. The graphics meaning starts only after `vjet_open`.

The Propeller 6-pin header is the programming port. The transfer uses the console pair.

### GSX driver

Write the subset driver only after `vjet_open` and `vjet_stream` work in the demo. A program that needs 3D calls the library. It does not go through GSX.

## Ordered work

Do the rows in order. A later row waits for the exit text of the row above.

| Step | Work | Exit |
|------|------|------|
| 1 | Measure the product binary and the free Hub. | A written size note. |
| 2 | Load the accepted framebuffer on the target monitor. | 720×480 at 60 Hz. The stripe picture accepted. |
| 3 | Bring-up top. Text boot, Control-G into the framebuffer, draw cog, three render cogs. | 60 s stable scene. FTDI still moves. |
| 4 | Return path and Ctrl+Alt+Del back to text. Ten switches. | Text console works after each return. |
| 5 | Promote the switch into the product top. Boot remains text. | Same checks on `ux_module.spin`. |
| 6 | Measure list bytes and `/WAIT`. | Numbers recorded in this file. |
| 7 | Mode flag on the existing 0x80 match. Graphics status on a read of 0x80. Handler must `fit`. | `DIR` works in text mode. `/INT` stays inactive in graphics mode. |
| 8 | Cube, resident and streamed. | Frame-time note. Overflow bit proven. |
| 9 | Freeze the command bytes. | A version byte in the status block. |
| 10 | CP/M library, cooker, and cube `.COM` for `8085-cf-acia`. | Cube spins. A key returns to the CCP. |
| 11 | GSX subset driver. | Open, clear, bar, convex fill, close. |

Status on 17 Oct 2026. Steps 1 and 2 are done. The two demos are `demo/vjet_test.spin` and `demo/vjet_fb.spin`.

The bring-up compiles to 20408 bytes. It keeps 10 content lines. EEPROM on the bench holds that image. The serial banner was `UX Module Initialised`, then the 8085 prompt. The monitor check for step 3 is still open. Steps 4 and 5 stay open.

The cube harness is the start of stage 2. The bring-up store budget stays in Stage 1. The accepted variables are 23776 bytes. The command bytes are not frozen. The ACIA cog is unchanged.

## Risks

| Risk | What to do |
|------|------------|
| Grey or smeared picture | Stay in stage 1. Compare `demo/vjet_fb.spin` on the same monitor. |
| Hub too small for the accepted buffers | A smaller bring-up store. Do not shrink the accepted renderer to force the link. |
| Graphics path too long for the cog | Shorten the handler. Do not add a bus cog. Do not open 0xC0. |
| Draw cog misses the frame | Stream fewer triangles, or move projection to the 8085. A late framebuffer repeats. |
| BIOS ISR during graphics | Hold `/INT` inactive. The program stays in `di` until status says text mode. |
| Graphics mode with no exit | Return chord, Enter text, Ctrl+Alt+Del, and backplane `/RESET` stop the framebuffer before `wmf.init`. |
| XMODEM mistaken for commands | Ignore the chord and the enter sequence while a transfer is active. |
| Two writers of the mode flag | Cog 0 writes the flag. The ACIA cog writes only the Enter-text request. The draw cog writes only the display list. |
| Stripe assumed for every colour pair | Only a high byte of low minus $55 stripes. Any other pair stays solid. |

## Sources

| Document | Use |
|----------|-----|
| `3D_PROCESS_LIB_VJET.md` | Repair history and the probe load |
| `ARCHITECTURE_UX_MODULE.md` | Clock, cogs, ACIA, text path |
| `ARCHITECTURE_LIB_VJET.md` | Display list, PLL, framebuffer |
| `.agents/skills/module-ux/SKILL.md` | Cog 0 rules, pump, XMODEM |
| `.agents/skills/library-vjet/SKILL.md` | List layout and VGA rules |
| `.agents/skills/hw-ux-pcb/SKILL.md` | Pin map and 74HC4078 |
| `src/lib_vjet/demo/vjet_fb.spin` | Framebuffer demo |
| `src/lib_vjet/demo/vjet_test.spin` | Original beam-chase demo |
| `src/lib_vjet/vjet_fb_cube.spin` | Stage 2 cube harness |
| `src/lib_vjet/vjet_fb_probe.spin` | Motion and occlusion check |
| `src/acia_rc2014.spin` | Port constants and the wait loop |
| `cpu-8085` skill | 8085 opcodes and stack locals |
| `8085-cf-acia/cpm22bios.asm` | `acia_interrupt` and the 6850 console |
| [GSX](https://www.seasip.info/Cpm/gsx.html) | BDOS 115 and the function list |
| [GSX programmer guide](http://www.z80.eu/downloads/gsx-pgr.pdf) | Digital Research manual |
| [feilipu/ReGIS](https://github.com/feilipu/ReGIS) | ReGIS grammar and sender-side 3D matrices |
| [Master System](https://www.copetti.org/writings/consoles/master-system/) | VDP port pair and tile model |

## Review

An adversarial review checked this plan against the ACIA wait loop, the cog map, `kbdToZ80`, and the display-list calls. A later review checked the stripe rule against arbitrary colour pairs. The sections above already include the changes.

| Point | Change in this plan |
|-------|---------------------|
| A6 test | Closed. The product path does not change the mask. |
| Second bus cog | Removed. P24 stays with the ACIA cog. |
| Mode flag | Cog 0 writes it. The ACIA cog reads it. |
| Graphics status | A read of 0x80 in graphics mode. It does not call `sync_irq`. |
| Hub | The accepted framebuffer does not fit in the bring-up. Step 3 uses a smaller store. |
| Pixels | Shift to 16.16 before `gl.triangle`. `gl.polygon` is one clipped convex face. |
| Stripe | Bit 0 means the $55 step only. Other pairs stay solid. |
| Occlusion | List order. Far shapes are drawn first. There is no depth buffer. |
| GSX | Polyline uses `gl.line`. The CP/M side splits or rejects a concave fill. |
| Chord | Same XMODEM guard as Enter graphics. Handle it before `txCheck`. |
| Recovery | Stop the framebuffer before `wmf.init`. |
| 8085 | Test platform is CP/M-IDE v3.0 `8085-cf-acia`. |
| Grey field | A cold accepted picture and the hot switch are separate results. |
| Other bases | 0xC0 stays undecoded. Do not move graphics to 0x00 or 0x40. |

## Address pair

Text mode and graphics mode do not share the screen. P16–P23 have one owner. Text on the picture is a VECTORJET text shape.

`acia_interrupt` treats 0x80 and 0x81 as a 6850 for the whole time `/INT` is active. A graphics window at 0xC0 would leave that interrupt on the console pair. The session still has to stop the interrupt. One pair, with `/INT` held off and `di` in the program, is enough.

The command path is 0x80 and 0x81, with the meaning switched by the mode flag. `PORT_VJET` remains unused.
