---
name: tool-rc-screen
description: >
  RC2014 ACIA console on USB CDC via GNU screen. Direct attach, no FTDI
  relay, no serial_probe. XMODEM send/receive with lsx/lrx. Use when
  talking to CP/M on the 8085, stuffing keys, hardcopy, or loading a
  .COM over the 8086net USB-C stick. Slash: /tool-rc-screen
---

# Tool — RC2014 CDC console

Session name **`rc2014`**. Device is **`/dev/cu.usbmodem*`** (USB CDC ACM). Screen opens that node. There is no PTY and no `ux-ftdi-relay`.

SparkFun FTDI **`/dev/cu.usbserial-*`** is Propeller `/RES` on DTR. That path is `ux-screen` (`tool-propeller`). Do not point `rc-screen` at it.

General command: `$HOME/bin/rc-screen` (on `PATH`). Config: `$HOME/.screenrc-rc`. In-tree copies: `tools/rc-screen.sh`, `tools/screenrc-rc`.

## Start / attach

```sh
rc-screen                              # CDC if one node; reattach if live
rc-screen /dev/cu.usbmodem01031
rc-screen --list
rc-screen --quit
```

Sockets live in `$HOME/.screen-rc2014` (`SCREENDIR`). Do not call `screen -S rc2014` from a random shell. Apple `screen` then looks in `$TMPDIR/.screen` and reports no session. Use `rc-screen --quit`, `rc-screen --stuff`, and `rc-screen --hardcopy`.

A TTY attaches. No TTY starts the session detached (`screen -d -m`). One session only. Do not start a second `screen` on the same CDC node.

If `ux-ftdi-relay` holds that node, run `ux-screen --quit` then `ux-screen --stop` first.

Env: `RC_SCREEN_DEV`, `RC_SCREEN_BAUD` (default 115200). `RC_SCREEN_RC` overrides the screenrc path. `RC_SCREEN_DIR` overrides `SCREENDIR`.

Binary: Apple `/usr/bin/screen`.

## Keys (human)

| Key | Action |
|-----|--------|
| `C-a d` | Detach (session stays on the port) |
| `C-a k` | Quit |
| `C-a s` | XMODEM send (`lsx -b -q -X`). Type the host path. |
| `C-a r` | XMODEM receive (`lrx -b -q -X`) |

Start `screen` with `115200,cs8,-ixon,-ixoff`. Apple `screen` with no baud flag resets the node to 9600. CDC DTR is not Propeller `/RES`.

## Agent I/O

The session stays up. Drive it with `rc-screen --stuff` and `rc-screen --hardcopy`. Do not wrap it in a Grok monitor. Do not call `screen -S` unless `SCREENDIR=$HOME/.screen-rc2014`.

```sh
rc-screen --stuff $'dir\r'
rc-screen --hardcopy /tmp/rc2014.hardcopy
```

## XMODEM (host → CP/M A:)

Same flags as `ux-screen`: `lsx -b -q -X`. Quiet is required. Progress on the serial line aborts CP/M after block 1.

On CP/M (8.3 name):

```
xmodem NAME.COM /r /q
```

Then on the host:

```sh
rc-screen --send /abs/path/to/file.com
rc-screen --send --1k /abs/path/to/file.com
```

`--send` waits one second (`--delay-startup 1`) so CP/M is in receive first. Overwrite prompt on CP/M is `Y`.

Host → 8085 receive:

```
xmodem NAME.COM /s /q
```

then `rc-screen --recv /abs/path/to/out`.

`lrzsz` (`lsx`/`lrx`) must be on `PATH` (Homebrew).

## Do not

1. Do not start `ux-screen` on the same CDC node while `rc2014` is live.
2. Do not use `tools/serial_probe.py` or `tools/ux-ftdi-relay.py` on this path.
3. Do not open `/dev/cu.usbmodem*` with `proploader` / `ux-load`. CDC is console only.
4. Do not start a second GNU `screen` named `rc2014`.
5. Do not watch the session with a byte-growth monitor. Use `hardcopy` or `--list`.
