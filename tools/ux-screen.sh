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
#   tools/ux-screen.sh --stop     # close the FTDI relay (pulses DTR)
# Detach: C-a d    Quit: C-a k
# XMODEM send:    C-a s   then file path (or C-a : exec !! lsx -b -q -X FILE)
# XMODEM 1K send: C-a : exec !! lsx -b -q -X -k FILE
# XMODEM receive: C-a r   then file path (or C-a : exec !! lrx -b -q -X FILE)

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

pty="/tmp/ux-pty-${UID}"
pidfile="/tmp/ux-relay-${UID}.pid"
devfile="/tmp/ux-relay-${UID}.dev"

stop_ux_relay() {
  local pid
  if [[ -f $pidfile ]]; then
    pid="$(<"$pidfile")"
    if [[ "$pid" == <-> ]]; then
      kill "$pid" 2>/dev/null || true
      for _ in {1..20}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
      done
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pidfile" "$devfile"
}

if [[ "${1:-}" == --stop ]]; then
  stop_ux_relay
  print -u2 "ux-screen: relay stopped"
  exit 0
fi

dev="$(pick_port "${1:-}")" || exit 1

rc="$here/screenrc-ux"
# macOS asserts DTR on open of cu.usbserial-*. On the SparkFun Basic that
# pin is /RES. Keep one relay process so later screen attach does not
# reopen the FTDI. ux-load.sh / ux-screen.sh --stop close it.
relay="$here/ux-ftdi-relay.py"
if [[ ! -x $relay ]]; then
  print -u2 "ux-screen: missing $relay"
  exit 1
fi
if [[ ! -f $rc ]]; then
  print -u2 "ux-screen: missing $rc"
  exit 1
fi

need_start=1
if [[ -f $pidfile ]]; then
  relpid="$(<"$pidfile")"
  if [[ "$relpid" == <-> ]] && kill -0 "$relpid" 2>/dev/null; then
    olddev=""
    [[ -f $devfile ]] && olddev="$(<"$devfile")"
    if [[ -n $olddev && $olddev != $dev ]]; then
      print -u2 "ux-screen: relay holds $olddev; restart for $dev (DTR pulse)"
      stop_ux_relay
    elif [[ -L $pty ]]; then
      need_start=0
    else
      print -u2 "ux-screen: relay pid $relpid has no $pty; restart"
      stop_ux_relay
    fi
  fi
fi

if (( need_start )); then
  nohup "$relay" "$dev" "$pty" >>"/tmp/ux-relay-${UID}.log" 2>&1 &
  relpid=$!
  print -r -- "$relpid" > "$pidfile"
  print -r -- "$dev" > "$devfile"
  ok=0
  for _ in {1..50}; do
    if [[ -L $pty ]]; then
      ok=1
      break
    fi
    sleep 0.05
  done
  if (( ! ok )); then
    print -u2 "ux-screen: relay did not create $pty"
    stop_ux_relay
    exit 1
  fi
  print -u2 "UX Module  $dev  via $pty  115200 8N1 RX/TX  (C-a s send / C-a r receive XMODEM)"
  print -u2 "first open of $dev pulses DTR (/RES). Wait for UX Module Initialised."
else
  print -u2 "UX Module  $dev  via $pty  115200 8N1 RX/TX  (C-a s send / C-a r receive XMODEM)"
  print -u2 "relay pid $relpid already holds $dev  (DTR not pulsed)"
fi
print -u2 "if XMODEM leaves a dead window: C-a k, then run this script again"
print -u2 "quit screen does not close the relay. ux-load.sh stops it before a download."
# Named session so a later ux-screen reattaches. A second
# `screen $pty` exclusive-opens the slave and used to kill the relay.
# No baud flags: Apple screen then treats the PTY as a modem.
sock="uxmod"
(
  slave="$(readlink "$pty" 2>/dev/null || true)"
  for _ in {1..20}; do
    [[ -n $slave && -e $slave ]] || break
    stty -f "$slave" -ixon -ixoff -echo -icanon 2>/dev/null && break
    sleep 0.1
  done
) &
if /usr/bin/screen -ls 2>/dev/null | grep -q "\.${sock}"; then
  print -u2 "reattach session $sock (FTDI already open)"
  /usr/bin/screen -d -r "$sock" || true
else
  /usr/bin/screen -S "$sock" -fn -c "$rc" "$pty" || true
fi
