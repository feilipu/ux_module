''***************************************
''*  User Experience Module             *
''*  Designed for RC2014                *
''*  Author: Phillip Stevens            *
''*  Copyright (c) 2020                 *
''*  See end of file for licence        *
''***************************************

CON

  _clkmode      = XTAL1 + PLL16X
  _xinfreq      = 7_372_800

CON

  ' import some constants from the ACIA Emulation
  PORT_40       = acia#PORT_40
  PORT_80       = acia#PORT_80    ' Default ACIA base port
  PORT_C0       = acia#PORT_C0

CON

  ' set these constants based on the Propeller VGA hardware
  VGA_BASE_PIN  = 16              ' VGA pins 16-23

  ' set these constants based on the Propeller PS/2 hardware
  KBD_DATA_PIN  = 27              ' KEYBOARD data pin
  KBD_CLK_PIN   = 26              ' KEYBOARD clock pin


VAR

' -----------------------------------------------------------------------------
' DECLARED VARIABLES, ARRAYS, ETC.   
' -----------------------------------------------------------------------------

  byte  gVgaRows, gVgaCols ' convenient globals to store number of columns and rows

  byte  gStrBuff1[64]      ' some string buffers
  byte  gStrBuff2[64]

  ' these data structures contains two cursors in the format [x,y,mode]
  ' these are passed to the VGA driver, so it can render them over the text in the display
  ' like "hardware" cursors, that don't disturb the graphics under them. We can use them
  ' to show where the text cursor and mouse cursor is
  ' The data structure is 6 contiguous bytes which we pass to the VGA driver ultimately
  
  byte  gTextCursX, gTextCursY, gTextCursMode        ' text cursor 0 [x0,y0,mode0] 
  byte  gMouseCursX, gMouseCursY, gMouseCursMode     ' mouse cursor 1 [x1,y1,mode1] (unused but required for VGA driver)

  long  gVideoBufferPtr                              ' holds the address of the video buffer passed back from the VGA driver
 
  byte  char


OBJ

      acia            : "acia_rc2014"
      term            : "terminal_ftdi"


PUB start | i

  'start the serial terminal
  term.start (115200)
  term.clear                                        ' clear terminal
  term.str (string ($0D,"UX Module Initialising...",$0D))

  'start the ACIA interface
  acia.start (PORT_80)

  'echo keystrokes in hex
  repeat
    char := term.rxCheck
    if char <> $ff
      acia.tx (char)
    char := acia.rxCheck
    if char <> $ff
      term.char (char)


{{
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}    
