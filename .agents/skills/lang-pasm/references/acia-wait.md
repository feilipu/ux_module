# ACIA `/WAIT` loop (P8X32A)

Canonical rules for the bus wait in `src/acia_rc2014.spin`. A 68B50 places data in ≤150 ns (`docs/MC6850.pdf` page 4, MC68B50 `tDDR`). This cog cannot do that, so it stretches the Z80 I/O cycle on P24.

Do not treat this as a 6850 pin. The chip has Enable (E), not `/WAIT`.

## Match value

At entry the cog ORs `/M1` and `WAIT_PIN` into the Hub `acia_base` long. Each pass through `wait` loads that long into `OUTA`.

`port_active_mask` is `WAIT_PIN | M1_PIN | PORT_MASK`. Every 1-bit in the match value that `WAITPEQ` compares must also be 1 in this mask, or the wait never ends.

`OUTA` bit 24 (`/WAIT`) is 1 (released, open-collector via a diode) before the match.

## Required sequence

```
waitpne outa, port_active_mask      ' this cycle has ended (idle: returns at once)
… idle INA poll / sync_irq …        ' optional; cog ops only on the match path
waitpeq outa, port_active_mask wr   ' match + assert /WAIT
andn    outa, bus_int               ' undo carry into P25
```

Then decode A0 / `/RD` / `/WR`. Handlers release `/WAIT` with `or outa, bus_wait` before they return to `wait`.

## `wr` effect (do not remove)

`WAITPEQ dest, mask wr` does **not** write `INA`. After the pin pattern matches, it does `dest := dest + mask` (same reload idea as `WAITCNT`).

`OUTA` already has P24 high. The mask also has P24. Add: bit 24 becomes 0, so `/WAIT` goes low **in that instruction**. Carry sets `OUTA` bit 25 (`/INT`). The next `andn outa, bus_int` clears that bit.

`add outa, port_active_mask` is the same ALU. Prefer the `waitpeq … wr` form so match detect and `/WAIT` assert stay one instruction.

## Do not

1. Drop `wr` and assert `/WAIT` later with `andn outa, bus_wait`. That leaves the Z80 in T2 with no stretch.
2. Put Hub ops (`RDLONG` / `WRLONG` / `CALL` to `sync_irq`) on the path from “pins match” to `waitpeq … wr`.
3. Take `/WAIT` out of the match value or out of `port_active_mask`.
4. Replace `andn outa, bus_int` after `wr`. If `DIRA[25]` is on and `OUTA[25]` stays 1, `/INT` glitches high on every ACIA cycle.
5. Drive P24 or P25 `DIRA` from a Spin cog. This PASM cog owns both.

## `/INT` (P25)

Hold the pin low while `(RIE and (RDRF or OVRN)) or (exact CR5/CR6 TIE and TDRE)`. Float it when that is false. `OUTA` bit 25 stays 0 so a driven pin is low. `SR_IRQ` follows the pin (`docs/MC6850.pdf` pages 6 and 9).

`sync_irq` runs from this cog only. Spin `tx` / `rx` update FIFO indexes and `RDRF` / `TDRE` in Hub. They do not touch `DIRA[25]`.

## Related

- Code: `src/acia_rc2014.spin` labels `wait`, `matched`, `sync_irq`
- Flags and FIFOs: `module-ux`
- Pins: `hw-ux-pcb`
- OBEX `WAITPEQ` tip: [obex-pasm.md](obex-pasm.md)
