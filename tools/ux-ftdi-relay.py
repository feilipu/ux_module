#!/usr/bin/env python3
"""Relay a PTY to an FT232 and keep DTR released.

SparkFun FTDI Basic pin 6 is DTR# → Propeller /RES. macOS asserts DTR
on open of /dev/cu.usbserial-*, which holds the chip in reset. GNU
screen talks to the PTY, not the FTDI, so it cannot raise DTR.

Usage: ux-ftdi-relay.py /dev/cu.usbserial-XXXX /tmp/ux-pty
"""
import array
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

def die(msg, code=1):
    print(f'ux-ftdi-relay: {msg}', file=sys.stderr)
    sys.exit(code)


def raw_tty(fd, baud=termios.B115200, hupcl=False):
    iflag, oflag, cflag, lflag, ispeed, ospeed, cc = termios.tcgetattr(fd)
    iflag = oflag = lflag = 0
    cflag &= ~(termios.CSIZE | termios.PARENB | termios.CSTOPB | termios.CRTSCTS)
    cflag |= termios.CS8 | termios.CREAD | termios.CLOCAL
    if hupcl:
        cflag |= termios.HUPCL
    else:
        cflag &= ~termios.HUPCL
    cc[termios.VMIN] = 0
    cc[termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, [iflag, oflag, cflag, lflag, baud, baud, cc])


def dtr_release(fd):
    try:
        fcntl.ioctl(fd, termios.TIOCMBIC, struct.pack('i', termios.TIOCM_DTR))
    except OSError as e:
        print(f'ux-ftdi-relay: TIOCMBIC DTR: {e}', file=sys.stderr)


def main():
    if len(sys.argv) != 3:
        die('usage: ux-ftdi-relay.py SERIAL PTY_LINK')
    serial_path, link = sys.argv[1], sys.argv[2]

    sfd = os.open(serial_path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    raw_tty(sfd, hupcl=False)
    dtr_release(sfd)

    master, slave = pty.openpty()
    raw_tty(master, hupcl=False)
    raw_tty(slave, hupcl=False)
    fcntl.fcntl(master, fcntl.F_SETFL, os.O_NONBLOCK)
    slave_name = os.ttyname(slave)
    try:
        os.unlink(link)
    except FileNotFoundError:
        pass
    os.symlink(slave_name, link)

    stop = False

    def on_stop(signum, frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, on_stop)
    signal.signal(signal.SIGTERM, on_stop)
    signal.signal(signal.SIGHUP, on_stop)

    try:
        while not stop:
            r, _, x = select.select([sfd, master], [], [sfd, master], 0.5)
            if x:
                break
            if sfd in r:
                try:
                    data = os.read(sfd, 1024)
                except OSError as e:
                    if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                        data = b''
                    else:
                        break
                if not data:
                    break
                os.write(master, data)
            if master in r:
                try:
                    data = os.read(master, 1024)
                except OSError as e:
                    if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                        data = b''
                    else:
                        break
                if not data:
                    break
                os.write(sfd, data)
    finally:
        dtr_release(sfd)
        try:
            os.unlink(link)
        except FileNotFoundError:
            pass
        os.close(master)
        os.close(slave)
        os.close(sfd)


if __name__ == '__main__':
    main()
