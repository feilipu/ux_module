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

Top object must be the file on the `openspin` command line (same rule as PropellerIDE foreground).

```bash
cd ~/Projects/ux_module
mkdir -p build
openspin -L src -L src/lib_vjet -b -o build/ux_module.binary src/ux_module.spin
# EEPROM-sized image file (still load with proploader -e):
openspin -L src -L src/lib_vjet -e -o build/ux_module.eeprom src/ux_module.spin
```

Useful flags: `-L`/`-I` object search path, `-b` binary, `-e` eeprom file, `-v` verbose, `-u` unused-method elimination.

lib_vjet demos use their own top objects, for example:

```bash
openspin -L src/lib_vjet -b -o build/vjet_test.binary src/lib_vjet/vjet_test.spin
```

## Load (FTDI)

```bash
proploader -P                          # list serial ports
proploader -p /dev/cu.usbserial-XXXX -r build/ux_module.binary
proploader -p /dev/cu.usbserial-XXXX -e -r build/ux_module.binary   # EEPROM + run
proploader -p /dev/cu.usbserial-XXXX -R                            # reset only
proploader -p /dev/cu.usbserial-XXXX -r -t build/ux_module.binary  # run + terminal
```

If auto-detect finds the wrong port, pass `-p`. Prefer `/dev/cu.*` over `/dev/tty.*` on macOS.

Board clock comes from the **Spin source** (`_xinfreq = 7_372_800`). Loader `-b` / `-D clkfreq=…` only affect loader-side helpers.

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
