# OBEX PASM references (Propeller 1 only)

External **Propeller 1** snippets used to cross-check this repo’s PASM skills.
Index: https://obex.parallax.com/code-language/pasm — **skip Propeller 2 objects** on that tag.  
Tips hub: https://obex.parallax.com/docs/chips-tips/propeller-1/

Full doc list: [p1-sources.md](p1-sources.md). Prefer tree + datasheet when behaviour disagrees. Use OBEX for idioms and worked examples.

| Topic | Link | Tree match |
|-------|------|------------|
| Pause / `WAITCNT` reload | [How to pause in PASM](https://obex.parallax.com/docs/chips-tips/propeller-1/how-to-pause-in-pasm/) | UART bit timing; Spin `waitcnt(clkfreq/… + cnt)` |
| Pin masks `OR`/`ANDN`/`XOR`/`MUX*`/`TEST` | [IO pin manipulation using PASM](https://obex.parallax.com/docs/chips-tips/propeller-1/io-pin-manipulation-using-pasm/) | ACIA `/WAIT` `/INT` data bus; FTDI masks |
| Per-cog `DIRA`/`OUTA`, shared `INA` | [Control IO pins from any cog](https://obex.parallax.com/docs/chips-tips/propeller-1/control-io-pins-from-any-cog/) | Open-collector **level** on `/INT` (ACIA cog only) |
| Spin pin ranges | [Simultaneous pin group control](https://obex.parallax.com/docs/chips-tips/propeller-1/simultaneous-pin-group-control/) | `dira[8..15]` style (Spin side) |
| `WAITPEQ` / `WAITPNE` | [WAITPEQ and WAITPNE with PASM](https://obex.parallax.com/docs/chips-tips/propeller-1/waitpeq-and-waitpne-with-pasm/) | ACIA address wait; I2C SCL wait |
| VAR vs DAT | [How to choose between VAR and DAT](https://obex.parallax.com/docs/chips-tips/propeller-1/how-to-choose-between-var-and-dat/) | Driver params in VAR; PASM image in DAT |
| Timing measurement | [Code Execution Time on the P8X32A](https://obex.parallax.com/obex/code-execution-time-on-the-p8x32a/) | Cycle budgets for bus/VGA |
| `JMPRET` coroutines | [Coroutines in PASM (AN014)](https://obex.parallax.com/obex/coroutines-in-pasm-an014/) | `terminal_ftdi.spin` rx/tx ping-pong |

## Idioms confirmed against `src/`

### `WAITCNT` pause (OBEX pause tip)

```
mov     timer, TICKS
add     timer, cnt
loop    waitcnt timer, TICKS
        djnz    count, #loop
```

`waitcnt dest, #delta` waits until `CNT == dest`, then writes `dest + delta` back into `dest`.

### Pin force high / low / toggle (OBEX IO tip)

| Goal | PASM |
|------|------|
| Output + high | `or dira, mask` then `or outa, mask` |
| Output + low | `or dira, mask` then `andn outa, mask` |
| Toggle | `xor outa, mask` |
| Release to input | `andn dira, mask` |
| Sample pin | `test mask, ina wc` / `wz` |

### `WAITPEQ` / `WAITPNE` (OBEX + datasheet)

```
waitpeq state, mask     ' until (INA & mask) == state
waitpne state, mask     ' until (INA & mask) != state
```

Rules:

1. Every 1-bit in `state` must also be 1 in `mask`, or `WAITPEQ` never completes.
2. Common edge wait: `waitpne mask, mask` then `waitpeq mask, mask` (wait for 1).
3. **`WR` effect is not “write INA”.** For `WAITPEQ dest, mask wr`, the destination becomes `dest + mask` (ALU add). UX ACIA uses this to assert `/WAIT` on address match (`acia_rc2014.spin`). Do not “simplify” that `wr` away. Full loop: [acia-wait.md](acia-wait.md).

### `JMPRET` coroutine (AN014; `terminal_ftdi.spin`)

```
receive   jmpret rxcode, txcode    ' swap to transmit fragment
          …
transmit  jmpret txcode, rxcode
```

One cog time-slices two tasks without Hub locks.

### DAT placeholders filled from Spin

```
MS_TICKS  long  0-0     ' Spin writes before cognew
msecs     res   1       ' cog-only scratch (not in Hub image meaningfully)
          FIT
```

`0-0` is a readable zero placeholder. `RES` reserves cog RAM after the loaded image.
