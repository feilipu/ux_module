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
  VGA_BASE_PIN  = 16  ' VGA pins 16-23

  ' set these constants based on the Propeller PS/2 hardware
  KBD_DATA_PIN  = 27  ' KEYBOARD data pin
  KBD_CLK_PIN   = 26  ' KEYBOARD clock pin

  ' import some constants from the I2C hardware
  SDA_PIN       = i2c#SDA_PIN  ' I2C data pin
  SCL_PIN       = i2c#SCL_PIN  ' I2C clock pin

  ' import some constants from the Propeller Window Manager
  VGACOLS       = wmf#VGACOLS
  VGAROWS       = wmf#VGAROWS


CON


  '    Control Character Constants
  '─────────────────────────────────────

  HM =  1  ''HM: HoMe cursor
  PC =  2  ''PC: Position Cursor in x,y

  ML =  3  ''ML: Move cursor Left
  MR =  4  ''MR: Move cursor Right
  MU =  5  ''MU: Move cursor Up
  MD =  6  ''MD: Move cursor Down

  BP =  7  ''BP: BeeP speaker
  BS =  8  ''BS: BackSpace
  TB =  9  ''TB: TaB

  LF = 10  ''LF: Line Feed
  CE = 11  ''CE: Clear to End of line
  CB = 12  ''CB: Clear lines Below
  NL = 13  ''NL: New Line

  PX = 14  ''PX: Position cursor in X
  PY = 15  ''PY: Position cursor in Y

  CS = 16  ''CS: Clear Screen


CON

  ' ASCII control codes

  ASCII_NULL    = $00 ' null character

  ASCII_BELL    = $07 ' backspace
  ASCII_BS      = $08 ' backspace
  ASCII_TAB     = $09 ' horizontal tab
  ASCII_LF      = $0A ' line feed
  ASCII_VT      = $0B ' vertical tab
  ASCII_FF      = $0C ' form feed (new page)
  ASCII_CR      = $0D ' carriage return

  ASCII_ESC     = $1B ' escape

  ASCII_SPACE   = $20 ' space
  ASCII_HASH    = $23 ' #
  ASCII_COMMA   = $2C ' ,
  ASCII_PERIOD  = $2E ' .

  ASCII_LB      = $5B ' [
  ASCII_RB      = $5D ' ]

  ASCII_DEL     = $7F ' delete


VAR

' -----------------------------------------------------------------------------
' DECLARED VARIABLES, ARRAYS, ETC.
' -----------------------------------------------------------------------------

  byte  gScreenRows, gScreenCols                      ' convenient globals to store number of screen columns and rows

  ' these data structures contains two cursors in the format [x,y,mode]
  ' these are passed to the VGA driver, so it can render them over the text in the display
  ' like "hardware" cursors, that don't disturb the graphics under them. We can use them
  ' to show where the text cursor and mouse cursor is
  ' The data structure is 6 contiguous bytes which we pass to the VGA driver ultimately

  byte  gTextCursX, gTextCursY, gTextCursMode         ' text cursor 0 [x0,y0,mode0]
  byte  gMouseCursX, gMouseCursY, gMouseCursMode      ' mouse cursor 1 [x1,y1,mode1] (unused but required for VGA driver)

  long  gScreenBufferPtr                              ' holds the address of the video buffer passed back from the VGA driver


OBJ

      term            : "terminal_ftdi"
      kbd             : "keyboard_ps2"
      wmf             : "wmf_terminal_vga"
      i2c             : "i2c"
      acia            : "acia_rc2014"


PUB start

  'start the serial terminal
  term.start (115200)
  term.clear                                        ' clear terminal
  term.str (string("UX Module Initialising...",$0D))

  'start the ACIA interface
  acia.start (PORT_80)

  'start the keyboard
  kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)

  'start i2c
  i2c.init (SCL_PIN, SDA_PIN)

  'start the VGA scren
  screenInit

  ' MAIN EVENT LOOP - this is where you put all your code in a non-blocking infinite loop...
  repeat
    readZ80
    kbdWriteZ80
    termWriteZ80


CON

  '' Visual differentiation


PUB screenInit | retVal
  ' This functions creates the entire user experience and does any other
  ' static initialization you might want.

  ' text cursor starting position and as blinking underscore
  gTextCursX     := 0
  gTextCursY     := 0
  gTextCursMode  := %110

  ' set mouse cursor position as off
  gMouseCursX    := 0
  gMouseCursY    := 0
  gMouseCursMode := 0


  ' now start the VGA driver and terminal services
  retVal := wmf.init(VGA_BASE_PIN, @gTextCursX )

  ' rows encoded in upper 8-bits. columns in lower 8-bits of return value, redundant code really
  ' since we pull it in with a constant in the first CON section, but up to you!
  gScreenRows := ( retVal & $0000FF00 ) >> 8
  gScreenCols := retVal & $000000FF

  ' VGA buffer encoded in upper 16-bits of return value
  gScreenBufferPtr := retVal >> 16

  wmf.strScreenLn (string("UX Module Initialising..."))
  ++gTextCursY

  ' return to caller
  return


PUB readZ80 | char

    ' if no input from ACIA then return
    repeat while acia.rxCheck

      ' get character from buffer
      char := acia.rx
  
      ' send it out the serial terminal (transparently)
      term.char (char)
  
      ' display it on the screen
      case char
        ASCII_CR: ' return
  
          wmf.outScreen ( NL )

          gTextCursX := 0
          if (gTextCursY < gScreenRows )
            ++gTextCursY

        ASCII_LF: ' line feed
          next

        ASCII_BS, ASCII_DEL: ' backspace (edit)
  
          if (gTextCursX < gScreenCols )
           ' move cursor back once to overwrite last character on screen
           wmf.outScreen ( BS )
           wmf.outScreen ( ASCII_SPACE )
           wmf.outScreen ( BS )

           --gTextCursX
  
        other:    ' all other cases
  
           ' update length
           if (gTextCursX < gScreenCols )
             ++gTextCursX
           else
             ' move cursor back once to overwrite last character on screen
             wmf.outScreen ( BS )
  
           ' echo character
           wmf.outScreen ( char )


PUB kbdWriteZ80 | char

    ' if no input from keyboard then return
    repeat while kbd.gotKey

      char := kbd.getKey

      case char

        kbd#KBD_ASCII_BS, kbd#KBD_ASCII_DEL:
          acia.tx (BS)

        kbd#KBD_ASCII_CR, kbd#KBD_ASCII_PAD_CR:
          acia.tx (NL)

        kbd#KBD_ASCII_LF:
          next

        kbd#KBD_ASCII_CTRL | kbd#KBD_ASCII_ALT | kbd#KBD_ASCII_DEL:
          dira[ acia#RESET_PIN_NUM ]~~                               ' Set /RESET pin to output to reset the Z80
          dira[ acia#RESET_PIN_NUM ]~                                ' Set /RESET pin to input (measured pulse is 5,600ns)

        other:      ' all other input
          acia.tx (char)


PUB termWriteZ80

    ' if no input from terminal then return
    repeat while term.rxCheck
      acia.tx (term.charIn)


DAT

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
