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

  XMODEM_SOH    = $01 ' Start of Header (parser uses this)
  XMODEM_EOT    = $04 ' End of Transmission (passed through as data)
  XMODEM_ETB    = $17 ' End of Transmission Block
  XMODEM_CAN    = $18 ' Cancel

  ' Non-blocking Z80 output parser (readZ80). One byte per call.
  PARSE_IDLE      = 0   ' normal stream
  PARSE_ESC       = 1   ' saw ESC, waiting for next byte
  PARSE_CSI       = 2   ' ESC [ ... collecting n
  PARSE_CSI_M     = 3   ' ESC [ n ; ... collecting m
  PARSE_XMODEM_N  = 4   ' SOH, waiting packet number
  PARSE_XMODEM_M  = 5   ' waiting complemented packet number
  PARSE_XMODEM    = 6   ' 129 payload bytes (128 data + checksum)

  PUMP_LIMIT      = 16  ' max bytes each of kbd / FTDI / ACIA drain per main-loop pass


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

  byte  z80Parse                                      ' PARSE_* state for readZ80
  long  z80N, z80M                                    ' CSI n and m (ESC [ n ; m H)
  long  z80Remain                                     ' XMODEM bytes still to copy to FTDI


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

  'start the VGA screen
  screenInit

  'start the keyboard
  kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)

  'start i2c
  i2c.init (SCL_PIN, SDA_PIN)

  ' MAIN COG EVENT LOOP — one writer for acia.tx (no extra pump cog).
  ' Skip the keyboard while XMODEM is in progress. Do not type during file load.
  repeat
    if acia.takeParseIdle                             ' Z80 CR_RESET: abandon ESC/CSI/XMODEM
      z80Parse := PARSE_IDLE
    if not inXmodem
      kbdToZ80
    termToZ80
    readZ80


CON

  '' Visual differentiation


PUB screenInit | retVal
  ' Start VGA text and place the boot banner. Static init only.

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


PUB readZ80 | char, n, need
{{Drain Z80 TDR bytes to VGA and FTDI. Never blocks on acia.rx or term.tx.
  If FTDI TX is full, hold ACIA TDRE so the Z80 stops sending.}}

    if not term.txCheck                               ' no room toward the host
      acia.tdreHold
      return

    acia.tdreAllow                                    ' FTDI can take bytes; Z80 may write TDR

    n := 0
    repeat while acia.rxCount > 0 and n < PUMP_LIMIT
      char := acia.rxPeek
      need := ftdiNeed (char)
      if term.txSpace < need
        acia.tdreHold
        quit
      char := acia.rx
      takeZ80Byte (char)
      n++

    if not term.txCheck
      acia.tdreHold


PRI ftdiNeed(char) : n
{{FTDI TX slots takeZ80Byte will use for this ACIA byte in the current PARSE_* state.}}

  n := 1
  if z80Parse == PARSE_IDLE
    case char
      ASCII_BS, ASCII_DEL:
        n := 3
      ASCII_LF:
        n := 0
      ASCII_CR:
        n := 1                                        ' term.lineFeed sends one LF


PRI inXmodem : truefalse
{{True while readZ80 is inside an XMODEM packet (SOH through payload).}}

  truefalse := z80Parse == PARSE_XMODEM_N or z80Parse == PARSE_XMODEM_M or z80Parse == PARSE_XMODEM


PRI takeZ80Byte(char)
{{One byte from the ACIA RX FIFO. Advances PARSE_* without waiting for more input.}}

  case z80Parse

    PARSE_ESC:                                      ' byte after ESC
      term.tx (char)
      if ( char == ASCII_LB )                       ' CSI Control Sequence Introducer
        z80N := 0
        z80Parse := PARSE_CSI
      else
        echoPrintable (char)                        ' printable non-CSI after ESC
        z80Parse := PARSE_IDLE

    PARSE_CSI:                                      ' ESC [ n ...
      term.tx (char)
      if ( char => "0" AND char =< "9" )
        z80N := z80N*10 + char - ASCII_0
      elseif ( char == ASCII_SEMI )
        z80M := 0
        z80Parse := PARSE_CSI_M
      else
        applyCsi (char)
        z80Parse := PARSE_IDLE

    PARSE_CSI_M:                                    ' ESC [ n ; m ...
      term.tx (char)
      if ( char => "0" AND char =< "9" )
        z80M := z80M*10 + char - ASCII_0
      else
        if ( char == "H" )                          ' cursor to row n, column m
          applyCsiH
        z80Parse := PARSE_IDLE

    PARSE_XMODEM_N:                                 ' packet number
      term.tx (char)
      z80N := char
      z80Parse := PARSE_XMODEM_M

    PARSE_XMODEM_M:                                 ' complemented packet number
      term.tx (char)
      z80M := char
      if ( z80N == $FF - z80M )
        z80Remain := 129                            ' 128 data + checksum (132/133 total with header)
        z80Parse := PARSE_XMODEM
      else
        z80Parse := PARSE_IDLE                      ' bad header; back to normal stream

    PARSE_XMODEM:                                   ' payload to FTDI only (not VGA)
      term.tx (char)
      z80Remain := z80Remain - 1
      if ( z80Remain == 0 )
        z80Parse := PARSE_IDLE

    other:                                          ' PARSE_IDLE
      takeZ80Idle (char)


PRI takeZ80Idle(char)
{{Idle-state byte: XMODEM SOH, edits, CR, ESC, or printable.}}

  case char

    XMODEM_SOH:                                     ' XMODEM Start of Header
      term.tx (char)
      z80Parse := PARSE_XMODEM_N

    ASCII_BS, ASCII_DEL:                            ' backspace (edit), delete
      term.tx (ASCII_BS)
      term.tx (ASCII_SPACE)
      term.tx (ASCII_BS)
      if ( gTextCursX > 0 )
        --gTextCursX
      wmf.outScreen (wmf#BS)
      wmf.outScreen (wmf#ASCII_SPACE)
      wmf.outScreen (wmf#BS)

    ASCII_TAB:                                      ' horizontal tab
      term.tx (char)
      if ( gTextCursX < gScreenCols-5 )
        repeat
          ++gTextCursX
        while gTextCursX & 3
      wmf.outScreen (wmf#TB)

    ASCII_LF:                                       ' eat linefeed from Z80

    ASCII_CR:                                       ' carriage return
      term.lineFeed
      gTextCursX := 0
      if ( gTextCursY < gScreenRows-1 )
        ++gTextCursY
      wmf.outScreen (wmf#NL)

    ASCII_ESC:                                      ' escape; next byte decides CSI vs literal
      term.tx (char)
      z80Parse := PARSE_ESC

    other:                                          ' all other cases
      term.tx (char)
      echoPrintable (char)


PRI echoPrintable(char)
{{Write a printable byte to the VGA cursor. Control bytes are ignored here.}}

  if ( char => $20 )                                ' only printable characters to the screen
    if ( gTextCursX < gScreenCols - 1 )
      ++gTextCursX
    else
      if ( gTextCursY < gScreenRows - 1 )
        ++gTextCursY
      gTextCursX := 0
    wmf.outScreen (char)


PRI applyCsiH
{{CSI CUP with two parameters: ESC [ n ; m H}}

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
{{Apply a CSI final byte that uses n only (not the semicolon form).}}

  case char

    "A":                                            ' cursor up
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursY > z80N // gScreenRows - 1 )
        gTextCursY := gTextCursY - z80N // gScreenRows
        wmf.outScreen (wmf#PY)
        wmf.outScreen (gTextCursY)

    "B":                                            ' cursor down
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursY < gScreenRows - z80N // gScreenRows )
        gTextCursY := gTextCursY + z80N // gScreenRows
        wmf.outScreen (wmf#PY)
        wmf.outScreen (gTextCursY)

    "C":                                            ' cursor right
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursX < gScreenCols - z80N // gScreenCols )
        gTextCursX := gTextCursX + z80N // gScreenCols
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "D":                                            ' cursor left
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursX > z80N // gScreenCols - 1 )
        gTextCursX := gTextCursX - z80N // gScreenCols
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "E":                                            ' cursor next line n start
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursY < gScreenRows - z80N // gScreenRows )
        gTextCursY := gTextCursY + z80N // gScreenRows
        gTextCursX := 0
        wmf.outScreen (wmf#PY)
        wmf.outScreen (gTextCursY)
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "F":                                            ' cursor previous line n start
      if ( z80N == 0 )
        ++z80N
      if ( gTextCursY > z80N // gScreenRows - 1 )
        gTextCursY := gTextCursY - z80N // gScreenRows
        gTextCursX := 0
        wmf.outScreen (wmf#PY)
        wmf.outScreen (gTextCursY)
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "G":                                            ' cursor to column n
      if ( z80N == 0 )
        ++z80N
      gTextCursX := z80N // gScreenCols - 1
      wmf.outScreen (wmf#PX)
      wmf.outScreen (gTextCursX)

    "H":                                            ' cursor to row n, column 1
      if ( z80N == 0 )
        ++z80N
      gTextCursY := z80N // gScreenRows - 1
      gTextCursX := 0
      wmf.outScreen (wmf#PY)
      wmf.outScreen (gTextCursY)
      wmf.outScreen (wmf#PX)
      wmf.outScreen (gTextCursX)

    "J":                                            ' clear screen
      if ( z80N == 0 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenRows*gScreenCols - gTextCursY*gScreenCols - gTextCursX )
      elseif ( z80N == 1 )
        bytefill ( gScreenBufferPtr, ASCII_SPACE, gTextCursY*gScreenCols + gTextCursX + 1 )
      elseif ( z80N == 2 )
        gTextCursX := gTextCursY := 0
        wmf.outScreen ( wmf#CS )

    "K":                                            ' clear line
      if ( z80N == 0 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenCols - gTextCursX)
      elseif ( z80N == 1 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gTextCursX + 1 )
      elseif ( z80N == 2 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gScreenCols )
        gTextCursX := 0
        wmf.outScreen (wmf#PX)
        wmf.outScreen (gTextCursX)

    "m":                                            ' set graphics rendition parameters
      if ( z80N == 0 )
        wmf.setLineColor ( gTextCursY, wmf#CTHEME_DEFAULT_FG, wmf#CTHEME_DEFAULT_BG )
      elseif ( z80N == 7 )
        wmf.setLineColor ( gTextCursY, wmf#CTHEME_DEFAULT_BG, wmf#CTHEME_DEFAULT_FG )


PUB kbdToZ80 | char, n
{{PS/2 keys into the ACIA TX FIFO. Called from main except during XMODEM.}}

    n := 0
    repeat while kbd.gotKey and n < PUMP_LIMIT

      char := kbd.peekKey

      case char
        kbd#KBD_ASCII_UP, kbd#KBD_ASCII_DOWN, kbd#KBD_ASCII_RIGHT, kbd#KBD_ASCII_LEFT, kbd#KBD_ASCII_HOME:
          if acia.txSpace < 3                       ' CSI is ESC [ x — need three FIFO slots
            quit
        other:
          if not acia.txCheck                       ' one slot for a normal key
            quit

      char := kbd.getKey
      n++

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

          dira[ acia#RESET_PIN_NUM ]~~              ' pulse RC2014 /RESET (Z80 drops the bus)
          dira[ acia#RESET_PIN_NUM ]~
          acia.masterReset                          ' both FIFOs, last_rdr, tdre_hold, status
          z80Parse := PARSE_IDLE                    ' abandon ESC/CSI/XMODEM in progress

          term.clear                                ' clear the serial terminal

          gTextCursX := gTextCursY := 0             ' home the VGA cursor
          wmf.outScreen ( wmf#CS )                  ' clear the screen

        other:                                      ' all other input
          acia.tx (char)


PUB termToZ80 | n
{{FTDI RX into the ACIA TX FIFO. Same cog as kbdToZ80. No XON/XOFF.}}

  n := 0
  repeat while term.rxCount > 0 and acia.txCheck and n < PUMP_LIMIT
    acia.tx (term.rx)
    n++


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
