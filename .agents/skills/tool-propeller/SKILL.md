---
name: tool-propeller
description: >
  Propeller 1 toolchains for this repo: build and use OpenSpin (compile) and
  PropLoader/proploader (FTDI FT232 upload) for P8X32A Spin+PASM. Use when
  installing tools, compiling, flashing, or choosing a loader. Propeller 2
  tools are out of scope. Slash: /tool-propeller
---

# Tool — Propeller 1 compile / upload

CLI path for agents and scripts. Humans may still use PropellerIDE (see `README.md`).

## Installed layout (this machine)

| Binary | Source tree | Build output | Symlink |
|--------|-------------|--------------|---------|
| `openspin` | `~/Projects/OpenSpin` | `~/Projects/OpenSpin/build/openspin` | `~/bin/openspin` |
| `proploader` | `~/Projects/PropLoader` | `~/Projects/proploader-macosx-build/bin/proploader` | `~/bin/proploader` |

`PATH` must include `$HOME/bin` (set in `~/.zshrc`).

## Build OpenSpin from source

Needs `git`, `make`, and a C++ compiler (`g++` / Apple clang).

```bash
git clone --recursive https://github.com/parallaxinc/OpenSpin.git ~/Projects/OpenSpin
cd ~/Projects/OpenSpin
make
mkdir -p ~/bin
ln -sfn ~/Projects/OpenSpin/build/openspin ~/bin/openspin
openspin -h
```

Rebuild after pulls:

```bash
cd ~/Projects/OpenSpin && make
```

`openspin` with no args prints usage. Version banner looks like `OpenSpin` / `1.00.81`.

## Build PropLoader (`proploader`) from source

PropLoader calls `openspin` during its own build (Spin helpers). Put `openspin` on `PATH` first.

```bash
export PATH="$HOME/bin:$PATH"
git clone --recursive https://github.com/parallaxinc/PropLoader.git ~/Projects/PropLoader
cd ~/Projects/PropLoader
OS=macosx make
ln -sfn ~/Projects/proploader-macosx-build/bin/proploader ~/bin/proploader
proploader -?
```

| Host | `make` |
|------|--------|
| macOS | `OS=macosx make` |
| Linux | `OS=linux make` |
| Raspberry Pi | `OS=raspberrypi make` |
| Windows (MinGW cross from Linux) | `make CROSS=win32` |

Output directory is `~/Projects/proploader-<os>-build/bin/proploader` (sibling of the `PropLoader` repo). The Makefile `install` target copies into `~/bin`.

Rebuild:

```bash
export PATH="$HOME/bin:$PATH"
cd ~/Projects/PropLoader && OS=macosx make
```

## Why `proploader` (not `propeller-load` / Propeller Tool)

The UX Module programmes over an **FTDI FT232** USB-UART on P30/P31 with **DTR** reset — the same serial Propeller protocol as a Prop Plug. No FTDI D2XX API is required. macOS exposes `/dev/cu.usbserial-*` via Apple’s built-in FTDI driver.

| Tool | Verdict for FT232 |
|------|-------------------|
| **`proploader`** ([parallaxinc/PropLoader](https://github.com/parallaxinc/PropLoader)) | **Use this.** Serial + DTR/RTS reset; `-P` lists ports; RAM/EEPROM; optional terminal. |
| `propeller-load` (PropGCC) | Also serial/FTDI-capable, but heavier PropGCC/board-cfg dependency. |
| Propeller Tool / Propellent | Windows GUI / Windows CLI — not the macOS agent path. |

## Compile this repo

Copy from [`tools/README.md`](../../../tools/README.md). Top object must be the file on the `openspin` command line (same rule as PropellerIDE foreground).

```bash
mkdir -p build
openspin -L src -b -o build/ux_module.binary src/ux_module.spin
```

Product search path is `-L src` only. EEPROM-sized image file (still load with `proploader -e` or `tools/ux-load.sh`):

```bash
openspin -L src -e -o build/ux_module.eeprom src/ux_module.spin
```

Useful flags: `-L`/`-I` object search path, `-b` binary, `-e` eeprom file, `-v` verbose, `-u` unused-method elimination.

lib_vjet demos use their own top objects, for example:

```bash
openspin -L src -L src/lib_vjet -b -o build/vjet_test.binary src/lib_vjet/vjet_test.spin
```

## Load (FT232 Prop Plug only)

The ROM bootloader clocks bits with `0xF9`. That needs a low-latency USB-UART (**FTDI FT232 / FT231**, SparkFun FTDI Basic, Parallax Prop Plug). Default reset is **DTR**.

SparkFun FTDI Basic uses the FTDI TTL-232R 6-pin SIL, with **pin 6 swapped from RTS# to DTR#** so Arduino-style `/RES` works ([hookup guide](https://learn.sparkfun.com/tutorials/sparkfun-usb-to-serial-uart-boards-hookup-guide)). Align GRN (pin 6) to GRN, BLK (pin 1) to BLK.

| Pin | SparkFun Basic | Colour | UX Module |
|-----|----------------|--------|-----------|
| 1 | GND | BLACK | GND (BLK) |
| 2 | CTS# | BROWN | NC |
| 3 | VCC | RED | VCC |
| 4 | TXO | ORANGE | P31 RX |
| 5 | RXI | YELLOW | P30 TX |
| 6 | **DTR#** (active low) | GREEN | `!DTR` → `/RES` (GRN) |

A genuine FTDI TTL-232R cable still has **RTS# on pin 6**; that needs `-D reset=rts`, not DTR.

```bash
tools/ux-load.sh                       # EEPROM + run, DTR, cu.usbserial-*
tools/ux-load.sh /dev/cu.usbserial-XXXX
proploader -P                          # list serial ports
# FT232 is cu.usbserial-*, not cu.usbmodem-*
proploader -p /dev/cu.usbserial-XXXX -r build/ux_module.binary
proploader -p /dev/cu.usbserial-XXXX -e -r build/ux_module.binary   # EEPROM + run
proploader -p /dev/cu.usbserial-XXXX -R                            # reset only
proploader -p /dev/cu.usbserial-XXXX -r -t build/ux_module.binary  # run + terminal
```

If auto-detect finds the wrong port, pass `-p`. Prefer `/dev/cu.*` over `/dev/tty.*` on macOS. Ignore `/dev/cu.debug-console`.

Board clock comes from the **Spin source** (`_xinfreq = 7_372_800`). Loader `-b` / `-D clkfreq=…` only affect loader-side helpers.

Quit GNU `screen` before a load (`C-a k`, or `screen -X -S <name> quit`). The port must be free.

## Do not load over USB CDC

macOS **CDC ACM** sticks show as `/dev/cu.usbmodem*`. PropLoader **lists** them. They are **not** a Prop Plug.

Tried and failed on this board (2026-09-10), 8086 Consultancy USB-C to UART Adaptor (5 V), nodes `cu.usbmodem03291` and `cu.usbmodem01031`:

| Attempt | Result |
|---------|--------|
| Default DTR reset | `Propeller not found` |
| `-D reset=rts` | `Propeller not found` |
| `-D reset=rts-inv` (local PropLoader) | `Propeller not found` |
| Manual GRN–BLK (`-D reset=none`) | `Propeller not found` |

Cause: header pin 1 on that stick is **RTS**, not DTR. Software RTS did not reach `/RES` until a jumper exists. Even with a hand pulse, CDC ACM latency breaks the ROM `0xF9` handshake. Console at 115200 can still work. Do not use CDC to download.

This machine’s PropLoader (`~/Projects/PropLoader`) default is **DTR** (SparkFun FTDI Basic pin 6 DTR#). Extra methods: `-D reset=rts` (stock FTDI cable pin 6), `-D reset=rts-inv`, `-D reset=none` (prints `Release /RES now`).

## Console helpers (this repository)

Scripts live in `tools/`. Humans and agents copy from [`tools/README.md`](../../../tools/README.md).

| Command | Role |
|---------|------|
| `tools/ux-screen.sh` | GNU `screen` 115200 8N1 on SparkFun FTDI. `tools/ux-ftdi-relay.py` holds DTR off (that pin is `/RES`). Session `uxmod`. Config: `tools/screenrc-ux`. |
| `rc-screen` | GNU `screen` 115200 8N1 on USB CDC (`/dev/cu.usbmodem*`). Direct attach. No relay. Session `rc2014`. `$HOME/bin/rc-screen`. See `tool-rc-screen`. |
| `tools/serial_probe.py` | Headless TX/RX log on FTDI. Holds DTR off. Prints `BOOT`/`TX`/`RX` as `repr` plus `<CR>`/`<LF>`. Quit screen first. Not the CDC path. |
| `tools/ux-load.sh` | EEPROM load on SparkFun FTDI Basic. Default `reset=dtr` on `/dev/cu.usbserial-*`. `-m` is manual `/RES`. Refuses `/dev/cu.usbmodem*`. |
| `tools/screenrc-ux` | FTDI session: `flow off`; `C-a s` / `C-a r` prefill `lsx` / `lrx`. |

```bash
tools/ux-screen.sh                         # FT232 console (relay, DTR off)
tools/ux-screen.sh /dev/cu.usbserial-XXXX
rc-screen                                  # RC2014 ACIA on USB CDC (direct)
tools/serial_probe.py                      # FTDI banner only (quit screen first)
tools/serial_probe.py $'ABC123\r'
```

## Optional / out of scope

| Tool | Notes |
|------|-------|
| PropellerIDE | Default for human interactive work (`README.md`) |
| flexspin | Optional; use `-1` or `-1bc` only — never P2 default |
| `loadp2`, PNut P2 | Propeller 2 — wrong chip |

## Agent rules

1. If `openspin` or `proploader` is missing, build them with the steps above before inventing another toolchain.
2. Compile the **top** object named by the user (`ux_module.spin` or a `lib_vjet` demo).
3. Prefer `openspin` + `proploader` for this repo.
4. EEPROM on the board is 32 KB or 64 KB; bootloader loads **32 KB** into Hub RAM.
5. Do not install vendor FTDI VCP kexts on modern macOS — use Apple’s built-in FTDI driver.
6. Propeller 1 only. Do not install or default to P2 loaders.
7. Do not use `/dev/cu.usbmodem*` (CDC) to download. Load only on FT232 `/dev/cu.usbserial-*` with DTR reset. CDC is console-only.
