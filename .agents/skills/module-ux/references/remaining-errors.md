# ACIA/flow repairs (closed list)

These were open after `faabd9c`. They are implemented. Do not restore Spin writes to `acia_status`. Do not restore XON/XOFF on the 8-bit load path. Policy table: `module-ux` revert notes.

Residual hardware: **P0-3** (RC2014 reset button). Net `PRESET` (P5) is not pulled. C12 is 200 pF. PASM must not poll P5 as a reset input (the pin floats). The button pulls `!RESET` (D1 anode). ACIA state then follows ROM `$03` (`CR_RESET`, keep `tdre_hold`). CTRL+ALT+DEL holds P5 low for 1 ms and uses `req_master` (`do_master_reset`).

| ID | What landed | Revert |
|----|-------------|--------|
| P0-1 | `panicReset` holds `!RESET` during `masterReset`, then `tdreHold`. VGA `CS` always. FTDI `clear` only if `txSpace => 4`. | Blocking `term.clear` after releasing reset. |
| P0-2 | Idle loop and `wait_pin_high` sample `req_master`. `/RD` `/WR` rise waits poll, they do not `waitpeq`. P5: `outa~` then `dira~~`, 1 ms, then release. | `waitpeq bus_rd/bus_wr` and a two-instruction pulse. |
| P0-3 | Not sensed on P5. See residual above. `do_master_reset` writes config `$03` and `req_parse_idle`. | Polling floating P5. |
| P0-4 | FTDI RX PASM drops the byte when `(head+1)==tail`. No wrap over unread data. Still no host pause (8B). | Store-always FullDuplexSerial head increment. |
| P0-5 | `hostXmodem` set on FTDI `SOH`/`STX`, cleared on `EOT`/`CAN`, `CR_RESET`, panic. Main skips `kbdToZ80`. Ctrl-A (`$01`) also sets the flag. Panic clears it. | Keyboard during host→Z80 load. |
| P1-1 | PASM writes `req_parse_idle` **before** zeroing indexes. Spin `tx`/`rx` abort if `req_parse_idle` or `req_master`. | Index update without the flag. |
| P1-2 | `readZ80` pumps `ftdiNeed==0` (LF) even when FTDI TX is full. | Early return on `!term.txCheck`. |
| P1-3 | `tdreAllow` only when the next byte fits (or the FIFO is empty and FTDI has a slot). | `tdreAllow` at the start of `readZ80`. |
| P1-4 | `STX` → 1024 data. After data: CS then CRC. If the CRC byte is `SOH`/`STX`/`EOT`/`ETB`/`CAN`, treat it as the next frame (checksum mode). Bad `n/~n` returns to IDLE with no payload. | `SOH`+129 only. |
| P2-1 | `do_master_reset` writes `acia_config` `$03`. Status reads stay 0 until a real control word. | Leave old TIE in config. |
| P2-2 | Removed `transmit_data` RMW of `acia_status`. `sync_irq` is the only status writer. | RMW-clear `OVRN` on RDR read. |
| P2-3 | Unchanged: TDR full drops the write. No TDR `OVRN`. | Setting `OVRN` on TDR full. |
| P2-4 | Deleted `txFlush` / `rxFlush`. | Dual-writer flush of both ends. |
| P2-5 | Hub map below. | |
| P2-6 | `tx`/`rx` wait, but abort on reset flags. Callers still check space first. | Wait forever through `CR_RESET`. |
| P3-1 | CSI cursor uses `clampCurs` / `setCursXY`. No `n // rows - 1`. | Modulo CUP. |
| P3-2 | TAB: `wmf.outScreen(TB)` then copy `getColScreen` / `getRowScreen`. | Dual increment of `gTextCursX`. |
| P3-3 | Z80 CR → `term.newLine` (CR+LF). `ftdiNeed` is 2. | `term.lineFeed` only. |
| P3-4 | CON comment: up to `PUMP_LIMIT` bytes per `readZ80`. | “One byte per call.” |
| P3-5 | `outa[n]~` before `dira[n]~~`. | `dira~~` alone. |

## Hub writer map

| Cell | Writer | Notes |
|------|--------|-------|
| `tx_head` | Spin | Abort on `req_parse_idle` / `req_master`. PASM zeros on reset |
| `tx_tail` | PASM | |
| `rx_head` | PASM | |
| `rx_tail` | Spin | Abort on reset flags |
| `acia_status` | PASM `sync_irq` only | |
| `acia_config` | PASM `receive_command` | `do_master_reset` writes `$03`. Spin `start` before `cognew` |
| `tdre_hold` | Spin | PASM zeros only in `do_master_reset` |
| `req_master` | Spin 1, PASM 0 | Sampled in `sync_irq`, idle poll, `wait_pin_high` |
| `req_parse_idle` | PASM 1, Spin 0 | Written **before** FIFO zeros |
| `last_rdr` | PASM cog RAM | Not a Hub long |
