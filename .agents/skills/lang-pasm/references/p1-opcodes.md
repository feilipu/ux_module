# Propeller 1 (P8X32A) — PASM instruction card

Authority: `docs/Propeller Quick Reference v1.7.pdf`. Full prose: Manual v1.2 Chapter on Propeller Assembly.  
**Not** Propeller 2 / PASM2.

## Instruction encoding (mental model)

```
Label   Condition   INST   Dest, 〈#〉Src   Effects
```

| Field | Width | Notes |
|-------|------:|-------|
| Dest (D) | 9-bit cog address | Register 0–511 (specials in the top of cog RAM) |
| Src (S) | 9-bit | Register **or** `#immediate` (0–511 only) |
| Condition | optional | Default = always |
| Effects | optional | `WC` `WZ` `WR` `NR` |

### Immediate size (pitfall)

`#n` fits in **9 bits** (0…511). Larger constants must live in cog RAM:

```
myconst         long    1_000_000
                mov     temp, myconst
```

Self-mod placeholders often written `0-0` (equals zero; patched later with `MOVS`/`MOVD`/`MOVI`).

## Timing (quick ref footnotes)

| Class | Clocks |
|-------|--------|
| Most ALU / `JMP` / `MOV` / … | **4** |
| Conditional jump **taken** (`DJNZ`/`TJZ`/…) | **4** |
| Conditional jump **not taken** | **8** |
| Hub ops (`RD*`/`WR*`/`LOCK*`/`COG*`/`CLKSET`) | **8…23** (sync to hub window + 8) |
| `WAITCNT` / `WAITPEQ` / `WAITPNE` | **6+** until event |
| `WAITVID` | **4+**; pixel handoff needs ~6–7 clocks between frames |

Interleave two 4-clock cog ops between hub ops when Hub bandwidth matters.

## Effects

| Effect | Meaning |
|--------|---------|
| `WC` | Write C from the op’s C result |
| `WZ` | Write Z from the op’s Z result |
| `WR` | Write destination (default for most ALU) |
| `NR` | Do **not** write destination (flags-only / compare style) |

## Conditions (subset agents use most)

| Condition | Meaning |
|-----------|---------|
| `IF_Z` / `IF_E` | Z set |
| `IF_NZ` / `IF_NE` | Z clear |
| `IF_C` / `IF_B` | C set |
| `IF_NC` / `IF_AE` | C clear |
| `IF_A` | above (!C & !Z) |
| `IF_BE` | below or equal (C \| Z) |
| `IF_C_AND_Z` … | combined; see quick ref full grid |

Predicted **taken**. Not-taken costs the extra 4 clocks.

## Instruction groups

### Arithmetic / logic (typically 4 clocks, WR default)

`ABS` `ABSNEG` `ADD` `ADDABS` `ADDS` `ADDSX` `ADDX`  
`SUB` `SUBABS` `SUBS` `SUBSX` `SUBX`  
`SUMC` `SUMNC` `SUMZ` `SUMNZ`  
`NEG` `NEGC` `NEGNC` `NEGZ` `NEGNZ`  
`AND` `ANDN` `OR` `XOR`  
`MIN` `MAX` `MINS` `MAXS`  
`CMP` `CMPS` `CMPX` `CMPSX` `CMPSUB` (often `NR`)  
`TEST` `TESTN` (`NR`)

### Shifts / rotates

`SHL` `SHR` `SAR` `ROL` `ROR` `RCL` `RCR` `REV`

### Move / patch

`MOV` `MOVS` `MOVD` `MOVI` `MUXC` `MUXNC` `MUXZ` `MUXNZ`

### Flow

`JMP` `JMPRET` `CALL` `RET` `DJNZ` `TJZ` `TJNZ` `NOP`

`CALL #label` writes the return address into `label_ret`’s S field. Local labels start with `:`.

### Hub / system (8…23)

`RDBYTE` `RDWORD` `RDLONG` `WRBYTE` `WRWORD` `WRLONG`  
`LOCKNEW` `LOCKRET` `LOCKSET` `LOCKCLR`  
`COGID` `COGINIT` `COGSTOP` `CLKSET`

### Wait / video

`WAITCNT` `WAITPEQ` `WAITPNE` `WAITVID`

`WAITPEQ dest, mask WR` → destination becomes **`dest + mask`** (not a copy of `INA`). ACIA `/WAIT` loop: [acia-wait.md](acia-wait.md). Also `obex-pasm.md`.

## Directives

| Directive | Rule |
|-----------|------|
| `ORG 〈addr〉` | Set cog compile pointer (usually 0) |
| `FIT 〈addr〉` | Assert prior code/data fits below addr (often 496) |
| `long` / `word` / `byte` | Initialized data in the cog image |
| `RES n` | Reserve *n* longs **after** all initialized data |

**`RES` must follow initialized `long`s** in the cog image. Putting `RES` in the middle leaves holes the assembler may not treat as you expect; house style keeps `RES` at the end (before `FIT`).

## Special registers (top of cog RAM)

Agents touch often: `PAR` `CNT` `INA` `OUTA` `DIRA` `CTRA` `CTRB` `FRQA` `FRQB` `PHSA` `PHSB` `VCFG` `VSCL`.

`PHSx` reads are source-operand only; RMW uses the last written value, not the live accumulator.

## Forbidden on P1 (Propeller 2 / PASM2)

Do not emit or “upgrade” to:

`WAITX` `WAITCT1`… `DRVL` `DRVH` `DRVNOT` `FLOAT` `PINW` `WRPIN` `WXPIN` `WYPIN`  
`##immediate` (P2 long immediate) `AUGS` `AUGD` `HUBSET` `COGATN` `POLLATN`  
`DIRB`/`OUTB`/`INB` as P2 port B, LUT exec, smart-pin registers, `SKIP`/`EXECF`, etc.

If an OBEX or web snippet shows those mnemonics, it is **P2** — discard for this repo.
