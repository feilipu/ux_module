#!/bin/zsh
# UX Module serial console via GNU screen.
# SparkFun FTDI Basic (FT232, /dev/cu.usbserial-*) or 8086net CDC
# (/dev/cu.usbmodem*). 115200 8N1, RX/TX only. No XON/XOFF (XMODEM).
# CTS is NC. DTR on the Basic is /RES — do not assert it from screen.
#
# Prefer a single FT232. Pass a path or unique suffix if several nodes
# exist. UX_SCREEN_DEV overrides the default pick.
#
# Usage:
#   tools/ux-screen.sh
#   tools/ux-screen.sh /dev/cu.usbserial-AB0JQLG6
#   tools/ux-screen.sh AB0JQLG6
# Detach: C-a d    Quit: C-a k
# XMODEM send:    C-a s   then file path (or C-a : exec !! lsx -b FILE)
# XMODEM 1K send: C-a : exec !! lsx -b -k FILE
# XMODEM receive: C-a r   then file path (or C-a : exec !! lrx -b FILE)

set -euo pipefail

here="${0:A:h}"
export PATH="/opt/homebrew/bin:$HOME/bin:$here:$PATH"

list_ports() {
  setopt localoptions nullglob
  local p
  for p in /dev/cu.usbserial* /dev/cu.usbmodem*; do
    [[ -e "$p" ]] && print -r -- "$p"
  done
}

match_port() {
  local want="$1" p
  [[ -e "$want" ]] && { print -r -- "$want"; return 0 }
  [[ "$want" != */* ]] || return 1
  list_ports | while read -r p; do
    [[ "$p" == *"$want"* ]] && print -r -- "$p"
  done
}

pick_port() {
  local -a found matches ft232
  local want="${1:-${UX_SCREEN_DEV:-}}" p n

  found=("${(@f)$(list_ports)}")
  ft232=()
  for p in "${found[@]}"; do
    [[ "$p" == *usbserial* ]] && ft232+=("$p")
  done

  if [[ -n "$want" ]]; then
    matches=("${(@f)$(match_port "$want")}")
    if (( ${#matches} == 1 )); then
      print -r -- "${matches[1]}"
      return 0
    fi
    if (( ${#matches} == 0 )); then
      print -u2 "ux-screen: no serial device matching $want"
    else
      print -u2 "ux-screen: $want matches more than one device:"
      print -u2 "  ${matches[@]}"
    fi
    if (( ${#found} )); then
      print -u2 "available:"
      print -u2 "  ${found[@]}"
    fi
    return 1
  fi

  if (( ${#found} == 0 )); then
    print -u2 "ux-screen: no /dev/cu.usbserial* or /dev/cu.usbmodem*"
    return 1
  fi
  if (( ${#ft232} == 1 )); then
    print -r -- "${ft232[1]}"
    return 0
  fi
  if (( ${#found} == 1 )); then
    print -r -- "${found[1]}"
    return 0
  fi

  print -u2 "ux-screen: ${#found} serial devices; one per session:"
  n=1
  for p in "${found[@]}"; do
    print -u2 "  $n) $p"
    (( n++ ))
  done
  if [[ ! -t 0 ]]; then
    print -u2 "pass a path or unique suffix, or set UX_SCREEN_DEV"
    return 1
  fi
  print -u2 -n "pick 1-${#found}: "
  read -r n || return 1
  if [[ "$n" != <-> ]] || (( n < 1 || n > ${#found} )); then
    print -u2 "ux-screen: bad pick"
    return 1
  fi
  print -r -- "${found[n]}"
}

dev="$(pick_port "${1:-}")" || exit 1

rc="$here/screenrc-ux"
# macOS asserts DTR on open of cu.usbserial-*. On the SparkFun Basic that
# pin is /RES, so GNU screen on the FTDI holds the Propeller in reset.
# Relay keeps DTR released; screen talks to a PTY.
relay="$here/ux-ftdi-relay.py"
pty="/tmp/ux-pty-${UID}"
if [[ ! -x $relay ]]; then
  print -u2 "ux-screen: missing $relay"
  exit 1
fi
if [[ ! -f $rc ]]; then
  print -u2 "ux-screen: missing $rc"
  exit 1
fi

"$relay" "$dev" "$pty" &
relpid=$!
ok=0
for _ in {1..50}; do
  if [[ -L $pty ]]; then
    ok=1
    break
  fi
  sleep 0.05
done
if (( ! ok )); then
  kill "$relpid" 2>/dev/null || true
  print -u2 "ux-screen: relay did not create $pty"
  exit 1
fi
# EEPROM boot after DTR release is ~1 s; banner follows term.start's 1/4 s wait.
print -u2 "UX Module  $dev  via $pty  115200 8N1 RX/TX  (C-a s send / C-a r receive XMODEM)"
print -u2 "wait for UX Module Initialised  (DTR held off)"
/usr/bin/screen -c "$rc" "$pty"
kill "$relpid" 2>/dev/null || true
wait "$relpid" 2>/dev/null || true
