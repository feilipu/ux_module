# ACIA host drivers vs this emulation

Checked 2026-09-12 for a **text-mode release candidate**. Not a live XMODEM check.

Sources:

- [RomWBW `Source/HBIOS/acia.asm`](https://github.com/wwarthen/RomWBW/blob/master/Source/HBIOS/acia.asm)
- [CPM-IDE `8085-cf-acia/cpm22bios.asm`](https://github.com/feilipu/CPM-IDE/blob/master/8085-cf-acia/cpm22bios.asm) from `_acia_interrupt`
- Tree: `src/acia_rc2014.spin`, `src/ux_module.spin` `PORT_DEFAULT` (`0x80`)

Punch list: [remaining-errors.md](remaining-errors.md). Wait loop: `lang-pasm/references/acia-wait.md`.

## Verdict

Neither driver needs a 6850 feature this tree does not already emulate for **text console**. Do not treat this as a clean bill of DDC, HDMI lock, or XMODEM transfer.

Default decode is `acia.start(PORT_DEFAULT)` (`0x80`). `PORT_ROMWBW` (`0x40`) is in source, commented.

## What they issue

| Operation | RomWBW | CPM-IDE 8085 | This tree |
|-----------|--------|--------------|-----------|
| Probe | `OUT $03`, status must be **0**. Then `OUT $02`. Status `& %00001110 == %00000010` (TDRE, CTS=0, DCD=0). | Chip is live from ROM CRT. BIOS `_acia_reset` zeros **software** rings only. | Status **0** while config is `$03`. After `$02`, `sync_irq` sets TDRE. CTS/DCD stay 0. |
| Init | `$03` then `$16` (8N1, /64, RTS low). IM1 ORs **RIE** (`$96`). No TIE. | CRT sets RIE/TIE/RTS. Warm boot does not rewrite the chip. | Stores the control byte. Clock divide and word select are not driven. Data path is 8-bit FIFO. |
| RX ready | Status bit 0 `RDRF`, or IM1 ring (32 bytes). | Software `aciaRxCount` after INT 65. | `RDRF` from TX FIFO unless `/RTS` high. |
| TX ready | Poll status bit 1 `TDRE`, then `OUT` data. | Immediate `OUT` if TDRE and Tx ring empty. Else ring + **TIE** (`TEI_RTS0`). | `TDRE` if RX FIFO has room and `tdre_hold` is 0. |
| `/RTS` | IM1: RTS high at 16/32, low at 8/32. `OR %01000000` / `AND %10111111`. | ISR: RTS high (`TDI_RTS1`) when RX fullish. `getc` sets RTS low (`TDI_RTS0`) when emptyish. | Exact `CR_TID_RTS1`: hide `RDRF`, keep FIFO, present `last_rdr`. Spin does not pulse `/INT` while RTS1. |
| IRQ | IM1: **RIE only**. ISR tests `RDRF`, not `SR_IRQ`. | 8085 RST 6.5. ISR tests `RDRF` then `TDRE`. Enables **TIE** when the Tx ring is not empty. | `sync_irq` on a **status read**. Spin pulses `DIRA[25]` on RIE/TIE. |
| Errors | Unused. Full software ring drops the byte. | Unused. | `PE`/`FE`/`OVRN` stay 0. Full TDR write is dropped. |
| 8-bit | 8N1 | Parity strip is commented out (XMODEM). | 8-bit through. |

`_acia0_*` and `_acia1_*` in CPM-IDE are the **same** chip. IOBYTE `$81` (CRT) still hits one ACIA.

## Gaps that do not block text RC

1. **Word select and clock divide.** Both drivers write them. This tree ignores them. They do not read the control register back.
2. **Break (`TC=11`).** RomWBW documents it. Neither console path uses it.
3. **`PE` / `FE` / `OVRN` / `SR_IRQ` as a poll bit.** Unused.
4. **1-byte TDR vs 512-byte FIFO.** Real 6850 `TDRE` clears for one character time after `OUT`. This tree keeps `TDRE` set until the FIFO is full or `tdre_hold`. CPM-IDE then drains its Tx ring faster. Safe for text.
5. **No `sync_irq` on a control write.** TIE on/off does not move `/INT` until the next status read. CPM-IDE ISR always starts with `IN` status. One extra INT 65 is possible. It is not a hang.
6. **Second ACIA.** RomWBW can have `ACIACNT >= 2`. This tree decodes one base. A second probe fails detect.

## Gaps to know. Do not “fix” for this RC

1. **RomWBW + SIO on `0x80`.** HBIOS ACIA then sits at `0x40`. Use the commented `PORT_ROMWBW` line. Wrong base: detect fails.
2. **CP/M warm boot does not `$03` the chip.** `_acia_reset` only clears 8085 rings. Propeller FIFOs stay. Boot `pulseZ80Reset` also does not flush. Do not add `txFlush`/`rxFlush`.
3. **`tdre_hold`.** If FTDI TX is full, this tree hides `TDRE`. RomWBW `ACIA_OUT` and CPM-IDE `putc` wait. Console pauses. That is FTDI back-pressure, not a 6850 miss.
4. **Live XMODEM.** Both sides pass 8-bit data. Host/Z80 session gates have no live transfer check yet. Text console does not need that.

## Do not change from this report

- Wait pair (`waitpne` then `waitpeq wr`).
- Status 0 while config is `$03` (RomWBW probe).
- Exact `CR_TID_RTS1` and exact `CR_TIE_RTS0`.
- Spin `DIRA[25]` pulse on RIE/TIE.
- Drop full TDR. Do not set `OVRN`.
