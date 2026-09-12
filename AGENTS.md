# ux_module — agent instructions

Project rules for AI agents working in this tree.
Skill layout follows the z88dk `.agents/skills` pattern. Prose rules come from the z88dk STE skill (`style-ste-writing`).

## Canonical skill root (do not double-read)

| Path | Role |
|------|------|
| **`.agents/`** | **Only** real tree of agent skills |
| **`.grok`** | Symlink → `.agents` (Grok discovery) |
| **`.claude`** | Symlink → `.agents` (Claude discovery) |

**Rules**

1. Prefer paths under **`.agents/skills/...`** in prose and links.
2. Before loading a skill file, **resolve realpath**. If that realpath was already loaded via `.grok` or `.claude`, **do not read it again**.
3. Skill `name` values are unique (`hw-propeller`, `lang-spin`, …).
4. Do **not** add a second full instruction set as root `CLAUDE.md` that duplicates this file or the skills.
5. This **`AGENTS.md`** is the only always-on project rules file at the repo root.

Skills load **on demand** when the task matches their `description`.

**Context budget**

1. Do **not** bulk-read every skill under `.agents/skills/`.
2. Do **not** open every PDF under `docs/` “just in case.”
3. The index tables below are enough to *choose* a skill; open a `SKILL.md` only when that topic is in scope.
4. Architecture prose for humans: `ARCHITECTURE_UX_MODULE.md`, `ARCHITECTURE_LIB_VJET.md`. Prefer those for orientation; prefer skills for edit rules.

## Primary sources

| Audience | Location |
|----------|----------|
| Agents (edit rules) | `.agents/skills/<name>/SKILL.md`, this file |
| Agents + humans (architecture) | `ARCHITECTURE_UX_MODULE.md`, `ARCHITECTURE_LIB_VJET.md` |
| Hardware / language authority | `docs/`, `pcb/*Propeller*`, `docs/MC6850.pdf` |
| PASM idioms (external) | https://obex.parallax.com/code-language/pasm — index in `.agents/skills/lang-pasm/references/obex-pasm.md` |
| Product overview | `README.md` |
| Code | `src/`, `src/lib_vjet/` |

When docs and tree disagree on **behaviour this board ships**, **the tree wins**. When the tree is silent on chip rules, **datasheet / manual win**. OBEX tips teach idioms; they do not override UX pin maps or ACIA `/WAIT` polarity.

Directory name in older notes may say `doc`; this repo uses **`docs/`**.

## Hard house rules (always)

1. **Propeller 1 only (P8X32A).** Different ISA from Propeller 2. No PASM2/Spin2, smart pins, `WAITX`, `DRVL`, `##imm`, `HUBSET`, Streamer, or CORDIC (`hw-propeller`, `lang-pasm`, `lang-spin`). Skill doc index: `.agents/skills/lang-pasm/references/p1-sources.md`.
2. **Pin `P2` ≠ Propeller 2.** In board/firmware text, `P2` means I/O pin 2 unless the words “Propeller 2” appear.
3. **Prose in STE.** New or rewritten documentation, architecture notes, PR text, error strings, and non-code comments follow **`style-ste-writing`** (STE-flavored unless the user asks for strict). Do not apply STE to code, identifiers, or command syntax.
4. **Top object for upload** is `src/ux_module.spin` for the product firmware. lib_vjet demos use their own top objects under `src/lib_vjet/`. Tools: `tool-propeller`.
5. **Clock:** `_clkmode = XTAL1 + PLL16X`, `_xinfreq = 7_372_800` unless the task is deliberately retuning the oscillator (`hw-propeller`, `module-ux`).
6. **Cog budget is scarce.** Count running cogs before `cognew`. Full UX text path uses most of the eight cogs; VECTORJET needs its own set (`module-ux`, `library-vjet`).
7. **Pin constants** live in the owning module and are imported with `object#CONST` (`hw-ux-pcb`).
8. **ACIA perspective:** Z80 RX ← Propeller `tx_*` FIFO; Z80 TX → Propeller `rx_*` FIFO (`module-ux`).
9. **Spin ↔ PASM:** no nest-calls; Hub + `PAR` only (`lang-pasm` / `spin-pasm-bridge`).
10. **Local omlx helpers** (qwen-coder / gemma-crew) are **not** assumed available in this project. Do not spawn them unless the user says they are enabled.

## Commit hygiene

1. **One subject line. No body.** Commit with a single `-m`.
2. **No attribution trailers.** No `Co-Authored-By:`, no "generated with" footer.
3. Commit only when asked, and never push unasked.

## Skill index

Load only what the task needs. Paths are under `.agents/skills/`.

Each skill lives at `.agents/skills/<name>/SKILL.md`. The directory name is the `name:` field. Flat layout only — no category folders.

### Style (underlying requirement)

| Skill | When |
|-------|------|
| `style-ste-writing` | Any human prose (docs, README slices, PR text, comments). Imported from z88dk STE skill set |

### Hardware

| Skill | When |
|-------|------|
| `hw-propeller` | P8X32A cogs, Hub, video generator, counters, clock, boot |
| `hw-ux-pcb` | UX Module pin map, 74HC4078 decode, ACIA/VGA/PS2/FTDI/I2C |

### Languages (Propeller 1)

| Skill | When |
|-------|------|
| `lang-spin` | Spin blocks, objects, cognew of Spin methods (not Spin2) |
| `lang-pasm` | P1 DAT assembly, WAIT*, hub ops, FIT/ORG; see `references/p1-opcodes.md` |

### Tools

| Skill | When |
|-------|------|
| `tool-propeller` | Build/use OpenSpin + PropLoader (`proploader`) for P1 CLI compile and FTDI upload. Copy compile/load/console from `tools/README.md`. |

### Product and libraries

| Skill | When |
|-------|------|
| `module-ux` | `src/ux_module.spin` and production drivers outside `lib_vjet` |
| `library-vjet` | `src/lib_vjet` VECTORJET display list / render / VGA |

## Provenance

- STE writing skill copied from local z88dk `.agents/skills/style-ste-writing` (ASD-STE100 Simplified Technical English).
- Propeller and UX skills authored for this repository against `docs/`, `pcb/`, and `src/`.
- Cross-check notes (P1 doc list, Spin↔PASM bridge, 9-bit immediates, RES ordering, P1≠P2) folded from a Grok web conversation; **P2 skill files were intentionally not added**.
