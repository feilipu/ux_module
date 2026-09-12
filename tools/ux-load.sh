#!/bin/zsh
# Load build/ux_module.binary over a SparkFun FTDI Basic (FT232, DTR reset).
# Header from GND (BLK): GND, CTS, VCC, TXO, RXI, DTR (GRN) = pin 6.
# DTR is net !DTR → Propeller /RES. macOS node /dev/cu.usbserial-*.
#
# Usage (from repo root or any cwd):
#   tools/ux-load.sh
#   tools/ux-load.sh /dev/cu.usbserial-XXXX
#   tools/ux-load.sh -m               # hand pulse /RES
# Quit GNU screen / tools/ux-screen.sh first.

set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/bin:$PATH"

here="${0:A:h}"
root="${here:h}"
bin="$root/build/ux_module.binary"
[[ -f "$bin" ]] || { print -u2 "ux-load: missing $bin  (compile first, see tools/README.md)"; exit 1 }

reset_method=dtr
want="${UX_LOAD_DEV:-${UX_SCREEN_DEV:-}}"
for arg in "$@"; do
  case "$arg" in
    -m|--manual) reset_method=none ;;
    -*) print -u2 "ux-load: unknown flag $arg"; exit 1 ;;
    *) want="$arg" ;;
  esac
done

list_ft232() {
  setopt localoptions nullglob
  local p
  for p in /dev/cu.usbserial*; do
    [[ -e "$p" ]] && print -r -- "$p"
  done
}

found=("${(@f)$(list_ft232)}")
if [[ -n "$want" ]]; then
  if [[ "$want" == *usbmodem* ]]; then
    print -u2 "ux-load: $want is CDC, not an FT232 Prop Plug"
    exit 1
  fi
  if [[ -e "$want" ]]; then
    dev="$want"
  else
    matches=()
    for p in "${found[@]}"; do
      [[ "$p" == *"$want"* ]] && matches+=("$p")
    done
    (( ${#matches} == 1 )) || { print -u2 "ux-load: pick one FT232 device"; print -u2 "  ${found[@]}"; exit 1 }
    dev="${matches[1]}"
  fi
elif (( ${#found} == 1 )); then
  dev="${found[1]}"
else
  print -u2 "ux-load: pass an FT232 path (/dev/cu.usbserial-*)"
  print -u2 "  ${found[@]}"
  exit 1
fi

if [[ "$reset_method" == none ]]; then
  print -u2 "ux-load  $dev  MANUAL RESET"
  print -u2 "HOLD DTR (GRN, pin 6) to GND (BLK). Press Enter. RELEASE when the line says: Release /RES now"
  read -r
else
  print -u2 "ux-load  $dev  reset=$reset_method  EEPROM+run"
fi
exec proploader -p "$dev" -D reset=$reset_method -e -r -v "$bin"
