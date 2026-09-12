# To reset the Propeller, without unplugging the FTDI interface, then this DTR toogle tool can be used.

import serial

path = '/dev/ttyUSB0'
baud = 115200

# Open serial port
ser = serial.Serial(path, baud)

if(ser.isOpen() == False):
    print("Serial port open failed.\n");
    exit;

ser.setDTR(True);
ser.setDTR(False);
ser.close();

