# Spin ↔ PASM bridge (Propeller 1)

Spin and PASM **do not call each other**. They share **Hub RAM**. The mailbox is usually a Hub struct whose address is passed in `PAR`.

## Launch

```
VAR
  long  hubstruct[…]          ' or named fields
  long  stack[64]             ' only for Spin cogs

DAT
entry   org 0
        mov     ptr, par
        rdlong  …
        …

PUB start
  cog := cognew(@entry, @hubstruct) + 1     ' PASM cog; PAR = @hubstruct
  cog := cognew(spinMethod, @stack) + 1     ' Spin cog; needs Hub stack
```

| Launch | Second arg | Meaning |
|--------|------------|---------|
| `cognew(@pasmLabel, hubPtr)` | Hub address | Loaded into that cog’s `PAR` |
| `cognew(spinMethod, @stack)` | Stack pointer | Spin interpreter in the new cog |
| `coginit(id, …)` | same | Restart a specific cog ID |

`cognew` returns 0…7 or −1. House style stores `id+1` so 0 means “not running”.

## Typical PASM prologue

```
entry                   mov     t1, par
                        add     t1, #offset
                        rdlong  field, t1
```

Walk a contiguous Hub block (ACIA and UART drivers do this). Document field offsets at the Spin `VAR` declaration.

## What each side owns

| | Spin | PASM |
|--|------|------|
| Runs in | Interpreter cog (bytecode in Hub) | Native cog (image copied from DAT) |
| Locals | Hub stack / VAR | Cog RAM (`RES` / reused init) |
| Cross talk | `byte`/`word`/`long[addr]`, locks | `RD*`/`WR*`, locks |
| Pins | Same `DIRA`/`OUTA`/`INA` model | Same; per-cog registers OR’d in hardware |

## Patterns in this tree

| Module | Bridge |
|--------|--------|
| `acia_rc2014.spin` | `cognew(@entry, @rx_head)` — FIFO indexes + config/status |
| `terminal_ftdi.spin` | `cognew(@entry, @rx_head)` — same shape; `JMPRET` inside cog |
| `keyboard_ps2.spin` | `cognew(@entry, @par_tail)` |
| `hires_text_vga.spin` | two `cognew(@d0, SyncPtr)` |
| `VJET_vUXM_*.spin` | `cognew` + DAT params filled with `longmove` before start |
| `ux_module.spin` | `cognew(termToZ80, @termStack)` — Spin helper cog |

## Pitfalls

1. Forgetting the Hub stack for a **Spin** `cognew` → crash.
2. Passing a Spin method address where a PASM `@label` is required (or the reverse).
3. Assuming PASM can `CALL` a Spin `PUB` — it cannot; use Hub mailboxes.
4. Starting PASM before Spin has written the Hub struct / `long 0-0` placeholders.
5. Two writers on the same Hub long without a protocol or lock.
6. Confusing **pin P2** (board net) with **Propeller 2** (chip generation).
