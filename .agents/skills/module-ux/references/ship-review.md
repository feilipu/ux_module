# Ship review — UX Module text firmware

Combative review of `src/ux_module.spin` and child objects. Date: 2026-09-11. Product is text VGA only. VECTORJET is not linked.

Line numbers refer to the tree **before** the ship fixes. This file is the checklist. It is not a clean bill.

Related: `remaining-errors.md` (ACIA punch list), `module-ux` revert notes.

## Verdict

Ship it as a **text console**. Do **not** trust it as an XMODEM pipe, especially not CRC-16 / 1K CRC. Screen motion is CP/M CR+LF plus a few CSI codes, not VT100. Characters are protected on the happy path and dropped on several real edges.

## Priority (ship blockers)

| # | Issue | Fix |
|---|--------|-----|
| 1 | CRC-16 trailer sniffed as a new frame | Count 1 or 2 trailers. Do not sniff delimiters in the CRC byte. |
| 2 | Host latch clears on payload `EOT`/`CAN` | Packet state machine. End only in the gap. Honour `ETB`. |
| 3 | Keyboard gated only inside `PARSE_XMODEM_*` | Gate for the whole Z80→host session, including the ACK gap. |
| 4 | DDC wait while Z80 is live. `pulseZ80Reset` does not flush | Hold `/RESET` across DDC. Flush ACIA while held. |
| 5 | Trailing `acia.tx` INT pulse never runs | Parentheses: `not (acia_config & mask)`. |
| 6 | Dual VGA cursor. BS at column 0 wipes the first cell | WMF is master. Sync overlay after WMF ops. Skip BS-space-BS at column 0. |

Until 1–3 have a live transfer check, treat XMODEM as a console filter, not a proven pipe.

## Current tree (staged, 2026-09-12)

Baseline `ee84231`. Cuts re-applied one at a time on a working console. Wait pair unchanged.

| # | Now |
|---|-----|
| 1 | Opaque `z80XmTrail`. In tree. Console checked. No live XMODEM check. |
| 2 | `hostXm` packet machine. In tree. Console checked. |
| 3 | `z80XmSess` gates the ACK gap. In tree. Console checked. |
| 4 | **Not in tree.** 1 ms `pulseZ80Reset` only. DDC still while the 8085 is live. |
| 5 | Trailing `acia.tx` pulse uses `not (config & mask)`. In tree. Console checked. |
| 6 | `syncCurs`. Idle BS-space-BS only if column > 0. No prompt-width guess. In tree. Console checked. |

Also in tree: text-only product top (no DIAG, no VECTORJET link). Compile `openspin -L src`.

## Bundle attempt (2026-09-11), then reverted, then bisected

These edits went into the index and onto EEPROM. They broke the CP/M console (`A>` then `AA` then a BS-space-BS storm). The working pre-review `ux_module.spin` was recovered from dangling blob `8188529d` and restored. Broken copy parked outside the tree as `ux_module_shipfix.spin` in the session directory. ACIA trailing INT parens were also reverted.

Do not re-apply this set as a bundle. Bisect one item at a time against the working console.

| # | What was in the broken bundle |
|---|----------|
| 1 | Opaque `z80XmTrail` (1 or 2). No CRC-lo sniff. |
| 2 | `hostXm` OFF/GAP/BLK/NBLK/DATA/TRAIL. |
| 3 | `z80XmSess` gated the keyboard across the ACK gap. |
| 4 | Tried 1 s `/RESET` hold and `masterReset` on release. Both failed. Left a 1 ms pulse. |
| 5 | Trailing `acia.tx` INT pulse with parentheses. |
| 6 | `syncCurs` after WMF. VGA BS-space-BS only if column > 0. |

Not done (out of ship scope): Unix LF-only, CSI `z80N` cap, `termToZ80` drop on `$03`, `term.start` 250 ms comment, unused APIs.

## Probe of the broken bundle (2026-09-11)

EEPROM load on `/dev/cu.usbserial-AB0JQLG6` of that bundle. OpenSpin size 12640 bytes.

Within about 3 s: Propeller banner and EDID/DDC lines are clean (a second open can concat `DDC/CI none` with the next `UX Module` because macOS asserts DTR).

Within about 6 s: CP/M prints `A>` then `AA` then a stream of BS-space-BS (`$08 $20 $08`). That is Z80 TDR `$08` expanded by idle backspace. Check the PS/2 key and the VGA before you treat this image as quiet. A 1 s `/RESET` hold across DDC was tried and made this worse. `masterReset` on release left `req_master` set and the ROM ACIA init did not stick.

---

## XMODEM — a latch with holes

### 1. CRC-16 trailer can be eaten as a new frame (bug)

`PARSE_XMODEM_CRC` treats CRC-lo as the next frame if the byte is `SOH`/`STX`/`EOT`/`ETB`/`CAN` (`ux_module.spin` ~375).

Checksum XMODEM lucks out: the extra state sees the next `SOH`/`EOT`. CRC-16 does not. CRC-lo is a data byte. If it is `$01`, `$02`, `$04`, `$17`, or `$18` (about 5/256 packets), the parser starts a new frame on the CRC. The real `SOH` then becomes a block number.

Fix: count trailers from the mode you entered (`1` vs `2`). Do not sniff delimiters in the CRC byte.

### 2. Host→Z80 “XMODEM” dies on payload `EOT`/`CAN` (bug)

`termToZ80` sets `hostXmodem` on any `SOH`/`STX` and clears it on any `EOT`/`CAN` (`ux_module.spin` ~609).

That is not packet-aware. `$04` and `$18` are legal payload bytes. The keyboard then writes into Z80 RDR mid-block.

`ETB` (`$17`) never clears the latch. A sender that ends on `ETB` leaves the keyboard dead until panic or `$03`.

There is no timeout. A host Ctrl-A (`SOH`) from a normal terminal latches this until panic. The skill already notes that. It is still a foot-gun.

### 3. Keyboard is only gated inside a Z80→host packet (bug)

`inXmodem` is false in `PARSE_IDLE`, including the gap between blocks (ACK/NAK). `hostXmodem` is 0 on that path. `kbdToZ80` runs. A key during download is injected as if it were the host ACK.

### 4. `termToZ80` can drop a byte on `$03` (bug)

FTDI `rx` happens before `acia.tx`. `acia.tx` returns without enqueue if `req_parse_idle` / `req_master` is set (`acia_rc2014.spin` ~192). The host byte is already gone from the UART FIFO.

Not in the top six. Do not add a new `txFlush`.

### 5. What actually works

- Z80→host payload is not painted on VGA.
- `ftdiNeed` holds `TDRE` when FTDI TX cannot take the next idle `CR`/`BS`.
- FTDI RX full **drops** instead of wrapping (`terminal_ftdi.spin` ~436). Keep it.
- ACIA RX full **drops** and does not set `OVRN`. Correct 6850-ish choice.

XMODEM here is “do not draw binary on VGA” plus “maybe mute the keyboard.” It is not a transfer engine.

---

## Screen movement — two cursors

Overlay `gTextCursX/Y` and WMF `gScreenCol/Row` update on different paths. CSI relative moves trust the overlay, then force WMF with `PX`/`PY`. Printable characters trust WMF via `printScreen`.

### 6. LF is discarded (bug for anything not CR+LF)

Idle `LF` is eaten. Idle `CR` does `term.newLine` (CR+LF) and `wmf#NL`. Product is CP/M. Keep LF eaten unless a Unix console is in scope.

Last-row `CR` does not increment overlay Y. WMF `newLine` **does** scroll (`wmf_terminal_vga.spin` ~680). After a full screen, overlay Y is “bottom” while the bitmap has scrolled. `ESC [ A` then uses the overlay.

### 7. Backspace at column 0 wipes the first cell (bug)

WMF `$08` does not wrap to the previous line (`wmf_terminal_vga.spin` ~741). At column 0, BS is a no-op, then SPACE writes column 0. A leading-edge BS deletes the first character of the line.

### 8. CSI is a toy subset, and `z80N` is unbounded

Implemented: `A B C D E F G H J K m` (`m` is only 0 and 7, current row only). Fine for CP/M-IDE. Not VT100.

`z80N := z80N*10 + digit` has no cap. A long numeric CSI wraps a signed long. `setCursXY` then clamps.

`CSI J`/`K` 0/1 `bytefill` the glyph buffer and do not move WMF.

TAB is the one path that re-reads WMF (`getColScreen` / `getRowScreen`). That is an admission the overlay is not authoritative.

### 9. Last-column wrap is accidentally consistent

`echoPrintable` increments overlay **before** the write. `printScreen` increments WMF **after**. Starting at 0 they stay aligned for ordinary glyphs. Do not “fix” wrap without treating it as one cursor.

---

## Character loss and buffer overflow

### 10. Boot: Cog 0 sits in I2C for up to 1 s while the Z80 is still live (bug)

`startDdc` blocks Cog 0 (`waitIdle` 500 ms × 2). ACIA PASM still runs. The Z80 is **not** in reset yet. TDR bytes fill the 512-byte RX FIFO, then they are dropped. `pulseZ80Reset` then kicks the CPU and does **not** wipe those FIFOs. Pre-reset junk is replayed as the first console bytes.

Hold `/RESET` across DDC, or `masterReset` the FIFOs at `pulseZ80Reset`. Hold P5 **after** `acia.start` (`mov dira,bus_wait` clears `DIRA[5]`).

### 11. `term.tx` still blocks. The peek is only as honest as `ftdiNeed`

`ftdiNeed` special-cases idle `BS`/`DEL`/`CR`/`LF` only. CSI and XMODEM always claim 1 slot. If that peek is wrong, Cog 0 sits in `terminal_ftdi.tx` and stops pumping `tdreHold`.

### 12. FIFOs themselves do not wrap

| Buffer | Size | Full behaviour |
|--------|------|----------------|
| ACIA RX/TX | 512 | drop write / Spin waits (abort on reset) |
| FTDI RX/TX | 512 | RX drop; TX Spin waits |
| PS/2 | 16 words | ring `& $F` — oldest and newest collide |

`PUMP_LIMIT` 16 is a latency cap, not an overflow cap. It helps only while Cog 0 runs.

### 13. INT pulse after `acia.tx` is dead (bug, P2-2 still open)

```
if not acia_config & constant ( CR_TID_RTS1 << DATA_BASE )
```

Spin `not` binds tighter than `&`. This is `(not acia_config) & mask`. After `start`, config is nonzero, so this pulse **never runs**. The wait-loop pulse **does** use parentheses. Polling BIOS hides it. An RIE-driven BIOS misses keys until a status read.

---

## Dead code / leftover lies

Do not delete the ASCII table. House policy.

| Item | Where | Why it is dead or false |
|------|--------|-------------------------|
| Trailing `DIRA[25]` pulse | `acia_rc2014.spin` ~209 | **Fixed.** `not (config & mask)`. |
| `term.start` “clears screen” + 250 ms wait | `terminal_ftdi.spin` ~54 | Wait is real. Clear is not. |
| `wmf.newLine` comment “cursor home” | `wmf_terminal_vga.spin` ~668 | **Fixed.** Comment now says column 0 and optional scroll. |
| `i2c` “Added self-demo PUB Main” | `i2c.spin` ~16 | No `PUB Main` in the file. |
| `PORT_VJET` | `ux_module.spin` ~20 | Reserved, unused. Keep as a marker. |
| `ASCII_GT` | `ux_module.spin` ~57 | Leftover from the `>` graphics hook. |
| Empty `CON '' Visual differentiation` | `ux_module.spin` ~176 | Noise. |
| PST/WMF/PS2 APIs unused by product | `strIn`, `decIn`, `drawFrame`, `keyState` | Library weight, not a runtime bug. |

`kbd.gotKey` skipping `$DE` (caps lock) **is** used as the `kbdToZ80` loop test. That one is live.

---

## What I would not pick a fight over

- Single writer for `acia.tx` on Cog 0.
- `tdreHold` / `tdreAllow` as Hub flags, not Spin RMW of `acia_status`.
- `$03` sets `req_parse_idle` before indexes move. Spin `tx`/`rx` abort.
- Panic gated `term.clear` (4 TX slots) so Cog 0 does not block on PST while P5 is held.
- Arrow keys requiring 3 FIFO slots before `getKey`.
- FTDI RX drop-on-full (binary-safe. No XON/XOFF).

Those robustness features are real.

---

## Out of ship scope (do not treat as blockers)

- Unix `LF`-only line ends (keep CP/M CR+LF).
- CSI cap on `z80N`. Full VT100.
- `termToZ80` drop window on `$03` (item 4).
- `term.start` 250 ms wait. Unused PST/WMF APIs.
- Graphics / VECTORJET (parked).
- Delete unused `ASCII_*` names.
