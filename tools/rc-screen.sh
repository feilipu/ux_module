#!/bin/zsh
# RC2014 ACIA console via GNU screen on USB CDC.
# Direct attach to /dev/cu.usbmodem* (8086net / similar). 115200 8N1,
# RX/TX only. No XON/XOFF (XMODEM). No FTDI relay. No serial_probe.
#
# SparkFun FTDI (/dev/cu.usbserial-*) is Propeller /RES on DTR.
# Use ux-screen for that port.
#
# Usage:
#   rc-screen
#   rc-screen /dev/cu.usbmodem01031
#   rc-screen 01031
#   rc-screen --list
#   rc-screen --quit
#   rc-screen --send FILE
#   rc-screen --send --1k FILE
#   rc-screen --recv FILE
# Detach: C-a d    Quit: C-a k
# XMODEM send:    C-a s   then file path
# XMODEM receive: C-a r   then file path
# Agent send:     CP/M  xmodem NAME /r /q
#                 then  rc-screen --send FILE

set -euo pipefail

me="${0:A}"
here="${me:h}"
export PATH="/opt/homebrew/bin:$HOME/bin:$PATH"

sock="rc2014"
baud="${RC_SCREEN_BAUD:-115200}"
devfile="/tmp/rc-screen-${UID}.dev"
screenbin="/usr/bin/screen"
# Apple screen 4.00.03 keeps sockets in $TMPDIR/.screen. That path
# changes per Terminal / agent, so `screen -S rc2014` then fails.
# Keep one directory so every shell sees the same session.
screendir="${RC_SCREEN_DIR:-$HOME/.screen-rc2014}"
mkdir -p -m 700 "$screendir"
export SCREENDIR="$screendir"
if [[ -n "${RC_SCREEN_RC:-}" && -f ${RC_SCREEN_RC} ]]; then
  rc="$RC_SCREEN_RC"
elif [[ -f $HOME/.screenrc-rc ]]; then
  rc="$HOME/.screenrc-rc"
elif [[ -f $here/screenrc-rc ]]; then
  rc="$here/screenrc-rc"
else
  rc="$HOME/.screenrc-rc"
fi

usage() {
  print -u2 "usage: ${me:t} [device|suffix]"
  print -u2 "       ${me:t} --list | --quit"
  print -u2 "       ${me:t} --send [--1k] FILE"
  print -u2 "       ${me:t} --recv FILE"
  print -u2 "       ${me:t} --stuff STRING"
  print -u2 "       ${me:t} --hardcopy [FILE]"
}

die() {
  print -u2 "rc-screen: $*"
  exit 1
}

list_cdc() {
  setopt localoptions nullglob
  local p
  for p in /dev/cu.usbmodem*; do
    [[ -e "$p" ]] && print -r -- "$p"
  done
}

list_all() {
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
  list_all | while read -r p; do
    [[ "$p" == *"$want"* ]] && print -r -- "$p"
  done
}

session_line() {
  $screenbin -ls 2>/dev/null | grep "\.${sock}" || true
}

session_id() {
  local ids
  ids="$($screenbin -ls 2>/dev/null || true)"
  if [[ "$ids" =~ ([0-9]+\.${sock}) ]]; then
    print -r -- "$match[1]"
  fi
  return 0
}

session_exists() {
  [[ -n "$(session_id)" ]]
}

screen_x() {
  local id
  id="$(session_id)"
  [[ -n $id ]] || die "no session $sock (SCREENDIR=$SCREENDIR). Start with rc-screen"
  $screenbin -S "$id" -X "$@"
}

pick_port() {
  local -a found matches
  local want="${1:-${RC_SCREEN_DEV:-}}" p n

  found=("${(@f)$(list_cdc)}")

  if [[ -n "$want" ]]; then
    matches=("${(@f)$(match_port "$want")}")
    if (( ${#matches} == 1 )); then
      print -r -- "${matches[1]}"
      return 0
    fi
    if (( ${#matches} == 0 )); then
      die "no serial device matching $want"
    fi
    print -u2 "rc-screen: $want matches more than one device:"
    print -u2 "  ${matches[@]}"
    return 1
  fi

  if (( ${#found} == 0 )); then
    print -u2 "rc-screen: no /dev/cu.usbmodem*"
    local -a other
    other=("${(@f)$(list_all)}")
    if (( ${#other} )); then
      print -u2 "other serial devices (FTDI uses ux-screen):"
      print -u2 "  ${other[@]}"
    fi
    return 1
  fi
  if (( ${#found} == 1 )); then
    print -r -- "${found[1]}"
    return 0
  fi

  print -u2 "rc-screen: ${#found} CDC devices; one per session:"
  n=1
  for p in "${found[@]}"; do
    print -u2 "  $n) $p"
    (( n++ ))
  done
  if [[ ! -t 0 ]]; then
    print -u2 "pass a path or unique suffix, or set RC_SCREEN_DEV"
    return 1
  fi
  print -u2 -n "pick 1-${#found}: "
  read -r n || return 1
  if [[ "$n" != <-> ]] || (( n < 1 || n > ${#found} )); then
    die "bad pick"
  fi
  print -r -- "${found[n]}"
}

relay_holds() {
  local d="$1"
  local pidfile="/tmp/ux-relay-${UID}.pid"
  local rdev="/tmp/ux-relay-${UID}.dev"
  local pid
  [[ -f $rdev ]] || return 1
  [[ "$(<"$rdev")" == "$d" ]] || return 1
  [[ -f $pidfile ]] || return 1
  pid="$(<"$pidfile")"
  [[ "$pid" == <-> ]] && kill -0 "$pid" 2>/dev/null
}

assert_free_device() {
  local d="$1" pid
  if relay_holds "$d"; then
    die "$d is held by ux-ftdi-relay (session uxmod). Stop that path first:
  $screenbin -S uxmod -X quit
  ux-screen --stop"
  fi
  if [[ "$d" == *usbserial* ]]; then
    print -u2 "rc-screen: $d is FTDI. DTR may pulse Propeller /RES."
    print -u2 "prefer ux-screen for that port."
  fi
}

prep_line() {
  local d="$1"
  # Pre-set the node. Apple screen still applies the baud argument on open.
  stty -f "$d" "$baud" raw cs8 -cstopb -parenb -echo -ixon -ixoff clocal cread -crtscts 2>/dev/null \
    || die "stty failed on $d (busy or missing)"
}

remember_dev() {
  print -r -- "$1" > "$devfile"
}

current_dev() {
  if [[ -f $devfile ]]; then
    print -r -- "$(<"$devfile")"
    return 0
  fi
  return 1
}

need_lsx() {
  command -v lsx >/dev/null || die "lsx not on PATH (brew install lrzsz)"
  command -v lrx >/dev/null || die "lrx not on PATH (brew install lrzsz)"
}

need_session() {
  session_exists || die "no session $sock. Start it with rc-screen"
}

abs_file() {
  local f="$1"
  [[ -n "$f" ]] || die "missing file path"
  [[ "$f" != *[[:space:]]* ]] || die "file path has spaces; screen -X cannot quote them"
  f="${f:A}"
  [[ -e "$f" || "$2" == recv ]] || die "no such file $f"
  print -r -- "$f"
}

do_list() {
  local -a cdc all
  local line
  print -u2 "CDC (rc-screen):"
  cdc=("${(@f)$(list_cdc)}")
  if (( ${#cdc} )); then
    for p in "${cdc[@]}"; do
      if relay_holds "$p"; then
        print -u2 "  $p  (held by ux-ftdi-relay / uxmod)"
      else
        print -u2 "  $p"
      fi
    done
  else
    print -u2 "  (none)"
  fi
  all=("${(@f)$(list_all)}")
  if (( ${#all} != ${#cdc} )); then
    print -u2 "other (ux-screen / FTDI):"
    local p
    for p in "${all[@]}"; do
      [[ "$p" == *usbmodem* ]] || print -u2 "  $p"
    done
  fi
  print -u2 "sockets: $SCREENDIR"
  line="$(session_line)"
  if [[ -n "$line" ]]; then
    print -u2 "session:${line}"
    print -u2 "id:      $(session_id)"
    if [[ -f $devfile ]]; then
      print -u2 "device:  $(<"$devfile")"
    fi
  else
    print -u2 "session: (none)"
  fi
}

do_quit() {
  local id
  id="$(session_id)"
  if [[ -z $id ]]; then
    rm -f "$devfile"
    print -u2 "rc-screen: no session $sock (SCREENDIR=$SCREENDIR)"
    return 0
  fi
  $screenbin -S "$id" -X quit || true
  sleep 0.15
  rm -f "$devfile"
  if session_exists; then
    die "session $id still listed"
  fi
  print -u2 "rc-screen: session $id quit"
}

do_send() {
  local k1k=0 file lsxbin
  if [[ "${1:-}" == --1k || "${1:-}" == -k ]]; then
    k1k=1
    shift
  fi
  need_session
  need_lsx
  file="$(abs_file "${1:-}")"
  lsxbin="$(command -v lsx)"
  if (( k1k )); then
    screen_x exec !! "$lsxbin" -b -q -X -k --delay-startup 1 "$file"
  else
    screen_x exec !! "$lsxbin" -b -q -X --delay-startup 1 "$file"
  fi
  print -u2 "rc-screen: XMODEM send $file"
}

do_recv() {
  local file lrxbin
  need_session
  need_lsx
  file="$(abs_file "${1:-}" recv)"
  lrxbin="$(command -v lrx)"
  screen_x exec !! "$lrxbin" -b -q -X --delay-startup 1 "$file"
  print -u2 "rc-screen: XMODEM receive $file"
}

do_stuff() {
  [[ -n "${1:-}" ]] || die "missing stuff string"
  screen_x stuff "$1"
}

do_hardcopy() {
  local f="${1:-/tmp/rc2014-${UID}.hardcopy}"
  f="${f:A}"
  rm -f "$f"
  screen_x hardcopy "$f"
  print -u2 "rc-screen: hardcopy $f"
}

start_or_attach() {
  local dev="$1"
  if [[ ! -f $rc ]]; then
    die "missing $rc"
  fi
  if session_exists; then
    if [[ -t 0 ]]; then
      print -u2 "rc-screen: reattach session $sock"
      $screenbin -d -r "$sock" || true
    else
      print -u2 "rc-screen: session $sock already running"
      print -u2 -- "$(session_line)"
    fi
    return 0
  fi
  assert_free_device "$dev"
  prep_line "$dev"
  remember_dev "$dev"
  print -u2 "RC2014  $dev  $baud 8N1 RX/TX  session $sock"
  print -u2 "XMODEM: C-a s send / C-a r receive, or ${me:t} --send FILE"
  # Baud must be a screen argument. Without it Apple 4.00.03 resets the
  # node to 9600 and CP/M 115200 reads as 8-bit garbage. CDC DTR is not
  # Propeller /RES, so the modem open is acceptable here.
  local line="${baud},cs8,-ixon,-ixoff"
  if [[ -t 0 ]]; then
    $screenbin -S "$sock" -fn -c "$rc" "$dev" "$line" || true
  else
    $screenbin -d -m -S "$sock" -fn -c "$rc" "$dev" "$line" || die "screen failed to start"
    if ! session_exists; then
      rm -f "$devfile"
      die "screen did not create session $sock"
    fi
    print -u2 "started detached. Attach with ${me}"
  fi
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --list)
    do_list
    exit 0
    ;;
  --quit|--stop)
    do_quit
    exit 0
    ;;
  --send)
    shift
    do_send "$@"
    exit 0
    ;;
  --recv)
    shift
    do_recv "$@"
    exit 0
    ;;
  --stuff)
    shift
    do_stuff "${1:-}"
    exit 0
    ;;
  --hardcopy)
    shift
    do_hardcopy "${1:-}"
    exit 0
    ;;
  --*)
    usage
    die "unknown flag $1"
    ;;
esac

dev="$(pick_port "${1:-}")" || exit 1
start_or_attach "$dev"
