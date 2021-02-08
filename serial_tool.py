import sys
import serial

from time import sleep

path = '/dev/ttyUSB0'
baud = 115200

# OPTION A
# To disable /RESET after hangup
#
# import termios
# with open(path) as f:
#    attrs = termios.tcgetattr(f)
#    attrs[2] = attrs[2] & ~termios.HUPCL
#    termios.tcsetattr(f, termios.TCSAFLUSH, attrs)

# OPTION B
# To disable /RESET after hangup
#
# import os
# os.system("stty -F /dev/ttyUSB0 -hupcl")

# OPTION C
# Disconnect the GRN pin from the FTDI interface


# Open serial port
ser = serial.Serial(path, baud, dsrdtr=False)

# Optionally check characteristics of serial port
# print(ser)

for line in sys.stdin:

    for ch in line:
        ser.write( ch );

    ser.write('\r');
    ser.flush();
    sleep(0.01);

ser.close()
sys.exit()
