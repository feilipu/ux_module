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

  PARSE_IDLE      = 0
  PARSE_ESC       = 1
  PARSE_CSI       = 2
  PARSE_CSI_M     = 3
  PARSE_XMODEM_N  = 4
  PARSE_XMODEM_M  = 5
  PARSE_XMODEM    = 6


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

  byte  z80Parse                                      ' non-blocking Z80 byte parser state
  long  z80N, z80M                                    ' CSI parameters
  long  z80Remain                                     ' XMODEM payload bytes still expected


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

  ' One Spin cog writes acia.tx. Keyboard during XMODEM/file load is not recommended.
  repeat
    if not inXmodem
      kbdToZ80
    termToZ80
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


PUB readZ80 | char

    if not term.txCheck
      acia.tdreHold
      return

    acia.tdreAllow

    repeat while acia.rxCount > 0 and term.txCheck
      char := acia.rx
      takeZ80Byte (char)

    if not term.txCheck
      acia.tdreHold


PRI inXmodem : truefalse

  truefalse := z80Parse == PARSE_XMODEM_N or z80Parse == PARSE_XMODEM_M or z80Parse == PARSE_XMODEM


PRI takeZ80Byte(char)

  case z80Parse

    PARSE_ESC:
      term.tx (char)
      if ( char == ASCII_LB )
        z80N := 0
        z80Parse := PARSE_CSI
      else
        echoPrintable (char)
        z80Parse := PARSE_IDLE

    PARSE_CSI:
      term.tx (char)
      if ( char => "0" AND char =< "9" )
        z80N := z80N*10 + char - ASCII_0
      elseif ( char == ASCII_SEMI )
        z80M := 0
        z80Parse := PARSE_CSI_M
      else
        applyCsi (char)
        z80Parse := PARSE_IDLE

    PARSE_CSI_M:
      term.tx (char)
      if ( char => "0" AND char =< "9" )
        z80M := z80M*10 + char - ASCII_0
      else
        if ( char == "H" )
          applyCsiH
        z80Parse := PARSE_IDLE

    PARSE_XMODEM_N:
      term.tx (char)
      z80N := char
      z80Parse := PARSE_XMODEM_M

    PARSE_XMODEM_M:
      term.tx (char)
      z80M := char
      if ( z80N == $FF - z80M )
        z80Remain := 129
        z80Parse := PARSE_XMODEM
      else
        z80Parse := PARSE_IDLE

    PARSE_XMODEM:
      term.tx (char)
      z80Remain := z80Remain - 1
      if ( z80Remain == 0 )
        z80Parse := PARSE_IDLE

    other:
      takeZ80Idle (char)


PRI takeZ80Idle(char)

  case char

    XMODEM_SOH:
      term.tx (char)
      z80Parse := PARSE_XMODEM_N

    ASCII_BS, ASCII_DEL:
      term.tx (ASCII_BS)
      term.tx (ASCII_SPACE)
      term.tx (ASCII_BS)
      if ( gTextCursX > 0 )
        --gTextCursX
      wmf.outScreen (wmf#BS)
      wmf.outScreen (wmf#ASCII_SPACE)
      wmf.outScreen (wmf#BS)

    ASCII_TAB:
      term.tx (char)
      if ( gTextCursY < gScreenCols-5 )
        repeat
          ++gTextCursY
        while gTextCursY & 3
      wmf.outScreen (wmf#TB)

    ASCII_LF:

    ASCII_CR:
      term.lineFeed
      gTextCursX := 0
      if ( gTextCursY < gScreenRows-1 )
        ++gTextCursY
      wmf.outScreen (wmf#NL)

    ASCII_ESC:
      term.tx (char)
      z80Parse := PARSE_ESC

    other:
      term.tx (char)
      echoPrintable (char)


PRI echoPrintable(char)

  if ( char => $20 )
    if ( gTextCursX < gScreenCols - 1 )
      ++gTextCursX
    else
      if ( gTextCursY < gScreenRows - 1 )
        ++gTextCursY
      gTextCursX := 0
    wmf.outScreen (char)


PRI applyCsiH

  if ( z80N == 0 )
    ++z80N
  if ( z80M == 0 )
    ++z80M
  gTextCursY := z80N // gScreenRows - 1
  gTextCursX := z80M // gScreenCols - 1
  wmf.outScreen (wmf#PY)
  wmf.outScreen (gTextCursY)
  wmf.outScreen (wmf#PX)
  wmf.outScreen (gTextCursX)


PRI applyCsi(char)

  case char

    "A":
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursY > z80N // gScreenRows - 1 )
        gTextCursY := gTextCursY - z80N // gScreenRows
        wmf.outScreen (wmf#PY)
        wmf.outScreen (gTextCursY)

    "B":
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursY < gScreenRows - z80N // gScreenRows )
        gTextCursY := gTextCursY + z80N // gScreenRows
        wmf.outScreen (wmf#PY)
        wmf.outScreen (gTextCursY)

    "C":
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursX < gScreenCols - z80N // gScreenCols )
        gTextCursX := gTextCursX + z80N // gScreenCols
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "D":
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursX > z80N // gScreenCols - 1 )
        gTextCursX := gTextCursX - z80N // gScreenCols
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "E":
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursY < gScreenRows - z80N // gScreenRows )
        gTextCursY := gTextCursY + z80N // gScreenRows
        gTextCursX := 0
        wmf.outScreen (wmf#PY)
        wmf.outScreen (gTextCursY)
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "F":
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursY > z80N // gScreenRows - 1 )
        gTextCursY := gTextCursY - z80N // gScreenRows
        gTextCursX := 0
        wmf.outScreen (wmf#PY)
        wmf.outScreen (gTextCursY)
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "G":
      if ( z80N == 0 )
        ++z80N
      gTextCursX := z80N // gScreenCols - 1
      wmf.outScreen (wmf#PX)
      wmf.outScreen (gTextCursX)

    "H":
      if ( z80N == 0 )
        ++z80N
      gTextCursY := z80N // gScreenRows - 1
      gTextCursX := 0
      wmf.outScreen (wmf#PY)
      wmf.outScreen (gTextCursY)
      wmf.outScreen (wmf#PX)
      wmf.outScreen (gTextCursX)

    "J":
      if ( z80N == 0 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenRows*gScreenCols - gTextCursY*gScreenCols - gTextCursX )
      elseif ( z80N == 1 )
        bytefill ( gScreenBufferPtr, ASCII_SPACE, gTextCursY*gScreenCols + gTextCursX + 1 )
      elseif ( z80N == 2 )
        gTextCursX := gTextCursY := 0
        wmf.outScreen ( wmf#CS )

    "K":
      if ( z80N == 0 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenCols - gTextCursX)
      elseif ( z80N == 1 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gTextCursX + 1 )
      elseif ( z80N == 2 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gScreenCols )
        gTextCursX := 0
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "m":
      if ( z80N == 0 )
        wmf.setLineColor ( gTextCursY, wmf#CTHEME_DEFAULT_FG, wmf#CTHEME_DEFAULT_BG )
      elseif ( z80N == 7 )
        wmf.setLineColor ( gTextCursY, wmf#CTHEME_DEFAULT_BG, wmf#CTHEME_DEFAULT_FG )


PUB kbdToZ80 | char

    ' Do not type during XMODEM/file load. Main skips this pump then.
    repeat while kbd.gotKey

      char := kbd.peekKey

      case char
        kbd#KBD_ASCII_UP, kbd#KBD_ASCII_DOWN, kbd#KBD_ASCII_RIGHT, kbd#KBD_ASCII_LEFT, kbd#KBD_ASCII_HOME:
          if acia.txSpace < 3
            quit
        other:
          if not acia.txCheck
            quit

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

          acia.txFlush
          z80Parse := PARSE_IDLE
          dira[ acia#RESET_PIN_NUM ]~~
          dira[ acia#RESET_PIN_NUM ]~

          term.clear

          gTextCursX := gTextCursY := 0
          wmf.outScreen ( wmf#CS )

        other:
          acia.tx (char)


PUB termToZ80

  repeat while term.rxCount > 0 and acia.txCheck
    acia.tx (term.rx)

  if not inXmodem
    term.rxFlow


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
