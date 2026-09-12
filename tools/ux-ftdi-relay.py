#!/usr/bin/env python3
"""Relay a PTY to an FT232 and keep DTR released.

SparkFun FTDI Basic pin 6 is DTR# → Propeller /RES. macOS asserts DTR
on open of /dev/cu.usbserial-*. This process must stay on the serial
node: close/open pulses /RES. Do not exit when GNU screen attach/detach
changes the PTY.

Usage: ux-ftdi-relay.py /dev/cu.usbserial-XXXX /tmp/ux-pty
"""
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
import traceback


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
    """Clear DTR. Call only after tcsetattr; TIOCMBIC too early is ENXIO."""
    try:
        buf = bytearray(struct.pack('i', 0))
        fcntl.ioctl(fd, termios.TIOCMGET, buf, True)
        m = struct.unpack('i', buf)[0]
        m &= ~termios.TIOCM_DTR
        fcntl.ioctl(fd, termios.TIOCMSET, struct.pack('i', m))
        return None
    except (OSError, termios.error) as e:
        try:
            fcntl.ioctl(fd, termios.TIOCMBIC, struct.pack('i', termios.TIOCM_DTR))
            return None
        except (OSError, termios.error):
            return e


def write_all(fd, data):
    view = memoryview(data)
    while view:
        try:
            n = os.write(fd, view)
        except OSError as e:
            if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                select.select([], [fd], [], 0.5)
                continue
            raise
        if n <= 0:
            raise OSError(errno.EPIPE, 'short write')
        view = view[n:]


def set_winsize(fd, rows=40, cols=80):
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
    except (OSError, termios.error):
        pass


def main():
    if len(sys.argv) != 3:
        die('usage: ux-ftdi-relay.py SERIAL PTY_LINK')
    serial_path, link = sys.argv[1], sys.argv[2]

    # Leave the ux-screen tty process group so C-c / hangup cannot
    # stop this process. Same PID so the pidfile stays valid.
    try:
        os.setsid()
    except OSError:
        pass

    sfd = os.open(serial_path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    raw_tty(sfd, hupcl=False)
    err = None
    for _ in range(20):
        err = dtr_release(sfd)
        if err is None:
            break
        time.sleep(0.02)
    if err is not None:
        print(f'ux-ftdi-relay: DTR release: {err}', file=sys.stderr)

    master, slave = pty.openpty()
    raw_tty(master, hupcl=False)
    raw_tty(slave, hupcl=False)
    set_winsize(master)
    set_winsize(slave)
    fcntl.fcntl(master, fcntl.F_SETFL, os.O_NONBLOCK)
    slave_name = os.ttyname(slave)
    try:
        os.unlink(link)
    except FileNotFoundError:
        pass
    os.symlink(slave_name, link)
    # Screen owns the slave. A second open with TIOCEXCL makes tcgetattr
    # on this fd fail (ENOTTY) and used to kill the relay → DTR pulse.
    os.close(slave)

    stop = False

    def on_stop(signum, frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, on_stop)
    signal.signal(signal.SIGTERM, on_stop)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)

    try:
        while not stop:
            try:
                r, _, _ = select.select([sfd, master], [], [], 0.5)
            except (OSError, ValueError) as e:
                print(f'ux-ftdi-relay: select: {e}', file=sys.stderr)
                time.sleep(0.1)
                continue
            if sfd in r:
                try:
                    data = os.read(sfd, 1024)
                except OSError as e:
                    if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                        data = b''
                    elif e.errno in (errno.ENXIO, errno.ENODEV, errno.EIO):
                        die(f'serial gone: {e}')
                    else:
                        print(f'ux-ftdi-relay: serial read: {e}', file=sys.stderr)
                        data = b''
                if data:
                    try:
                        write_all(master, data)
                    except OSError as e:
                        # No screen on the slave yet, or PTY buffer full.
                        if e.errno not in (errno.EIO, errno.EAGAIN, errno.EWOULDBLOCK):
                            print(f'ux-ftdi-relay: pty write: {e}', file=sys.stderr)
            if master in r:
                try:
                    data = os.read(master, 1024)
                except OSError as e:
                    if e.errno in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EIO):
                        data = b''
                    else:
                        print(f'ux-ftdi-relay: pty read: {e}', file=sys.stderr)
                        data = b''
                if data:
                    try:
                        write_all(sfd, data)
                    except OSError as e:
                        print(f'ux-ftdi-relay: serial write: {e}', file=sys.stderr)
    except Exception:
        traceback.print_exc()
        die('unexpected exit')
    finally:
        dtr_release(sfd)
        try:
            os.unlink(link)
        except FileNotFoundError:
            pass
        os.close(master)
        os.close(sfd)


if __name__ == '__main__':
    main()
