# Beam-chase tear: review findings and remediation options

Two independent adversarial reviews of `src/lib_vjet` at `c80e076`, plus the six repairs
already recorded as rejected. This note states the fault mechanism both reviews agree on,
where they diverge, the remediation options with their measured costs, and the other
defects found on the way.

No patch from either review has been applied. This note records the findings and the
options only.

## Symptoms

On the beam-chase products the picture tears on doubled scanlines: an interlace comb
("mosquito") effect on some lines, and lines that never receive the current frame's
content at all. The damage is banded - a top band of roughly 20 lines and a second band
about 30 percent down the screen - rather than uniformly distributed.

## What the six rejected repairs prove

| Bytes | Change | Result |
| ----- | ------ | ------ |
| 16864 | Hub edge cache and field box | Horizontal stripes. Scene-specific cut. |
| 16604 | `gl.pace` | About 12 fps. Tear stayed. |
| 16532 | Cog-RAM `linebuf` | Vertical rainbow bars. |
| 16536 | Hub scratch, skip if late | Interlace comb and sparkle lines. |
| 16528 | Paint during `:linewait` | Keys dead. |
| 16528 | Wait then always copy | Double line feed. Text mode stuck. |

Every one of them changed pacing, caching, or copy placement. None of them reduced the
renderer's per-line work, and none of them stopped the renderer writing a buffer slot the
video cog was reading. Slowing the renderer to 12 fps did not remove the tear, which alone
shows the fault is not a rate the renderer can be paced out of.

## The mechanism (agreed by both reviews)

The video cog owns the raster and publishes the logical line it is displaying
(`VJET_vUXM_vga.spin:155-159`): eight Hub line slots selected by line `& 7`, **each slot
scanned twice** (`tileCounter = #2`), with the line number written to the sync indicator.

The renderer polls that published value in `:linewait` (`VJET_vUXM_rendering.spin:358-385`).
The guard is an **upper bound only**. `d0 = currentscanline + total_cogs - LINE_BUFFERS`
is the far edge of the lead the renderer may hold, and `if_a` releases the renderer as soon
as the published line passes `d0`. There is **no lower bound**: a renderer that has fallen
behind is released immediately, at whatever beam position it happens to occupy, and paints
its slot right there. Two outcomes follow, and they are the two reported symptoms:

- **Beam inside the slot it is writing** - the `:fillp` and span `wrlong`s interleave with
  the video cog's `rdlong`s of the same slot, so the line is half old and half new: the
  interlace comb ("mosquito").
- **Beam already past the slot** - the paint completes, but that line has already been
  displayed with the previous frame's occupant: the missed scanline.

A render cog takes every `total_cogs`-th logical line, so with three cogs it has **three
logical lines (about 22 600 clocks)** between paints, in which it must finish
`paint(M) + build(M + total_cogs)`. The lead is a **one-shot buffer, not a budget**: with
eight slots and three cogs the renderer may hold about seven lines of lead, and once a
sustained deficit drains that lead inside a frame it cannot be recovered, because
`:linewait` can only block a cog that is early - it cannot push a late cog forward.

Measured work against that budget:

- **Build** (`:build_spans`, `VJET_vUXM_rendering.spin:249-338`) re-walks the entire
  display list for **every line**. Per in-range trapezoid shape it reads the trap height,
  two slopes, and calls `satmul` twice (`:285-300`, `satmul` at `:691-713` - sixteen add
  steps, roughly 70-150 clocks typical, 300 worst).
- **Paint** (`:paint` at `:203-247`) is a 64-long fill plus up to `SPAN_MAX` (24) span
  writes, plus per-pixel text bytes.

That is roughly **2.0 to 4.5 lines of work against a 3.0-line budget**, which is why the
damage is banded: the bands are the workload peaks, not two separate faults.

The frame-start path makes the top band worse. `if_z_and_nc jmp #new_frame` at `:359-361`
fires for a late cog during logical line 0 and re-runs the first three paints, consuming
most of the lead at the top of each frame.

## Where the two reviews diverge

Both agree on the mechanism above and on the shape of the cure. They differ on the
dominant contributor, and therefore on the cheapest sufficient fix.

**Review A - per-line work is the deficit.** The display-list walk paying a `satmul` chain
per consumed trap per shape is the overrunner. Fix by emitting **split-trap display lists**
in the builder (`src/lib_vjet/VJET_v01_displaylist.spin`, general-triangle branch): each
general triangle becomes two one-trap shapes, so the renderer's per-line walk costs one
current-trap pair per shape instead of a consumed-trap multiply chain. Build falls from
about 2.1 lines to about 1.0-1.2. Renderer cost **0 bytes**; builder image +140 bytes; each
general triangle's list entry grows 48 -> 72 bytes. Validated by compiling with OpenSpin
1.00.81 and by **1 075 780 randomised line-walks comparing old and new lists: zero span
mismatches, worst pixel delta 0**.

**Review B - the lead is stolen at frame start, and the deficit then cascades.** Fix by
**double-buffering the slot bank**: two 2 048-byte banks after the eight VGA slots, a
displayed-bank word, and one release byte per render cog. The video cog flips banks only at
the front porch and only if every cog released the bank it painted; a late cog writes the
other value, the flip fails, and the display holds the current frame for one more frame.
**+208 bytes of code** (measured on `vjet_test` 6404 -> 6612 and `vjet_acia` 8036 -> 8244).
The tear becomes a held frame rather than a torn one.

These are complementary rather than competing: A reduces how often a cog goes late, B makes
lateness invisible when it happens. Review A explicitly rejects widening the line ring
(`LINE_BUFFERS` 16), because that only moves the same race further out and a late cog still
writes a live slot - B differs in that the consumer, not the renderer, decides what is
displayed.

## Remediation options

| Option | Change | Cost | Effect | Risk |
| ------ | ------ | ---- | ------ | ---- |
| **A** | Text out-of-bounds clamp, bring-up build fix, and the two-instruction one-shot frame-start restart | +10 bytes, two instructions | Removes a real overflow bug, restores the build, recovers 3-4 lines of lead at the top | Low - independent of the tear fix |
| **B** | A + split-trap builder patch (Review A) | Renderer 0 bytes, builder +140 bytes, list entries +24 bytes/triangle | Shrinks the per-line work so the renderer stops going late | Proven pixel-identical; worst-case hub timing may narrow the bands rather than close them |
| **C** | A + frame double buffer with release/acquire (Review B) | +208 bytes code, 2 x 2048-byte banks | Tear becomes a held frame | Holds a frame when a cog is late: stutter instead of tear |
| **D** | B + C | Sum of the above | Both properties | Pays memory and code for both |
| **E** | Span-record ring decoupling build from paint (both reviews' robust design) | About 30-40 renderer cog longs; needs Hub room that does not exist today | Removes the coupling entirely: build early in the frame, paint from the ring | Requires reclaiming Hub (the top currently exceeds Hub by 203 longs without `-u`) |

**Recommended sequence:** A, then B, measuring the bands after each. Reach for C or E only
if the bands persist. Both reviews are explicit that worst-case timing may narrow the bands
without closing them, so re-measurement after each step is not optional.

## Other defects found

1. **HIGH - the bring-up top does not compile.** `src/ux_module_vjet.spin` (around line
   1132) fails to build with OpenSpin 1.00.81, so the product's primary artefact cannot be
   rebuilt from the tree with the documented tool. Both reviews found this independently.
   The EEPROM image at `6615776` cannot be reproduced from the current sources.
2. **HIGH - the guard's missing lower bound** (`VJET_vUXM_rendering.spin:366`). The tear
   mechanism above.
3. **MEDIUM - the text painter writes past the slot end** (`VJET_vUXM_rendering.spin:415-486`).
   `poly_left` is bounds-checked only at `:chrloop` entry, but glyph writes reach
   `poly_left + 7 x pxwidth`, so a glyph near `WIDTH` writes up to 27 bytes into the next
   slot. At pxwidth 2 and 4 the glyphs are also dotted, columns stepping every pxwidth-th
   pixel, rather than stretched. Both reviews found this independently; the clamp is
   considered high confidence.
4. **LOW - mid-frame list mix on restart** (`VJET_vUXM_rendering.spin:359-361`). The
   `if_z_and_nc` restart fires for a late cog during logical line 0; one cog can begin the
   new list while the others finish the old frame. Self-limiting to one frame, and only
   reachable once a cog is already late.
5. **LOW - undocumented start delay.** `render.start` uses `repeat 10000`
   (`VJET_vUXM_rendering.spin:87`) to serialise DAT-parameter reuse between cog starts.
   It works; it deserves a named constant and a comment so it is not optimised away.
6. **INFO - init-code overlay.** `a0`/`d0`/`d1` double as scratch registers after init
   (`:99-102`). Documented in-file, safe, fragile under edit.

## What would settle the disagreement

- **Review A's falsifier:** apply the split-trap patch and watch the top band. If it narrows
  but persists, the paint rather than the build is the remaining overrunner and option E is
  required.
- **Review B's falsifier:** instrument the release path and record, per frame, how many cogs
  release late. If cogs release on time yet the tear persists, the mechanism is wrong and
  the slot write itself is at fault.

Both are board experiments: there is no Propeller emulator in the review environment, so all
cycle figures are static or simulated rather than measured on hardware.
