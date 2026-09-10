# Propeller 1 — source documents

This project is **P8X32A (Propeller 1) only**. Do not load Propeller 2 manuals into agent context for edit work.

## In-tree (prefer these)

| Doc | Path | Use |
|-----|------|-----|
| Propeller Manual v1.2 | `docs/P8X32A-Web-PropellerManual-v1.2.pdf` | Spin blocks, language, PASM chapter |
| Propeller Quick Reference v1.7 | `docs/Propeller Quick Reference v1.7.pdf` | Spin + PASM cheat sheet (opcode / condition / effect / clocks) |
| P8X32A datasheet | `pcb/P8X32A-Propeller-Datasheet-v1.4.0_0.pdf` | Hub timing, video, counters, electrical |
| MC6850 | `docs/MC6850.pdf` | ACIA register model (board peripheral) |
| ACIA `/WAIT` loop | `.agents/skills/lang-pasm/references/acia-wait.md` | P24 dest+mask stretch. Do not drop `wr`. |

## External (idioms and community tables)

| Doc | URL | Use |
|-----|-----|-----|
| OBEX PASM tag | https://obex.parallax.com/code-language/pasm | Snippets; **filter to Propeller 1** |
| Propeller 1 tips | https://obex.parallax.com/docs/chips-tips/propeller-1/ | Pause, WAITPEQ, VAR/DAT, pin masks |
| Ed Parsons PASM quick ref thread | https://forums.parallax.com/discussion/90092/pasm-quick-reference | Historic 2-page PDF (same class as in-tree quick ref) |
| Cluso99 P1 instruction-set summary | https://forums.parallax.com/discussion/164612/p1-instruction-set-summary | Opcode / cond / flags community table |
| OpenSpin | https://github.com/parallaxinc/OpenSpin | Open-source P1 Spin+PASM compiler (`openspin`). Build steps: `tool-propeller` |
| PropLoader | https://github.com/parallaxinc/PropLoader | P1 serial/WiFi loader (`proploader`) for FTDI FT232. Build steps: `tool-propeller` |
| FlexProp / flexspin | https://github.com/totalspectrum/flexprop | Optional; can target P1 — still emit **P1** mnemonics only |

## Out of scope (Propeller 2)

Do **not** use these for this repository:

| Doc | Why excluded |
|-----|----------------|
| https://www.parallax.com/propeller-2/documentation/ | P2 hub / smart pins / Spin2 |
| PASM2 manuals, Gracey P2 spreadsheets | Different ISA |
| PNut / Propeller Tool P2 mode | Wrong chip |
| Mnemonics `WAITX`, `DRVL`, `DRVH`, `##imm`, `HUBSET`, smart-pin regs | PASM2 only |

Authority when facts conflict: **tree `src/` → in-tree datasheet/manual → OBEX P1 tips**. Forum PDFs are secondary mirrors of the same P1 ISA.
