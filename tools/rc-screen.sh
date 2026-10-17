#!/bin/zsh
# RC2014 ACIA console via GNU screen on USB CDC or FTDI.
# Direct attach to /dev/cu.usbmodem* (CDC ACM) or /dev/cu.usbserial*
# (FTDI). 115200 8N2. RTS/CTS on. No XON/XOFF (XMODEM). No FTDI
# relay. No serial_probe. screen has no crtscts option. Apple screen
# clears the second stop bit on open. Set cstopb and crtscts on
# the open node after screen starts.
#
# SparkFun FTDI on the UX Module has Propeller /RES on DTR. Use
# ux-screen for that port so the relay holds DTR off. A Z80 RC2014
# serial module on FTDI is a normal console. rc-screen opens it.
#
# Usage:
#   rc-screen
#   rc-screen /dev/cu.usbmodem01031
#   rc-screen /dev/cu.usbserial-A50285BI
#   rc-screen A50285BI
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

list_ports() {
  setopt localoptions nullglob
  local p
  for p in /dev/cu.usbserial* /dev/cu.usbmodem*; do
    [[ -e "$p" ]] && print -r -- "$p"
  done
}

port_kind() {
  case "$1" in
    *usbmodem*) print CDC ;;
    *usbserial*) print FTDI ;;
    *) print serial ;;
  esac
}

match_port() {
  local want="$1" p
  [[ -e "$want" ]] && { print -r -- "$want"; return 0 }
  [[ "$want" != */* ]] || return 1
  list_ports | while read -r p; do
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

  found=("${(@f)$(list_ports)}")
  # An empty command substitution still leaves one blank array slot.
  if (( ${#found} == 1 )) && [[ -z "${found[1]}" ]]; then
    found=()
  fi

  if [[ -n "$want" ]]; then
    matches=("${(@f)$(match_port "$want")}")
    if (( ${#matches} == 1 )) && [[ -z "${matches[1]}" ]]; then
      matches=()
    fi
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
    print -u2 "rc-screen: no /dev/cu.usbmodem* or /dev/cu.usbserial*"
    return 1
  fi
  if (( ${#found} == 1 )); then
    print -r -- "${found[1]}"
    return 0
  fi

  print -u2 "rc-screen: ${#found} serial devices; one per session:"
  n=1
  for p in "${found[@]}"; do
    print -u2 "  $n) $p  ($(port_kind "$p"))"
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
  local d="$1"
  if relay_holds "$d"; then
    die "$d is held by ux-ftdi-relay (session uxmod). Stop that path first:
  $screenbin -S uxmod -X quit
  ux-screen --stop"
  fi
  if [[ "$d" == *usbserial* ]]; then
    print -u2 "rc-screen: $d is FTDI. macOS asserts DTR on open."
    print -u2 "use ux-screen if this is the SparkFun Propeller /RES port."
  fi
}

prep_line() {
  local d="$1"
  # Pre-set the node. Apple screen still applies the baud argument on open
  # and clears crtscts. enable_hw_flow sets RTS/CTS again after open.
  stty -f "$d" "$baud" raw cs8 cstopb -parenb -echo -ixon -ixoff clocal cread crtscts 2>/dev/null \
    || die "stty failed on $d (busy or missing)"
}

# screen line flags are baud, cs8, ixon, ixoff. crtscts is not one of them.
# Set RTS/CTS on the open node. macOS stty uses -f. Keep XON/XOFF off.
hw_flow_on() {
  local d="$1"
  stty -f "$d" -a 2>/dev/null | tr ' \t' '\n\n' | grep -qx crtscts
}

# AppleUSBFTDI clears termios CRTSCTS. SET_FLOW arms RTS/CTS in the FT232.
ftdi_set_flow() {
  python3 - "$1" << 'PY'
import ctypes, os, sys
def ftdi_rtscts(serial_path):
    marker = "usbserial-"
    if marker not in serial_path:
        return "not-ftdi"
    want = os.path.basename(serial_path).split(marker, 1)[1]
    libpath = None
    for cand in ("/opt/homebrew/lib/libusb-1.0.dylib", "/usr/local/lib/libusb-1.0.dylib"):
        if os.path.exists(cand):
            libpath = cand
            break
    if not libpath:
        return "libusb missing"
    u8 = ctypes.c_uint8
    u16 = ctypes.c_uint16
    vp = ctypes.c_void_p
    class Desc(ctypes.Structure):
        _fields_ = [
            ("bLength", u8), ("bDescriptorType", u8), ("bcdUSB", u16),
            ("bDeviceClass", u8), ("bDeviceSubClass", u8),
            ("bDeviceProtocol", u8), ("bMaxPacketSize0", u8),
            ("idVendor", u16), ("idProduct", u16), ("bcdDevice", u16),
            ("iManufacturer", u8), ("iProduct", u8),
            ("iSerialNumber", u8), ("bNumConfigurations", u8),
        ]
    lib = ctypes.CDLL(libpath)
    lib.libusb_init.argtypes = [ctypes.POINTER(vp)]
    lib.libusb_init.restype = ctypes.c_int
    lib.libusb_exit.argtypes = [vp]
    lib.libusb_get_device_list.argtypes = [vp, ctypes.POINTER(ctypes.POINTER(vp))]
    lib.libusb_get_device_list.restype = ctypes.c_ssize_t
    lib.libusb_free_device_list.argtypes = [ctypes.POINTER(vp), ctypes.c_int]
    lib.libusb_get_device_descriptor.argtypes = [vp, ctypes.POINTER(Desc)]
    lib.libusb_get_device_descriptor.restype = ctypes.c_int
    lib.libusb_open.argtypes = [vp, ctypes.POINTER(vp)]
    lib.libusb_open.restype = ctypes.c_int
    lib.libusb_close.argtypes = [vp]
    lib.libusb_get_string_descriptor_ascii.argtypes = [vp, u8, ctypes.c_char_p, ctypes.c_int]
    lib.libusb_get_string_descriptor_ascii.restype = ctypes.c_int
    lib.libusb_control_transfer.argtypes = [vp, u8, u8, u16, u16, ctypes.POINTER(u8), u16, ctypes.c_uint]
    lib.libusb_control_transfer.restype = ctypes.c_int
    ctx = vp()
    if lib.libusb_init(ctypes.byref(ctx)):
        return "libusb_init failed"
    lst = ctypes.POINTER(vp)()
    n = lib.libusb_get_device_list(ctx, ctypes.byref(lst))
    msg = "no matching FTDI"
    try:
        for i in range(max(n, 0)):
            dev = lst[i]
            desc = Desc()
            if lib.libusb_get_device_descriptor(dev, ctypes.byref(desc)) or desc.idVendor != 0x0403:
                continue
            handle = vp()
            if lib.libusb_open(dev, ctypes.byref(handle)) or not handle:
                continue
            try:
                raw = ctypes.create_string_buffer(64)
                nr = lib.libusb_get_string_descriptor_ascii(handle, desc.iSerialNumber, raw, 64)
                if (raw.value.decode() if nr > 0 else "") != want:
                    continue
                buf = (u8 * 2)()
                sr = lib.libusb_control_transfer(handle, 0x40, 2, 0, 0x0100, None, 0, 1000)
                lib.libusb_control_transfer(handle, 0xC0, 5, 0, 0, buf, 2, 1000)
                msg = f"SET_FLOW {sr} modem {buf[0]:02x}{buf[1]:02x} CTS {int(bool(buf[0] & 0x10))}"
                break
            finally:
                lib.libusb_close(handle)
    finally:
        if n >= 0:
            lib.libusb_free_device_list(lst, 1)
        lib.libusb_exit(ctx)
    return msg
print(ftdi_rtscts(sys.argv[1]))
PY
}

enable_hw_flow() {
  local d="$1" msg _
  for _ in {1..10}; do
    stty -f "$d" crtscts cstopb -ixon -ixoff 2>/dev/null || true
    hw_flow_on "$d" && return 0
    sleep 0.05
  done
  if [[ "$d" == *usbserial-* ]]; then
    msg="$(ftdi_set_flow "$d" 2>/dev/null || true)"
    print -u2 "rc-screen: $msg"
    [[ "$msg" == *"SET_FLOW 0"* ]] && return 0
  fi
  return 1
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
  local -a found
  local p line
  print -u2 "devices:"
  found=("${(@f)$(list_ports)}")
  if (( ${#found} == 1 )) && [[ -z "${found[1]}" ]]; then
    found=()
  fi
  if (( ${#found} )); then
    for p in "${found[@]}"; do
      if relay_holds "$p"; then
        print -u2 "  $p  ($(port_kind "$p"), held by ux-ftdi-relay / uxmod)"
      else
        print -u2 "  $p  ($(port_kind "$p"))"
      fi
    done
  else
    print -u2 "  (none)"
  fi
  print -u2 "sockets: $SCREENDIR"
  line="$(session_line)"
  if [[ -n "$line" ]]; then
    print -u2 "session:${line}"
    print -u2 "id:      $(session_id)"
    if [[ -f $devfile ]]; then
      print -u2 "device:  $(<"$devfile")  ($(port_kind "$(<"$devfile")"))"
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
  local live
  if [[ ! -f $rc ]]; then
    die "missing $rc"
  fi
  if session_exists; then
    live="$(current_dev || true)"
    if [[ -n "$live" && "$live" != "$dev" ]]; then
      die "session $sock is on $live. --quit first, then attach $dev"
    fi
    if ! enable_hw_flow "$dev"; then
      die "hardware flow (crtscts) did not stay set on $dev"
    fi
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
  print -u2 "RC2014  $dev  $(port_kind "$dev")  $baud 8N2 crtscts  session $sock"
  print -u2 "XMODEM: C-a s send / C-a r receive, or ${me:t} --send FILE"
  # Baud must be a screen argument. Without it Apple 4.00.03 resets the
  # node to 9600 and CP/M 115200 reads as 8-bit garbage. CDC DTR is not
  # Propeller /RES. FTDI open on macOS does assert DTR.
  # Start detached so the node is open, then set crtscts. A foreground
  # screen does not return until detach, so stty cannot run after it.
  local line="${baud},cs8,-ixon,-ixoff"
  $screenbin -d -m -S "$sock" -fn -c "$rc" "$dev" "$line" || die "screen failed to start"
  if ! session_exists; then
    rm -f "$devfile"
    die "screen did not create session $sock"
  fi
  if ! enable_hw_flow "$dev"; then
    $screenbin -S "$sock" -X quit 2>/dev/null || true
    rm -f "$devfile"
    die "hardware flow (crtscts) did not stay set on $dev"
  fi
  if [[ -t 0 ]]; then
    $screenbin -d -r "$sock" || true
  else
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
