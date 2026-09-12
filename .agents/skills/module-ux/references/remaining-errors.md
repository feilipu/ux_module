# ACIA/flow punch list (open)

Policy (what to keep or undo) is the revert-notes table in `module-ux`. This file is the tree vs that policy. It is **not** a clean bill of health.

XMODEM, VGA cursor, and boot-reset findings: [ship-review.md](ship-review.md). RomWBW and CPM-IDE ACIA clients vs this tree: [acia-host-drivers.md](acia-host-drivers.md). Text RC: those drivers do not need a 6850 feature this tree lacks. Live XMODEM is still open.

Bus cog: **`569cd07` wait loop** (`rdlong` base, `waitpne`, `waitpeq wr`). No Hub between those waits. Rise wait is `wait_pin_high` (poll pin and `req_master`). Mailbox is **11 longs**. `last_rdr` is cog RAM.

Probe after each slice: ROM banner plus `ABC\r` → `ABC\r\n\r\n> `.

## Status vs tree

| ID | Policy fix | In this tree | Notes |
|----|------------|--------------|-------|
| **P0-1** | Hold P5 1 ms, discard host RX, restart ACIA cog (`last_rdr` and FIFOs zero), `tdreHold`. Panic: VGA `CS`, FTDI `clear` only if 4 TX slots | **Landed (Spin).** Boot `pulseZ80Reset` uses the same wipe. | Do not wait on `req_master`. Keep gated `clear`. |
| **P0-2** | Sample `req_master` in idle/`wait_pin_high`; no `waitpeq` on `/RD` `/WR` rise | **Partial.** `wait_pin_high` samples `req_master`. Spin does **not** wait on the flag. Idle Hub between `waitpne` and `waitpeq wr` is forbidden. | Rise abort only. |
| **P0-3** | Sample P5 when not driving. 1 ms debounce. Wipe ACIA once per backplane `/RESET`. Keep `tdre_hold` | **Landed.** D1 pulls P5 high while `/RESET` is idle. Do not drive P5 in reply. | Idle poll with no debounce was the false-trigger. |
| **P0-4** | FTDI RX drop when full; no XON/XOFF | **In tree.** | Do not restore wrap-over or XON. |
| **P0-5** | Skip `kbdToZ80` on host `SOH`/`STX` | **Landed (packet machine).** | `hostXm` ends on `EOT`/`ETB`/`CAN` in GAP only. `z80XmSess` covers the ACK gap. |
| **P1-1** | `req_parse_idle` before PASM zeros indexes; Spin `tx`/`rx` abort | **Landed.** | Keep the take in the loop. |
| **P1-2** | Pump LF when FTDI TX is full | **In tree.** | Done. |
| **P1-3** | `tdreAllow` only when the next byte fits | **Landed.** `sync_irq` honours `tdre_hold`. | After `/WAIT` only. |
| **P1-4** | XMODEM-1K parser | **Landed.** Opaque trailers (1 checksum, 2 CRC / `STX`). | Do not sniff CRC-lo as `SOH`. No live transfer check yet. |
| **P2-1** | Panic sets `acia_config` `$03` | **Landed.** | `do_master_reset` does not clear `tdre_hold`. |
| **P2-2** | PASM only writer of `acia_status` | **Partial.** Live compose is `sync_irq` on a status read. Spin does not RMW `acia_status`. Spin still **pulses** `DIRA[25]` when RIE/TIE. Trailing `tx` pulse uses `not (config & mask)`. Removing that pulse dropped host keys (RX empty). `start` writes initial status before `cognew`. | Do not idle `sync_irq`. Keep the Spin INT pulse. |
| **P2-3** | Full TDR: drop write, no `OVRN` | **Landed.** | Done. |
| **P2-4** | Delete `txFlush` / `rxFlush` | **Landed.** | Done. |
| **P2-5** | Hub map | **11 longs.** `last_rdr` is cog RAM. | See table. |
| **P2-6** | `tx`/`rx` abort on reset flags | **Landed** with P1-1. | Done. |
| **P3-1** … **P3-5** | CUP, TAB, CR, `PUMP_LIMIT`, `outa` before `dira` | **In tree.** | Done. |

## Empty / `/RTS` RDR

**Landed.** Same drive timing as `569cd07` (rdbyte, then shl, then `or outa`). Empty or cached `CR_TID_RTS1` presents `last_rdr` and rewinds `tx_tail`. Earlier branch-before-drive `last_rdr` failed (`ACC`, high-bit bytes) and must not be restored.

## Hub writer map (this image)

| Cell | Writer now | Policy writer |
|------|------------|---------------|
| `tx_head` | Spin `tx` (abort on flags) | Spin (abort on flags) |
| `tx_tail` | PASM; Spin `masterReset` (panic wipe while `waitpeq` has no match) | PASM only |
| `rx_head` | PASM; Spin `masterReset` | PASM only |
| `rx_tail` | Spin `rx` (abort on flags) | Spin (abort on flags) |
| `acia_status` | PASM `sync_irq` (live). `start` before `cognew`. `$03` / `do_master_reset` write the reset value. | PASM `sync_irq` only |
| `acia_config` | PASM `receive_command` / `do_master_reset`; Spin `start` / `masterReset` | PASM + `start` |
| `tdre_hold` | Spin `tdreHold` / `tdreAllow` / `masterReset` | Spin |
| `req_master` | Spin `masterReset` sets 1; PASM `do_master_reset` sets 0 | Spin 1, PASM 0 |
| `req_parse_idle` | PASM `$03` / `do_master_reset` sets 1; Spin `takeParseIdle` / `start` sets 0 | PASM 1, Spin 0 |
| `DIRA[25]` | Spin `tx`/`rxCount` pulse when RIE/TIE. PASM `sync_irq` level on a status read. | PASM level only |

## Failed slices (do not retry the same way)

1. `last_rdr` with extra Hub/branch **before** the RDR drive (echoed `ACC` / high-bit bytes).
2. `sync_irq` as the only status writer **and** no Spin INT pulse (RX empty).
3. Idle `sync_irq` between `waitpne` and `waitpeq wr` (silent 8085).
4. Spin `masterReset` wait on `req_master` while P5 is held (deadlock).

Do not: idle `sync_irq`, Hub between `waitpne` and `waitpeq wr`, poll P5 with no debounce, drive P5 in reply to a backplane pulse, restore XON/XOFF, drop the Spin INT pulse.
