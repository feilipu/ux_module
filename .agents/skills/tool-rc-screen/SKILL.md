---
name: tool-rc-screen
description: >
  RC2014 ACIA console via GNU screen on USB CDC or FTDI.
  Direct attach,
  no FTDI relay, no serial_probe. XMODEM send/receive with lsx/lrx. Use
  when talking to CP/M on 8085 or Z80, stuffing keys, hardcopy, or
  loading a .COM. Slash: /tool-rc-screen
---

# Tool — RC2014 serial console

Session name **`rc2014`**. Device is USB CDC ACM **`/dev/cu.usbmodem*`** or FTDI **`/dev/cu.usbserial*`**. Screen opens that node. There is no PTY and no `ux-ftdi-relay`.

SparkFun FTDI on the UX Module has Propeller `/RES` on DTR. That path is `ux-screen` (`tool-propeller`). A Z80 RC2014 serial module on FTDI is a normal console. `rc-screen` opens it. macOS asserts DTR on open of `cu.usbserial-*`.

General command: `$HOME/bin/rc-screen` (on `PATH`). Config: `$HOME/.screenrc-rc`. In-tree copies: `tools/rc-screen.sh`, `tools/screenrc-rc`.

## Start / attach

```sh
rc-screen                              # one USB node of either kind; reattach if live
rc-screen /dev/cu.usbmodem01031
rc-screen /dev/cu.usbserial-A50285BI
rc-screen A50285BI
rc-screen --list
rc-screen --quit
```

If more than one USB serial node exists, pass a path or a unique suffix. Set `RC_SCREEN_DEV` for a default. A TTY with several nodes asks which one.

Sockets live in `$HOME/.screen-rc2014` (`SCREENDIR`). Do not call `screen -S rc2014` from a random shell. Apple `screen` then looks in `$TMPDIR/.screen` and reports no session. Use `rc-screen --quit`, `rc-screen --stuff`, and `rc-screen --hardcopy`.

A TTY attaches. No TTY starts the session detached (`screen -d -m`). One session only. Do not start a second `screen` on the same node.

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

`screen` cannot set RTS/CTS. `C-a f`, `flow`, and `-f` are XON/XOFF. Leave `defflow` and `flow` off. After the session has the node open, set `stty -f <node> crtscts -ixon -ixoff` (macOS `-f`). Parentheses around `CTS` in `C-a i` mean hardware flow is on. `!CTS` means the board holds `/RTS` off, or pin 6 does not reach the adapter CTS input.

`$HOME/bin/rc-screen` is the holder. It keeps the serial node at 115200 8N2, because Apple `screen` clears the second stop bit if it opens the node. AppleUSBFTDI also clears the termios `CRTSCTS` bit. On `/dev/cu.usbserial-*` the holder then sends the FT232 `SET_FLOW` vendor request (RTS/CTS). Screen attaches to the holder PTY. `C-a i` on that PTY does not show the board CTS line. The holder log `/tmp/rc-hold-$UID.log` prints `SET_FLOW` and the chip modem byte. `CTS 0` means the adapter will hold TX. Quit and start again after this change. An old holder does not pick it up.

`tools/rc-screen.sh` also uses 115200 8N2. It sets `cstopb` again after `screen` opens the node. `crtscts` stays on for this console. Do not copy `crtscts` onto `ux-ftdi-relay`.

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

Host → board receive:

```
xmodem NAME.COM /s /q
```

then `rc-screen --recv /abs/path/to/out`.

`lrzsz` (`lsx`/`lrx`) must be on `PATH` (Homebrew).

## Do not

1. Do not start `ux-screen` on the same node while `rc2014` is live.
2. Do not use `tools/serial_probe.py` or `tools/ux-ftdi-relay.py` on this path.
3. Do not open `/dev/cu.usbmodem*` with `proploader` / `ux-load`. CDC is console only.
4. Do not start a second GNU `screen` named `rc2014`.
5. Do not watch the session with a byte-growth monitor. Use `hardcopy` or `--list`.
6. Do not use `rc-screen` on the SparkFun UX Module FTDI. That DTR pin is `/RES`. Use `ux-screen`.
