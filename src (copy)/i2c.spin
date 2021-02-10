{{
 i2cDriver. Provide bus-level and chip-level methods for I2C bus communication.
 Erlend Fj. 2015, 2016
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------

 Supports standard 7 bit chip addressing, and both 8bit, 16bit, and 32bit register addressing. Use of 32bit is rare.
 Assumes the caller uses the chip address 7 bit format, onto which a r/w bit is added by the code before being transmitted.
 Signalling 'Open Collector Style' is achieved by setting pins OUTA := 0 permanent, and then manipulate on DIRA to either
 float the output, i.e. let PU resistor pull up to '1' -or- unfloat the output (which was set to 0) to bring it down to '0'

 Revisions:
 - Changed DAT assignment of scl and sda pins
 - Added BusInitialized flag
 - Added object instance identifier
 - Added isBusy
 - Added self-demo PUB Main

-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
}}
{
 Acknowledgements: I have mainly built upon the work of Jon "JonnyMac" McPhalen

=======================================================================================================================================================================


      Propeller
   +-------------+
   |             +-------+  3.3V  +------------------------------------------------------// -----------------------------------+
   |             |  |  |                 |                              |                                 |                |   |
   |             |  |  |               +-----------+                  +-----------+                     +-----------+      |   |
   |             |  |  |               | V+        |                  | V+        |                     | V+        |      |   |
   |   master    |  |  +               |           |                  |           |                     |           |      +   |
   |             |  | 4k7              | Chip/slave|                  | Chip/slave|                     | Chip/slave|     4k7  |
   |             |  +  +  Pull-up      |           |                  |           |                     |           |      +   |
   |             | 4k7 |               |SDA SCL GND|                  |SDA SCL GND|                     |SDA SCL GND|      |   +
   |             |  +  |               +-----------+                  +-----------+                     +-----------+      |  4k7
   |             |  |  |                 |   |   |                      |   |   |                         |   |   |        |   +
   |             |  |  |                 |   |   |                      |   |   |                         |   |   |        |   |
   |             |  |  |                 |   |   |                      |   |   |                         |   |   |        |   |
   |      PINsda +-----------------------------------------------------------------------// -------------------------------+   |
   |             |     |  I2C Bus            |   |                          |   |                             |   |            |
   |      PINscl +-----------------------------------------------------------------------// -----------------------------------+
   |             |                               |                              |                                 |
   |         GND +-----------------------------------------------------------------------// ----------------------+
   |             |
   +-------------+

 About I2C
 ---------
 Both the SCL and the SDA line needs to be pulled up by p-u resistors. Value not critical for such slow speeds that Spin can do, but should be in the order of 1k-47k.
 With long lines have p-u resistors at each node to reduce noise or interference.

 REF:
 http://www.8051projects.net/wiki/I2C_TWI_Tutorial
 http://i2c.info/i2c-bus-specification

=======================================================================================================================================================================
}

CON

          mSec = 117965                                             ' ticks in 1ms = 7,372,800 * 16 xin * pll / 1_000
          uSec = 118                                                ' ticks in 1us = 7,372,800 * 16 xin * pll / 1_000_000

CON

          ACK = 0                                                   'signals ready for more
          NAK = 1                                                   'signals not ready for more

CON

          SCL_PIN = 29                                              'This is reversed from standard pinout, to ensure that only the EEPROM
          SDA_PIN = 28                                              'appears on the I2C bus during boot process. Ensures no address conflicts.

DAT
          PINscl              LONG    0                             'Use DAT variable to make the assignment stick for later calls to the object, and optionally
          PINsda              LONG    0                             'assign to default pin numbers. Use init( ) to change at runtime. Best for many chips same one bus.
                                                                    'and assign to default pin numbers Use init( ) to change at runtime

          BusInitialized      LONG    FALSE                         'If this is not desired, change from defining PINmosi etc. as DAT to VAR, and
                                                                    'assign value to them in init( ) by means of 'PINmosi:= _PINmosi' etc. instead.
                                                                    'Best when many busses.

          ThisObjectInstance  LONG    1                             'Change to separate object loads for different physical buses

          fit


PUB init(_PINscl, _PINsda)

'INITIATION METHOD
'=================================================================================================================================================

   LONG[@PINscl]:= _PINscl                                          'Copy pin into DAT where it will survive
   LONG[@PINsda]:= _PINsda                                          'into later calls to this object

   DIRA[PINscl] := 0                                                'Float output
   OUTA[PINscl] := 0                                                'and set to 0
   DIRA[PINsda] := 0                                                'to simulate open collector i/o (i.e. pull-up resistors required)
   reset                                                            'Do bus reset to clear any chips' activity
   LONG[@BusInitialized]:= TRUE                                     'Keep tally of initialization


PUB isInitialized

   RETURN BusInitialized


'CHIP LEVEL METHODS    - calls BUS LEVEL METHODS below, encapsulates the details of the workings of the bus
'=================================================================================================================================================
'Write

'Byte (8bit)

PUB writeByteA8(ChipAddr, RegAddr, Value)                           'Write a byte to specified chip and 8bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Shift left 1 to add on the read/write bit, default 0 (write)
     writeBus(RegAddr)
     writeBus(Value)
     stop


PUB writeByteA16(ChipAddr, RegAddr, Value)                          'Write a byte to specified chip and 16bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Shift left 1 to add on the read/write bit, default 0 (write)
     writeBus(RegAddr.BYTE[1])                                      'MSB
     writeBus(RegAddr.BYTE[0])                                      'LSB
     writeBus(Value)
     stop


'Word (16bit)

PUB writeWordA8(ChipAddr, RegAddr, Value)                           'Write a Word to specified chip and 8bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Shift left 1 to add on the read/write bit, default 0 (write)
     writeBus(RegAddr)
     writeBus(Value.BYTE[1])                                        'MSB
     writeBus(Value.BYTE[0])                                        'LSB
     stop


PUB writeWordA16(ChipAddr, RegAddr, Value)                          'Write a Word to specified chip and 16bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Shift left 1 to add on the read/write bit, default 0 (write)
     writeBus(RegAddr.BYTE[1])                                      'MSB
     writeBus(RegAddr.BYTE[0])                                      'LSB
     writeBus(Value.BYTE[1])                                        'MSB
     writeBus(Value.BYTE[0])                                        'LSB
     stop


'Long (32bit)

PUB writeLongA8(ChipAddr, RegAddr, Value)                           'Write a Long to specified chip and 8bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Shift left 1 to add on the read/write bit, default 0 (write)
     writeBus(RegAddr)
     writeBus(Value.BYTE[3])                                        'MSB
     writeBus(Value.BYTE[2])                                        'NMSB
     writeBus(Value.BYTE[1])                                        'NLSB
     writeBus(Value.BYTE[0])                                        'LSB
     stop


PUB writeLongA16(ChipAddr, RegAddr, Value)                          'Write a Long to specified chip and 16bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Shift left 1 to add on the read/write bit, default 0 (write)
     writeBus(RegAddr.BYTE[1])                                      'MSB
     writeBus(RegAddr.BYTE[0])                                      'LSB
     writeBus(Value.BYTE[3])                                        'MSB
     writeBus(Value.BYTE[2])                                        'NMSB
     writeBus(Value.BYTE[1])                                        'NLSB
     writeBus(Value.BYTE[0])                                        'LSB
     stop


' Special ------------not debugged, written in attempt to communicate with adafruit oled -------------------------------------------------------------------------

PUB writeByteDirect(ChipAddr, FlagByte, OneByte)                    'Write direct, flagbyte determines if command, parameter or data,  register addressing not used

   IF callChip(ChipAddr << 1)== ACK                                 'Shift left 1 to add on the read/write bit, default 0 (write)
     writeBus(FlagByte)                                             'FlagByte determines if data is received as command, parameter or data
     writeBus(OneByte)
     stop


PUB writeBlockDirect(ChipAddr, FlagByte, OneByte, begin_end)        'Write direct, flagbyte must signal 'data write' begin_end=  1:begin, 0:continue, -1:end
   IF begin_end== 1
     IF callChip(ChipAddr << 1)== ACK                               'Shift left 1 to add on the read/write bit, default 0 (write)
        writeBus(FlagByte)                                          'FlagByte determines if data is received as command, parameter or data
        writeBus(OneByte)                                           'First byte of data
   ELSEIF begin_end== 0
      writeBus(FlagByte)
      writeBus(OneByte)                                             'A number of bytes of data
   ELSEIF begin_end== -1
       writeBus(FlagByte)
       writeBus(OneByte)                                            'Last byte of data
       stop



'Read------------------------------------------------------------------------------------------------------
'Byte

PUB readByteA8(ChipAddr, RegAddr) | Value                           'Read a byte from specified chip and 8bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Check if chip responded
     writeBus(RegAddr)
     start                                                          'Restart for reading
     writeBus(ChipAddr << 1 | 1 )                                   'address again, but with the read/write bit set to 1 (read)
     Value:= readBus(NAK)
     stop
     RETURN Value
   ELSE
     RETURN FALSE


PUB readByteA16(ChipAddr, RegAddr) | Value                          'Read a byte from specified chip and 16bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Check if chip responded
     writeBus(RegAddr.BYTE[1])                                      'MSB
     writeBus(RegAddr.BYTE[0])                                      'LSB
     start                                                          'Restart for reading
     writeBus(ChipAddr << 1 | 1 )                                   'address again, but with the read/write bit set to 1 (read)
     Value:= readBus(NAK)
     stop
     RETURN Value
   ELSE
     RETURN FALSE

'Word

PUB readWordA8(ChipAddr, RegAddr) | Value                           'Read a Word from specified chip and 8bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Check if chip responded
     writeBus(RegAddr)
     start                                                          'Restart for reading
     writeBus(ChipAddr << 1 | 1 )                                   'address again, but with the read/write bit set to 1 (read)
     Value.BYTE[3]:= 0                                              'clear the rubbish
     Value.BYTE[2]:= 0                                              'clear the rubbish
     Value.BYTE[1]:= readBus(ACK)                                   'MSB
     Value.BYTE[0]:= readBus(NAK)                                   'LSB
     stop
     RETURN Value
   ELSE
     RETURN FALSE


PUB readWordA16(ChipAddr, RegAddr) | Value                          'Read a Word from specified chip and 16bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Check if chip responded
     writeBus(RegAddr.BYTE[1])                                      'MSB
     writeBus(RegAddr.BYTE[0])                                      'LSB
     start                                                          'Restart for reading
     writeBus(ChipAddr << 1 | 1 )                                   'address again, but with the read/write bit set to 1 (read)
     Value.BYTE[3]:= 0                                              'clear the rubbish
     Value.BYTE[2]:= 0                                              'clear the rubbish
     Value.BYTE[1]:= readBus(ACK)                                   'MSB
     Value.BYTE[0]:= readBus(NAK)                                   'LSB
     stop
     RETURN Value
   ELSE
     RETURN FALSE


'Long

PUB readLongA8(ChipAddr, RegAddr) | Value                           'Read a Long from specified chip and 8bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Check if chip responded
     writeBus(RegAddr)
     start                                                          'Restart for reading
     writeBus(ChipAddr << 1 | 1 )                                   'address again, but with the read/write bit set to 1 (read)
     Value.BYTE[3]:= readBus(ACK)                                   'MSB
     Value.BYTE[2]:= readBus(ACK)                                   'NMSB
     Value.BYTE[1]:= readBus(ACK)                                   'NLSB
     Value.BYTE[0]:= readBus(NAK)                                   'LSB
     stop
     RETURN Value
   ELSE
     RETURN FALSE


PUB readLongA16(ChipAddr, RegAddr) | Value                          'Read a Long from specified chip and 16bit register address

   IF callChip(ChipAddr << 1)== ACK                                 'Check if chip responded
     writeBus(RegAddr.BYTE[1])                                      'MSB
     writeBus(RegAddr.BYTE[0])                                      'LSB
     start                                                          'Restart for reading
     writeBus(ChipAddr << 1 | 1 )                                   'address again, but with the read/write bit set to 1 (read)
     Value.BYTE[3]:= readBus(ACK)                                   'MSB
     Value.BYTE[2]:= readBus(ACK)                                   'NMSB
     Value.BYTE[1]:= readBus(ACK)                                   'NLSB
     Value.BYTE[0]:= readBus(NAK)                                   'LSB
     stop
     RETURN Value
   ELSE
     RETURN FALSE


'BUS LEVEL METHODS
'=============================================================================================================================================
PUB reset                                                           'Do bus reset to clear any chips' activity

   OUTA[PINsda] := 0                                                'Float SDA
   REPEAT 9
     DIRA[PINscl] := 1                                              'Toggle SCL to clock out any remaining bits, maximum 8bits + acknak bit
     DIRA[PINscl] := 0                                              'or until
     IF (INA[PINsda])                                               'SDA is released to go high by chip(s)
       QUIT


PUB isBusy

   IF INA[PINsda]== 1 AND INA[PINscl]== 1
     RETURN FALSE
   ELSE
     RETURN TRUE


PUB whoOnBus(ptrOnBusArr) | onbus, addr                             'Fills an array with max 119 elements with addresses that get a response
                                                                    'and writes how many is onbus to the 0th element
   onbus:= 1

   REPEAT addr FROM %0000_1000 TO %0111_0111                        'Scan the entire address space, exept for reserved spaces
     IF callChip(addr << 1)== ACK                                   'If a chip acknowledges,
       LONG[ptrOnBusArr][onbus]:= addr                              'put that address in the callers array
       LONG[ptrOnBusArr][0]:= onbus                                 'and update the total count of chips on the bus
       onbus++
       IF onbus> 119                                                'until loop expires or maximum number of elements in the array is reached
         stop
         QUIT
     stop                                                           'After each call send a stop signal to avoid confusion


PUB callChip(ChipAddr) | acknak, t                                  'Address the chip until it acknowledges or timeout

  t:= CNT                                                           'Set start time
  REPEAT
     start                                                          'Prepare chips for responding
     acknak:= writeBus(ChipAddr)                                    'Address the chip
     IF CNT > t+ 10*mSec                                            'and break if timeout
       RETURN NAK
  UNTIL acknak == ACK                                               'or until it acknowledges
  RETURN ACK


PUB start                                                           'Check that no chip is holding down SCL, then signal 'start'

   DIRA[PINsda] := 0
   DIRA[PINscl] := 0
   WAITPEQ(|<PINscl,|<PINscl, 0)                                    'Check/ wait for SCL to be released
   DIRA[PINsda] := 1                                                'Signal 'start'
   DIRA[PINscl] := 1


PUB writeBus(BusByte) | acknak                                      'Clock out 8 bits to the bus

   BusByte := (BusByte ^ $FF) << 24                                 'XOR all bits with '1' to invert them, then shift left to bit 31
   REPEAT 8                                                         '(output the bits as inverted because DIRA:= 1 gives pin= '0')
     DIRA[PINsda] := BusByte <-= 1                                  'send msb first and bitwise rotate left to send the next bits
     DIRA[PINscl] := 0                                              'clock the bus
     DIRA[PINscl] := 1                                              'and leave SCL low

   DIRA[PINsda] := 0                                                'Float SDA to read ack bit
   DIRA[PINscl] := 0                                                'clock the bus
   acknak := INA[PINsda]                                            'read ack bit
   DIRA[PINscl] := 1                                                'and leave SCL low

   RETURN acknak


PUB readBus(acknak) | BusByte                                       'Clock in  8 bits from the bus

  DIRA[PINsda] := 0                                                 'Float SDA to read input bits

  REPEAT 8
    DIRA[PINscl] := 0                                               'clock the bus
    WAITPEQ(|<PINscl,|<PINscl, 0)                                   'check/ wait for SCL to be released
    BusByte := (BusByte << 1) | INA[PINsda]                         'read the bit
    DIRA[PINscl] := 1                                               'and leave SCL low

  DIRA[PINsda] := !acknak                                           'output nak if finished, ack if more reads
  DIRA[PINscl] := 0                                                 'clock the bus
  DIRA[PINscl] := 1                                                 'and leave SCL low

  RETURN BusByte


PUB stop                                                            'Send stop sequence

  DIRA[PINsda] := 1                                                 'Pull SDA low
  DIRA[PINscl] := 0                                                 'float SCL and
  WAITPEQ(|<PINscl,|<PINscl,0)                                      'wait for SCL to be released
  DIRA[PINsda] := 0                                                 'and leave SDA floating


DAT

{{
+------------------------------------------------------------------------------------------------------------------------------+
|                                                   TERMS OF USE: MIT License                                                  |
+------------------------------------------------------------------------------------------------------------------------------+
|Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    |
|files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    |
|modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software|
|is furnished to do so, subject to the following conditions:                                                                   |
|                                                                                                                              |
|The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.|
|                                                                                                                              |
|THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          |
|WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         |
|COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   |
|ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         |
+------------------------------------------------------------------------------------------------------------------------------+
}}