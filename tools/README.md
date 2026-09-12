# Compile, load, and console

Copy these commands from a clone of this repository. Product firmware is Propeller 1 only (`P8X32A`).

Put `openspin` and `proploader` on `PATH`. Build notes: `.agents/skills/tool-propeller/SKILL.md`.

Quit GNU `screen` before a load (`C-a k`). The serial port must be free.

## Product firmware

Top object: `src/ux_module.spin`. Search path: `-L src` only.

```sh
cd /path/to/ux_module
mkdir -p build
openspin -L src -b -o build/ux_module.binary src/ux_module.spin
tools/ux-load.sh
tools/ux-screen.sh
```

`tools/ux-load.sh` writes EEPROM and then runs. It uses DTR reset on `/dev/cu.usbserial-*` (SparkFun FTDI Basic pin 6). It refuses `/dev/cu.usbmodem*` (USB CDC). That path is console only.

```sh
tools/ux-load.sh /dev/cu.usbserial-XXXX
tools/ux-load.sh -m                       # hand pulse /RES
tools/ux-screen.sh /dev/cu.usbserial-XXXX
tools/serial_probe.py $'ABC123\r'         # headless TX/RX log, DTR held off
```

Same load without the helper:

```sh
proploader -P
proploader -p /dev/cu.usbserial-XXXX -e -r build/ux_module.binary
```

## VECTORJET demo (not the product top)

```sh
openspin -L src -L src/lib_vjet -b -o build/vjet_test.binary src/lib_vjet/vjet_test.spin
```

## Console keys (`tools/ux-screen.sh`)

| Key | Action |
|-----|--------|
| `C-a k` | Quit screen (do this before `ux-load.sh`) |
| `C-a d` | Detach |
| `C-a s` | XMODEM send (`lsx`). Type the file path. |
| `C-a r` | XMODEM receive (`lrx`) |

`tools/ux-ftdi-relay.py` holds DTR off. macOS asserts DTR on open of `cu.usbserial-*`. That pin is Propeller `/RES`.

Older pyserial helpers (Linux `/dev/ttyUSB0` in the source): `tools/serial_dtr.py` pulses DTR. `tools/serial_tool.py` writes stdin to the port and comments HUPCL options. Prefer `tools/ux-load.sh` and `tools/ux-screen.sh` on macOS.
