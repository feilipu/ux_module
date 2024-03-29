''***************************************
''*  User Experience Module             *
''*  Designed for RC2014                *
''*  Author: Phillip Stevens            *
''*  Copyright (c) 2021                 *
''*  See end of file for licence        *
''***************************************

CON

  _clkmode      = XTAL1 + PLL16X
  _xinfreq      = 7_372_800


CON

  ' import some constants from the ACIA Emulation
  PORT_ROMWBW   = acia#PORT_40  ' Alternate ACIA base port, when used together with SIO/2 Module on 0x80
  PORT_DEFAULT  = acia#PORT_80  ' Default ACIA base port
  PORT_VJET     = acia#PORT_C0


CON

  ' set these constants based on the Propeller VGA hardware
  VGA_BASE_PIN  = 16  ' VGA pins 16-23

  ' set these constants based on the Propeller PS/2 hardware
  KBD_DATA_PIN  = 27  ' KEYBOARD data pin
  KBD_CLK_PIN   = 26  ' KEYBOARD clock pin

  ' import some constants from the I2C hardware
  SDA_PIN       = i2c#SDA_PIN   ' I2C data pin
  SCL_PIN       = i2c#SCL_PIN   ' I2C clock pin

  ' import some constants from the Propeller Window Manager
  VGACOLS       = wmf#VGACOLS
  VGAROWS       = wmf#VGAROWS


CON

  ' ASCII control codes

  ASCII_NULL    = $00 ' null character

  ASCII_BELL    = $07 ' bell
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

  ASCII_SEMI    = $3B ' ;

  ASCII_0       = $30 ' 0
  ASCII_9       = $39 ' 9

  ASCII_LB      = $5B ' [
  ASCII_RB      = $5D ' ]

  ASCII_DEL     = $7F ' delete

CON

  ' XMODEM control codes

  XMODEM_SOH    = $01 ' Start of Header
  XMODEM_EOT    = $04 ' End of Transmission
  XMODEM_ETB    = $17 ' End of Transmission Block
  XMODEM_CAN    = $18 ' Cancel


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

  long  termStack [64]                                ' small stack for the serial terminal input cog


OBJ

      term            : "terminal_ftdi"
      kbd             : "keyboard_ps2"
      wmf             : "wmf_terminal_vga"
      i2c             : "i2c"
      acia            : "acia_rc2014"


PUB main

  'start the serial terminal
  term.start (115200)
  term.clear                                          ' clear terminal
  term.str (string("UX Module Initialised"))
  term.lineFeed

  'start the ACIA interface
  acia.start (PORT_DEFAULT) 'default for RC2014 ROM
' acia.start (PORT_ROMWBW)  'optional for RomWBW, when used together with SIO/2 Module on 0x80

  'start the VGA scren
  screenInit

  'start the keyboard
  kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)

  'start i2c
  i2c.init (SCL_PIN, SDA_PIN)

  'start serial processing in a separate cog
  cognew (termToZ80, @termStack)

  'MAIN COG EVENT LOOP - this is where you put all your code in a non-blocking infinite loop...
  repeat
    ' if no input from keyboard then continue	
    kbdToZ80
    ' if no input from ACIA then continue
    readZ80


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
  retVal := wmf.init (VGA_BASE_PIN, @gTextCursX)

  ' rows encoded in upper 8-bits. columns in lower 8-bits of return value, redundant code really
  ' since we pull it in with a constant in the first CON section, but up to you!
  gScreenRows := ( retVal & $0000FF00 ) >> 8
  gScreenCols := retVal & $000000FF

  ' VGA buffer encoded in upper 16-bits of return value
  gScreenBufferPtr := retVal >> 16

  wmf.strScreenLn (string("UX Module Initialised"))
  ++gTextCursY

  ' return to caller
  return


PUB readZ80 | char, n, m

    ' if no input from ACIA  or no space in terminal tx buffer then return
    repeat while acia.rxCount > 0 and term.txCheck  ' check whether any bytes have arrived (with /RTS)

      ' get character from buffer
      char := acia.rx

      case char

        XMODEM_SOH:                             ' XMODEM Start of Header

          term.tx (char)                        ' SOH to terminal

          n := acia.rx
          term.tx (n)                           ' Packet Number to terminal

          m := acia.rx
          term.tx (m)                           ' Complimented Packet Number to terminal

          if ( n == $FF-m )
            n := 129                            ' get another 129 (of 132/133 total) XMODEM packet characters
            repeat
              term.tx (acia.rx)                 ' get next characters after Packet Header
            while ( --n )

        ASCII_BS, ASCII_DEL:                    ' backspace (edit), delete

          ' move cursor back once to overwrite last character on terminal
          term.tx (ASCII_BS)
          term.tx (ASCII_SPACE)
          term.tx (ASCII_BS)

          if ( gTextCursX > 0 )
            --gTextCursX

          ' move cursor back once to overwrite last character on screen
          wmf.outScreen (wmf#BS)
          wmf.outScreen (wmf#ASCII_SPACE)
          wmf.outScreen (wmf#BS)

        ASCII_TAB:                              ' horizontal Tab

          term.tx (char)

          if ( gTextCursY < gScreenCols-5 )
            repeat
              ++gTextCursY
            while gTextCursY & 3

          wmf.outScreen (wmf#TB)

        ASCII_LF:                               ' line feed

        ' eat linefeed from Z80.
          next

        ASCII_CR:                               ' carriage return

          term.lineFeed

          gTextCursX := 0
          if ( gTextCursY < gScreenRows-1 )
            ++gTextCursY

          wmf.outScreen (wmf#NL)

        ASCII_ESC:                              ' escape

          term.tx (char)                        ' ESC to terminal

          char := acia.rx                       ' get next character after ESC
          term.tx (char)                        ' possible CSI to terminal

          case char

            ASCII_LB:                           ' CSI Control Sequence Introducer

              n := 0

              repeat
                char := acia.rx                 ' get next characters after CSI
                term.tx (char)                  ' possible modifier char to terminal

                if ( char => "0" AND char =< "9" )
                  n := n*10 + char - ASCII_0

              while ( char => "0" AND char =< "9" )

              case char

                "A":                            ' cursor up
                  if ( n == 0 )
                    ++n
                  if ( gTextCursY > n // gScreenRows - 1 )
                    gTextCursY := gTextCursY - n // gScreenRows
                    wmf.outScreen (wmf#PY)
                    wmf.outScreen (gTextCursY)

                "B":                            ' cursor down
                  if ( n == 0 )
                    ++n
                  if ( gTextCursY < gScreenRows - n // gScreenRows )
                    gTextCursY := gTextCursY + n // gScreenRows
                    wmf.outScreen (wmf#PY)
                    wmf.outScreen (gTextCursY)

                "C":                            ' cursor right
                  if ( n == 0 )
                    ++n
                  if ( gTextCursX < gScreenCols - n // gScreenCols )
                    gTextCursX := gTextCursX + n  // gScreenCols
                    wmf.outScreen (wmf#PX)
                    wmf.outScreen (gTextCursX)

                "D":                            ' cursor left
                  if ( n == 0 )
                    ++n
                  if ( gTextCursX > n // gScreenCols - 1 )
                    gTextCursX := gTextCursX - n // gScreenCols
                    wmf.outScreen (wmf#PX)
                    wmf.outScreen (gTextCursX)

                "E":                            ' cursor next line n start
                  if ( n == 0 )
                    ++n
                  if ( gTextCursY < gScreenRows - n // gScreenRows )
                    gTextCursY := gTextCursY + n // gScreenRows
                    gTextCursX := 0
                    wmf.outScreen (wmf#PY)
                    wmf.outScreen (gTextCursY)
                    wmf.outScreen (wmf#PX)
                    wmf.outScreen (gTextCursX)

                "F":                            ' cursor previous line n start
                  if ( n == 0 )
                    ++n
                  if ( gTextCursY > n // gScreenRows - 1 )
                    gTextCursY := gTextCursY - n // gScreenRows
                    gTextCursX := 0
                    wmf.outScreen (wmf#PY)
                    wmf.outScreen (gTextCursY)
                    wmf.outScreen (wmf#PX)
                    wmf.outScreen (gTextCursX)

                "G":                            ' cursor to column n
                  if ( n == 0 )
                    ++n
                  gTextCursX := n // gScreenCols - 1
                  wmf.outScreen (wmf#PX)
                  wmf.outScreen (gTextCursX)

                "H":                            ' cursor to row n, column 1
                  if ( n == 0 )
                    ++n
                  gTextCursY := n // gScreenRows - 1
                  gTextCursX := 0
                  wmf.outScreen (wmf#PY)
                  wmf.outScreen (gTextCursY)
                  wmf.outScreen (wmf#PX)
                  wmf.outScreen (gTextCursX)

                "J":                            ' clear screen
                  if ( n == 0 )
                    bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenRows*gScreenCols - gTextCursY*gScreenCols - gTextCursX )
                  elseif ( n == 1 )
                    bytefill ( gScreenBufferPtr, ASCII_SPACE, gTextCursY*gScreenCols + gTextCursX + 1 )
                  elseif ( n == 2 )
                    gTextCursX := gTextCursY := 0
                    wmf.outScreen ( wmf#CS )

                "K":                            ' clear line
                  if ( n == 0 )
                    bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenCols - gTextCursX)
                  elseif ( n == 1 )
                    bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gTextCursX + 1 )
                  elseif ( n == 2 )
                    bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gScreenCols )
                    gTextCursX := 0
                    wmf.outScreen (wmf#PX)
                    wmf.outScreen (gTextCursX)

                "m":                            ' set graphics rendition parameters
                  if ( n == 0 )
                    wmf.setLineColor ( gTextCursY, wmf#CTHEME_DEFAULT_FG, wmf#CTHEME_DEFAULT_BG )
                  elseif ( n == 7 )
                    wmf.setLineColor ( gTextCursY, wmf#CTHEME_DEFAULT_BG, wmf#CTHEME_DEFAULT_FG )

                ASCII_SEMI:

                  m :=0

                  repeat
                    char := acia.rx             ' get next characters after semicolon
                    term.tx (char)              ' possible modifier char to terminal

                    if ( char => "0" AND char =< "9" )
                      m := m*10 + char - ASCII_0

                  while ( char => "0" AND char =< "9" )

                  if ( char == "H" )            ' cursor to row n, column m
                    if ( n == 0 )
                      ++n
                    if ( m == 0 )
                      ++m
                    gTextCursY := n // gScreenRows - 1
                    gTextCursX := m // gScreenCols - 1
                    wmf.outScreen (wmf#PY)
                    wmf.outScreen (gTextCursY)
                    wmf.outScreen (wmf#PX)
                    wmf.outScreen (gTextCursX)

            other:                                  ' all other cases after ESC
              if ( char => $20 )                    ' only printable characters to the screen
                if ( gTextCursX < gScreenCols - 1 ) ' update cursor position
                  ++gTextCursX
                else
                  if ( gTextCursY < gScreenRows - 1 )
                    ++gTextCursY
                  gTextCursX := 0
                wmf.outScreen (char)            ' echo printable non CSI character

        other:                                  ' all other cases

          term.tx (char)                        ' send other characters out the serial terminal

          if ( char => $20 )                    ' only printable characters to the screen
            if ( gTextCursX < gScreenCols - 1 ) ' update cursor position
              ++gTextCursX
            else
              if ( gTextCursY < gScreenRows - 1 )
                ++gTextCursY
              gTextCursX := 0
            wmf.outScreen (char)                ' echo all printable characters


PUB kbdToZ80 | char

    ' if no input from keyboard or no space in acia tx buffer then return
    repeat while kbd.gotKey and acia.txCheck

      char := kbd.getKey

      case char

        kbd#KBD_ASCII_BS, kbd#KBD_ASCII_DEL:
          acia.tx (ASCII_BS)

        kbd#KBD_ASCII_CR, kbd#KBD_ASCII_PAD_CR:
          acia.tx (ASCII_CR)

        kbd#KBD_ASCII_LF:
          next

        kbd#KBD_ASCII_ESC:
          acia.tx (ASCII_ESC)

        kbd#KBD_ASCII_UP:
          acia.txString ( string (ASCII_ESC, "[A") )

        kbd#KBD_ASCII_DOWN:
          acia.txString ( string (ASCII_ESC, "[B") )

        kbd#KBD_ASCII_RIGHT:
          acia.txString ( string (ASCII_ESC, "[C") )

        kbd#KBD_ASCII_LEFT:
          acia.txString ( string (ASCII_ESC, "[D") )

        kbd#KBD_ASCII_HOME:
          acia.txString ( string (ASCII_ESC, "[H") )

        kbd#KBD_ASCII_CTRL | kbd#KBD_ASCII_ALT | kbd#KBD_ASCII_DEL:

          acia.txFlush                          ' remove any pending transmit queue to Z80
          dira[ acia#RESET_PIN_NUM ]~~          ' set /RESET pin to output to reset the Z80
          dira[ acia#RESET_PIN_NUM ]~           ' set /RESET pin to input

          term.clear                            ' clear the serial terminal

          gTextCursX := gTextCursY := 0         ' move screen cursor to home position
          wmf.outScreen ( wmf#CS )              ' clear the screen

        other:      ' all other input
          acia.tx (char)


PUB termToZ80

  'COG EVENT LOOP - this is where you put all your code in a non-blocking infinite loop...
  repeat
    ' if no input from terminal then wait till there is
    if term.rxCount > 0 and acia.txCheck        ' if there is a received byte and space in acia tx buffer 
      acia.tx (term.rx)                         ' grab a byte and push it to the tx buffer


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
