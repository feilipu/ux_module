---
name: lang-spin
description: >
  Propeller 1 Spin only (P8X32A): CON/VAR/OBJ/PUB/PRI/DAT blocks, cognew of
  Spin vs PASM, Hub mailbox via PAR, VAR vs DAT, house style in src/*.spin.
  Use when writing or reviewing Spin. Not Spin2. Sources: docs/ Manual and
  Quick Reference; lang-pasm/references/spin-pasm-bridge.md.
---

# Language — Propeller 1 Spin

**Chip: P8X32A (Propeller 1) only.** Do not use Spin2 syntax (`HUBSET`, smart-pin builtins, `^@`, P2 debug, etc.).

Spin is bytecode interpreted in a cog. Hot paths are usually PASM in `DAT`; Spin wires objects and Hub memory.

Quick reference: `docs/Propeller Quick Reference v1.7.pdf`. Full language: `docs/P8X32A-Web-PropellerManual-v1.2.pdf`. Bridge to PASM: `.agents/skills/lang-pasm/references/spin-pasm-bridge.md`.

## File blocks (order agents must respect)

| Block | Role |
|-------|------|
| `CON` | Compile-time constants and enumerations |
| `VAR` | Hub RAM variables (byte/word/long) |
| `OBJ` | Nested objects (`name : "file"`) |
| `PUB` | Public methods (API) |
| `PRI` | Private methods |
| `DAT` | Data tables and/or PASM |

A file may repeat `CON`/`VAR` sections. The **top object** of a PropellerIDE build is the foreground file at compile/upload time. For this product that is `src/ux_module.spin` (or a lib_vjet test top).

## Clock constants (top object only)

```
CON
  _clkmode = XTAL1 + PLL16X
  _xinfreq = 7_372_800
```

Only the top object’s `_clkmode` / `_xinfreq` (or `_clkfreq`) set the chip clock. Child objects must not redefine them unless they are themselves a top object (tests).

## Objects and hierarchy

```
parent
  child : "module_name"     ' loads module_name.spin
  child.method(args)
  child#CONSTANT            ' CON from child
```

UX Module hierarchy lives in `module-ux`. Do not flatten Parallax objects into the top file without a reason.

## Starting work on another cog

```
cognew(spinMethod(@args...), @stack)   ' Spin method + Hub stack
cognew(@pasmEntry, parameter)          ' PASM; PAR gets Hub mailbox address
cogstop(id)
```

`cognew` returns cog ID 0–7, or −1 on failure. House style often stores `cog := cognew(...) + 1` so 0 means “not running”.

Every Spin cog needs its own Hub stack long array sized for locals and call depth.

**Spin does not call PASM as a subroutine, and PASM does not call Spin `PUB`s.** Share Hub longs only (see `lang-pasm` bridge reference).

## Memory

| Form | Meaning |
|------|---------|
| `byte[addr]`, `word[addr]`, `long[addr]` | Typed Hub access |
| `@symbol` | Hub address of symbol |
| `string("...")` | Address of zero-terminated string in Hub |
| `BYTEFILL` / `WORDMOVE` / … | Block fill/copy |

Spin and PASM share Hub RAM. Document who writes each shared long.

## VAR vs DAT (OBEX tip)

| | `VAR` | `DAT` (data) | `DAT` (PASM) |
|--|-------|--------------|--------------|
| Where | Hub RAM | Hub RAM | Loaded into Cog RAM on `cognew(@entry,…)` (first 496 longs) |
| Per object instance | **Separate** copy | **One** shared copy | One image; each started cog gets its own Cog RAM copy |
| Init | Cleared to 0 | Can set `long`/`word`/`byte` values | Code + `long` constants; `res n` for cog scratch |
| Typical use | FIFOs, cog IDs, per-instance state | Shared tables, font blobs, single-driver constants | Driver entry points |

Rules of thumb (OBEX + this tree):

1. Prefer `VAR` for per-instance driver state (`rx_head`, `cog`, buffers).
2. Use shared `DAT` longs when every instance must see the same cell, or for PASM immediates filled from Spin (`long 0-0` then assign before `cognew`).
3. Passing `@var` in `PAR` is how PASM reaches Hub `VAR` blocks (ACIA, UART, VGA).
4. Object scope ≠ cog scope. Two Spin cogs from the same object share that object’s `VAR`s automatically.

## Control flow notes

- `REPEAT` / `REPEAT WHILE` / `REPEAT UNTIL` / counted `REPEAT`
- `CASE` with ranges (`10..15`) and `OTHER`
- `ABORT` unwinds to the nearest catcher; display-list builders in lib_vjet use this on overflow
- Booleans: non-zero is true; logical ops promote non-zero to −1
- `not` is boolean unary (result 0 or −1) and binds tighter than `&`. `if not x & mask` means `(not x) & mask`. For a bit field write `(x & mask) <> field`. `!` is bitwise invert (`acia_status &= !flag`).

## House style in this repo

1. Keep Spin for orchestration; leave scanline / bus bit-bang in PASM.
2. Match neighbouring comment density; do not narrate obvious assignments.
3. Import pin and port constants from the owning object (`acia#PORT_80`, `i2c#SDA_PIN`) instead of duplicating magic numbers.
4. Prefer existing buffer/mask patterns (`BUFFER_LENGTH` power of two, `BUFFER_MASK`) when adding FIFOs.
5. Count and check methods (`rxCount`, `rxPeek`, `txCheck`, `txSpace`) must not change status bits. ACIA status bits are PASM-only. `tdreHold` writes `tdre_hold`, not `acia_status`. `tx` / `rx` abort on `req_parse_idle` / `req_master`. Do not add `txFlush`/`rxFlush` that write both FIFO ends. Do not add XON/XOFF (`module-ux`).
6. Prose in new comments and docs follows `style-ste-writing` (STE-flavored).

## Propeller 2 / Spin2 — reject

If a snippet uses Spin2-only forms (`HUBSET`, `PINWRITE`, `COGATN`, `debug(`, P2 registry builtins), it is the wrong chip. Translate to P1 Spin+PASM or discard.

## Related

- Hardware model: `hw-propeller`
- Assembly: `lang-pasm` (+ `references/spin-pasm-bridge.md`)
- Tools: `tool-propeller`
- Product wiring: `module-ux`
