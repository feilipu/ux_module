#!/usr/bin/env python3
"""Headless FTDI probe for the UX Module.

Logs bytes sent to the board and bytes that come back. Holds DTR
released so macOS open() does not keep Propeller /RES asserted
(SparkFun FTDI Basic pin 6). Same hang-up issue as serial_tool.py.

Quit GNU screen / tools/ux-screen.sh first. The port must be free.

Examples:
  tools/serial_probe.py                      # wait for banner
  tools/serial_probe.py ABC123               # send ABC123 (no CR)
  tools/serial_probe.py $'hello\\r'          # send hello + CR
  tools/serial_probe.py --hex $'xyz\\r'
  tools/serial_probe.py --listen 3
"""

from __future__ import annotations

import argparse
import array
import errno
import fcntl
import glob
import os
import select
import struct
import sys
import termios
import time


def pick_port(want: str | None) -> str:
    found = sorted(glob.glob('/dev/cu.usbserial*') + glob.glob('/dev/cu.usbmodem*'))
    ft232 = [p for p in found if 'usbserial' in p]
    if want:
        if os.path.exists(want):
            return want
        hits = [p for p in found if want in p]
        if len(hits) == 1:
            return hits[0]
        die(f'no serial device matching {want}')
    if len(ft232) == 1:
        return ft232[0]
    if len(found) == 1:
        return found[0]
    if not found:
        die('no /dev/cu.usbserial* or /dev/cu.usbmodem*')
    die('several serial devices; pass a path: ' + ' '.join(found))


def die(msg: str, code: int = 1) -> None:
    print(f'serial_probe: {msg}', file=sys.stderr)
    sys.exit(code)


def raw_serial(fd: int) -> None:
    iflag, oflag, cflag, lflag, ispeed, ospeed, cc = termios.tcgetattr(fd)
    iflag = oflag = lflag = 0
    cflag &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB | termios.CRTSCTS)
    cflag |= termios.CS8 | termios.CREAD | termios.CLOCAL
    cflag &= ~termios.HUPCL
    cc[termios.VMIN] = 0
    cc[termios.VTIME] = 0
    termios.tcsetattr(
        fd, termios.TCSANOW,
        [iflag, oflag, cflag, lflag, termios.B115200, termios.B115200, cc],
    )


def modem_line(fd: int, mask: int) -> bool:
    buf = array.array('i', [0])
    fcntl.ioctl(fd, termios.TIOCMGET, buf)
    return bool(buf[0] & mask)


def dtr_release(fd: int) -> None:
    fcntl.ioctl(fd, termios.TIOCMBIC, struct.pack('i', termios.TIOCM_DTR))


def show_bytes(tag: str, data: bytes, use_hex: bool) -> None:
    if not data:
        print(f'{tag}  (0)')
        return
    ascii_view = ''.join(
        ch if 32 <= b < 127 else {10: '<LF>', 13: '<CR>'}.get(b, f'<{b:02X}>')
        for b, ch in ((n, chr(n)) for n in data)
    )
    print(f'{tag}  ({len(data)})  {data!r}')
    print(f'{tag}  ascii  {ascii_view}')
    if use_hex:
        print(f'{tag}  hex    {data.hex(" ")}')


def read_for(fd: int, secs: float) -> bytes:
    end = time.time() + secs
    buf = bytearray()
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], max(0.0, end - time.time()))
        if not r:
            continue
        try:
            chunk = os.read(fd, 1024)
        except OSError as e:
            if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                continue
            raise
        if chunk:
            buf.extend(chunk)
    return bytes(buf)


def decode_payload(text: str) -> bytes:
    """Accept shell-style escapes: \\r \\n \\x1b."""
    return text.encode('utf-8').decode('unicode_escape').encode('latin1')


def main() -> int:
    ap = argparse.ArgumentParser(description='UX Module serial TX/RX probe (DTR held off)')
    ap.add_argument('text', nargs='?', help='bytes to send (use \\r for CR)')
    ap.add_argument('-p', '--port', help='cu.usbserial-* path or unique suffix')
    ap.add_argument('-w', '--wait', type=float, default=2.5, help='seconds to wait for banner after open')
    ap.add_argument('-t', '--dwell', type=float, default=0.8, help='seconds to read after send')
    ap.add_argument('--listen', type=float, metavar='SEC', help='receive only for SEC seconds')
    ap.add_argument('--hex', action='store_true', help='also print hex')
    ap.add_argument('--no-wait', action='store_true', help='do not wait for a banner')
    args = ap.parse_args()

    port = pick_port(args.port)
    try:
        fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError as e:
        die(f'{port}: {e.strerror} (quit ux-screen.sh first)')

    try:
        raw_serial(fd)
        dtr_on = modem_line(fd, termios.TIOCM_DTR)
        dtr_release(fd)
        dtr_now = modem_line(fd, termios.TIOCM_DTR)
        print(f'port  {port}  115200 8N1')
        print(f'dtr   open={"on" if dtr_on else "off"}  now={"on" if dtr_now else "off"}  (/RES when on)')

        payload = b''
        if args.text is not None:
            payload = decode_payload(args.text)
        elif not sys.stdin.isatty():
            payload = sys.stdin.buffer.read()

        if args.listen is not None:
            show_bytes('RX', read_for(fd, args.listen), args.hex)
            return 0

        if not args.no_wait:
            boot = read_for(fd, args.wait)
            show_bytes('BOOT', boot, args.hex)

        if payload:
            os.write(fd, payload)
            show_bytes('TX', payload, args.hex)
            show_bytes('RX', read_for(fd, args.dwell), args.hex)
        elif args.no_wait:
            show_bytes('RX', read_for(fd, args.dwell), args.hex)
        return 0
    finally:
        try:
            dtr_release(fd)
        except OSError:
            pass
        os.close(fd)


if __name__ == '__main__':
    sys.exit(main())
