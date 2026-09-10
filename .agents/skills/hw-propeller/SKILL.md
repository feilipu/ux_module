---
name: hw-propeller
description: >
  Parallax Propeller 1 (P8X32A) hardware only: eight cogs, Hub, I/O Port A,
  locks, counters, Video Generator (VCFG/VSCL/WAITVID), clock, EEPROM boot.
  Use for Spin/PASM timing, pins, video, multi-cog design. Never Propeller 2.
  Sources: docs/, pcb/ datasheet, OBEX Propeller 1 tips.
---

# Hardware — Propeller 1 (P8X32A)

**This repository targets Propeller 1 only.** Propeller 2 (P2X8C4M64P and related) is a different chip: smart pins, hub RAM map, Streamer, CORDIC, PASM2, Spin2. Do not apply P2 facts here.

Naming trap: **`P2` in board docs often means I/O pin 2**, not Propeller 2. Prefer “pin P2” vs “Propeller 2” in prose.

Authority order when facts disagree:

1. Tree sources under `src/` (what this board runs)
2. `pcb/P8X32A-Propeller-Datasheet-v1.4.0_0.pdf`
3. `docs/P8X32A-Web-PropellerManual-v1.2.pdf`
4. `docs/Propeller Quick Reference v1.7.pdf`
5. OBEX **Propeller 1** tips — https://obex.parallax.com/code-language/pasm (skip P2-tagged objects)
6. Doc index: `.agents/skills/lang-pasm/references/p1-sources.md`

## Chip model (must keep straight)

| Item | Fact |
|------|------|
| Cogs | 8 identical 32-bit processors, IDs 0–7 |
| Cog RAM | 512 longs; last 16 are special-purpose registers |
| Main RAM | 32 KB shared Hub RAM + 32 KB Hub ROM |
| Hub access | Round-robin; one cog every 16 system clocks |
| Hub instruction cost | 8–23 clocks (sync to access window + 8) |
| I/O | 32 pins; after boot all general-purpose |
| Boot pins | P28 SCL, P29 SDA (EEPROM); P30 TX, P31 RX (host) |
| Spec clock | 80 MHz typical; UX Module runs ~118 MHz (see `module-ux`) |
| Languages | Spin (interpreted) + Propeller Assembly (PASM) |

No interrupts on the Propeller. Event work uses dedicated cogs plus `WAITCNT` / `WAITPEQ` / `WAITPNE` / `WAITVID`.

## Shared resources

**Common (any cog, any time):** I/O pin sense, System Counter (`CNT`).

**Mutually exclusive (Hub):** Hub RAM/ROM, locks, cog start/stop, clock set.

I/O pin final state:

- Direction = OR of all cog direction registers
- Output high if any active cog that drives the pin sets it high
- A stopped cog clears its influence

## Counters and video

Each cog has CTRA/CTRB (FRQ/PHS) and one Video Generator.

Video path (VGA mode used by this board):

1. Start CTRA in a PLL mode (video needs PLLA)
2. Set `VSCL` (PixelClocks / FrameClocks)
3. Set `VCFG` (VMode=VGA, CMode, VGroup, VPins)
4. Feed pixels with `WAITVID Colors, Pixels`

If PLLA is not running, `WAITVID` hangs the cog forever.

VGroup selects pin octets: 0→P0–7, 1→P8–15, 2→P16–23, 3→P24–31. UX VGA uses group 2 (base pin 16). See `hw-ux-pcb`.

## Clock

UX Module top object sets:

```
_clkmode = XTAL1 + PLL16X
_xinfreq = 7_372_800
```

System clock ≈ 7.3728 MHz × 16 ≈ 117.9648 MHz. Timing constants in drivers assume this. Changing the oscillator requires `_xinfreq` and VGA pixel-rate retune.

## Boot

1. Reset → Cog 0 runs bootloader
2. Host on P30/P31 may download to RAM / EEPROM
3. Else load 32 KB image from I2C EEPROM on P28/P29
4. Cog 0 runs Spin interpreter on the loaded image

UX EEPROM pins are **swapped vs the usual Propeller diagram** so only the EEPROM is visible at boot. See `hw-ux-pcb` and `src/i2c.spin`.

## Propeller 2 features that do not exist here

No smart pins, no `HUBSET` clock API as on P2, no hub exec / LUT exec, no Streamer, no CORDIC coprocessor, no Port B (`OUTB`/`DIRB`/`INB` as P2), no 64-bit system counter builtins from Spin2.

P1 video = per-cog Video Generator + `WAITVID` + CTRA PLL. That is the path UX and VECTORJET use.

## Agent rules

1. Count cogs before starting another (`cognew` returns −1 when none free).
2. Cross-cog data larger than one long needs locks or a single-writer protocol.
3. Interleave non-hub PASM with hub ops when Hub bandwidth matters.
4. After self-modifying PASM (`MOVI`/`MOVS`/`MOVD`), execute at least one other instruction before the patched line runs.
5. Conditional jumps are predicted taken; not-taken costs an extra 4 clocks.
6. If a source mentions Propeller 2, treat it as foreign unless the task is explicitly about excluding it.

## Related

- Spin: `lang-spin`
- PASM: `lang-pasm` (+ `references/p1-opcodes.md`)
- Tools: `tool-propeller`
- Board pin map: `hw-ux-pcb`
- Firmware topology: `module-ux`
- VECTORJET: `library-vjet`
