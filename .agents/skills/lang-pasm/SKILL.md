---
name: lang-pasm
description: >
  Propeller 1 (P8X32A) Assembly (PASM) only: 9-bit immediates, WC/WZ/WR/NR,
  conditions, hub timing, MOVS/MOVD/MOVI, WAIT*, pin masks, JMPRET, FIT/ORG/RES.
  Use when writing or reviewing DAT assembly in src/*.spin. Never PASM2.
  Sources: docs/ quick ref + Manual; OBEX P1 tips; references/ under this skill.
---

# Language — Propeller 1 Assembly (PASM)

**Chip: P8X32A (Propeller 1) only.** Propeller 2 / PASM2 is a different ISA. Do not mix.

PASM runs from Cog RAM. Entry is usually `DAT` / `org` / label, started with `cognew(@Entry, parValue)`.

| Reference | Path |
|-----------|------|
| Opcode / condition / clocks card | [references/p1-opcodes.md](references/p1-opcodes.md) |
| Spin ↔ PASM mailbox | [references/spin-pasm-bridge.md](references/spin-pasm-bridge.md) |
| Doc index (in-tree + OBEX P1) | [references/p1-sources.md](references/p1-sources.md) |
| OBEX idioms | [references/obex-pasm.md](references/obex-pasm.md) |
| ACIA `/WAIT` loop | [references/acia-wait.md](references/acia-wait.md) |
| In-tree cheat sheet | `docs/Propeller Quick Reference v1.7.pdf` |

## Non-obvious rules (encode these)

1. **S-field immediates are 9-bit** (`#0`…`#511`). Bigger values → `long` in cog RAM, then `mov`.
2. Line shape: `Label  Condition  INST  D,S  Effects` (`IF_Z`, `WC`, `WZ`, `WR`, `NR`).
3. Almost all ops are **4 clocks**; hub and wait ops are longer (see opcode card).
4. **`RES` comes after initialized `long`s** in the cog image; then `FIT`.
5. **Local labels** start with `:`. `CALL`/`JMPRET`/`RET` use the 9-bit S field as the return slot (`label_ret`).
6. Spin and PASM **never nest-call**; they share Hub longs via `PAR` ([spin-pasm-bridge.md](references/spin-pasm-bridge.md)).
7. **P1 ≠ P2.** Reject `WAITX`, `DRVL`, `##imm`, `HUBSET`, smart pins, etc. ([p1-opcodes.md](references/p1-opcodes.md) forbidden list).

## Instruction shape

```
〈label〉  〈condition〉  instruction  dest, 〈#〉src  〈effects〉
```

| Effect | Meaning |
|--------|---------|
| `WC` | Write C |
| `WZ` | Write Z |
| `WR` | Write destination |
| `NR` | Do not write destination |

Default for most ALU ops is write destination without changing flags unless `WC`/`WZ` requested.

## Hub vs cog

| Class | Examples | Clocks |
|-------|----------|--------|
| Cog ALU / branch | `MOV`, `ADD`, `DJNZ`, `JMP` | usually 4 (branch not-taken 8) |
| Hub memory | `RDBYTE` `RDWORD` `RDLONG` `WRBYTE` `WRWORD` `WRLONG` | 8–23 |
| Hub system | `COGINIT` `COGSTOP` `LOCK*` `CLKSET` | 8–23 |
| Wait | `WAITCNT` `WAITPEQ` `WAITPNE` `WAITVID` | 6+ until event |

Put two 4-clock cog instructions between hub ops when Hub bandwidth matters.

## Self-modifying code

`MOVS` / `MOVD` / `MOVI` patch source, dest, or opcode fields. The instruction **immediately after** a patch still fetches the old encoding — insert at least one other instruction before the patched line runs.

Placeholders: `0-0` (zero; often means “patched later”) or Spin-filled `long 0-0` before `cognew`.

## Special registers

| Reg | Use |
|-----|-----|
| `PAR` | Boot parameter (Hub address from `cognew`) |
| `CNT` | System counter |
| `INA` / `OUTA` / `DIRA` | Pin in / out / direction (**Port A only** on P1) |
| `CTRA`/`CTRB`, `FRQA`/`FRQB`, `PHSA`/`PHSB` | Counters / PLL |
| `VCFG`, `VSCL` | Video config / scale |

`PHSA`/`PHSB` are source-only for reads. RMW uses the last written value, not the live accumulator.

## Pin-mask idioms

| Goal | Pattern |
|------|---------|
| Output + high | `or dira, mask` / `or outa, mask` |
| Output + low | `or dira, mask` / `andn outa, mask` |
| Toggle | `xor outa, mask` |
| Float (input) | `andn dira, mask` |
| Sample | `test mask, ina wc` or `wz` |
| Flag-conditioned bits | `muxc` / `muxnc` / `muxz` / `muxnz` |

## WAITCNT / WAITPEQ / WAITPNE

```
mov     timer, TICKS
add     timer, cnt
loop    waitcnt timer, TICKS
        djnz    count, #loop
```

```
waitpeq state, mask     ' until (INA & mask) == state
waitpne state, mask     ' until (INA & mask) != state
```

1. `state` bits outside `mask` → `WAITPEQ` hangs forever.
2. **`waitpeq dest, mask wr` writes `dest + mask`**, not `INA`. ACIA uses this to assert `/WAIT` (P24 1+1 → 0, carry into `/INT`).
3. ACIA loop contract: [references/acia-wait.md](references/acia-wait.md). Do not drop `wr`. Do not Hub-read on the match path.

## CALL / JMPRET

- `call #label` … `label_ret ret`
- `jmpret retReg, #other` — coroutine (`terminal_ftdi.spin`)

## Event loops in this tree

**ACIA:** `WAITPNE` → idle `/INT` refresh (`req_master` poll) → `WAITPEQ … wr` match and `/WAIT` → service RD/WR → `or outa, bus_wait` → `wait_pin_high`. See [acia-wait.md](references/acia-wait.md).  
**VGA:** `WAITVID` scanline loop.  
**FTDI:** `JMPRET` + bit timing.  
**I2C (Spin):** `WAITPEQ(|<scl,|<scl,0)`.

## Agent rules

1. Emit **P1 PASM only**. No PASM2.
2. Keep `FIT` headroom (496 longs before specials).
3. Document PAR Hub layout at `entry`.
4. Update pin masks and `waitpeq` masks together.
5. Never remove ACIA `waitpeq … wr` without another `/WAIT` design. Follow [acia-wait.md](references/acia-wait.md).
6. Prose: `style-ste-writing`.

## Related

- `hw-propeller` — chip model (P1)
- `lang-spin` — Spin side of the bridge
- `tool-propeller` — build/use OpenSpin + PropLoader
- `hw-ux-pcb` / `module-ux` — board + ACIA
- `library-vjet` — render/VGA PASM
