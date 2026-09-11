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

  ' Bring-up. One of these is 1, or both 0 for the full path.
  DIAG_TERM_ECHO   = 0  ' FTDI local echo only
  DIAG_ACIA_BRIDGE = 1  ' shipped path: FTDI + ACIA + text VGA + PS/2 + DDC. No VECTORJET.


CON

  ' import some constants from the ACIA Emulation
  PORT_ROMWBW   = acia#PORT_40  ' Alternate ACIA base port, when used together with SIO/2 Module on 0x80
  PORT_DEFAULT  = acia#PORT_80  ' Default ACIA base port
  PORT_VJET     = acia#PORT_C0  ' reserved Z80 graphics port; not decoded yet


CON

  ' set these constants based on the Propeller VGA hardware
  VGA_BASE_PIN  = 16  ' VGA pins 16-23

  ' set these constants based on the Propeller PS/2 hardware
  KBD_DATA_PIN  = 27  ' KEYBOARD data pin
  KBD_CLK_PIN   = 26  ' KEYBOARD clock pin

  ' I2C DDC pins live in i2c.spin (P29 SCL, P28 SDA). Boot EEPROM is the swapped pair.

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

  XMODEM_SOH    = $01 ' Start of Header (128-byte packet)
  XMODEM_STX    = $02 ' Start of Header (1024-byte packet)
  XMODEM_EOT    = $04 ' End of Transmission (passed through as data)
  XMODEM_ACK    = $06 ' Acknowledge
  XMODEM_NAK    = $15 ' Negative acknowledge
  XMODEM_ETB    = $17 ' End of Transmission Block
  XMODEM_CAN    = $18 ' Cancel

  ' Non-blocking Z80 output parser (readZ80). Up to PUMP_LIMIT bytes per call.
  PARSE_IDLE      = 0   ' normal stream
  PARSE_ESC       = 1   ' saw ESC, waiting for next byte
  PARSE_CSI       = 2   ' ESC [ ... collecting n
  PARSE_CSI_M     = 3   ' ESC [ n ; ... collecting m
  PARSE_XMODEM_N  = 4   ' SOH/STX, waiting packet number
  PARSE_XMODEM_M  = 5   ' waiting complemented packet number
  PARSE_XMODEM    = 6   ' data bytes (z80Remain)
  PARSE_XMODEM_CS = 7   ' first trailer (checksum or CRC hi)
  PARSE_XMODEM_CRC= 8   ' second trailer unless next-frame start

  PUMP_LIMIT      = 16  ' max bytes each of kbd / FTDI / ACIA drain per main-loop pass

  VIDEO_TEXT      = 0   ' hires_text_vga owns P16-P23 (boot / serial console)
  VIDEO_GRAPHICS  = 1   ' VECTORJET owns P16-P23; enterGraphics, not boot
  VJET_PIN_GROUP  = VGA_BASE_PIN / 8
  VJET_RENDER_COGS = 2  ' VGA + 2 render; one cog left for a later Spin draw loop
  VJET_LINEBUF_LONGS = vjetrend#WIDTH * vjetrend#LINE_BUFFERS / 4
  VJET_DLIST_LONGS = 4  ' empty list (next=0); grow when a draw cog exists


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
  byte  hostXmodem                                    ' FTDI SOH/STX seen; skip keyboard until EOT/CAN
  long  z80N, z80M                                    ' CSI n and m (ESC [ n ; m H)
  long  z80Remain                                     ' XMODEM data bytes still to copy to FTDI
  long  z80XmLen                                      ' 128 (SOH) or 1024 (STX)

  long  videoMode                                     ' VIDEO_TEXT or VIDEO_GRAPHICS; Cog 0 writer
  long  vjetStatus                                    ' VECTORJET VGA phase; VGA cog writer
  long  vjetDlistPtr                                  ' live display list; Cog 0 at switch, later draw cog
  long  vjetReady                                     ' render cogs wait for non-zero; Cog 0 writer
  long  vjetLinebuf[VJET_LINEBUF_LONGS]
  long  vjetList[VJET_DLIST_LONGS]                    ' empty list until a draw cog publishes one


OBJ

      term            : "terminal_ftdi"
      kbd             : "keyboard_ps2"
      wmf             : "wmf_terminal_vga"
      i2c             : "i2c"
      acia            : "acia_rc2014"
      vjetvga         : "VJET_vUXM_vga"             ' src/lib_vjet (add that folder to the search path)
      vjetrend        : "VJET_vUXM_rendering"
      gl              : "VJET_v01_displaylist"      ' display-list builder; boot uses an empty list


PUB main

  'start the serial terminal
  term.start (115200)
  term.str (string("UX Module Initialised"))
  term.newLine

  if DIAG_TERM_ECHO                                   ' first bring-up: echo host bytes on FTDI
    termEchoLoop

  'start the ACIA interface
  acia.start (PORT_DEFAULT) 'default for RC2014 ROM
' acia.start (PORT_ROMWBW)  'optional for RomWBW, when used together with SIO/2 Module on 0x80

  if DIAG_ACIA_BRIDGE                                 ' FTDI + ACIA + text VGA + PS/2
    waitcnt (clkfreq / 100 + cnt)                     ' 10 ms for the ACIA cog
    screenInit
    startDdc
    kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)
    pulseZ80Reset
    aciaBridgeLoop

  'start the VGA text screen (serial console). Call enterGraphics from a later draw cog, not from main.
  screenInit

  'start the keyboard
  kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)

  startDdc

  ' MAIN COG EVENT LOOP — one writer for acia.tx (no extra pump cog).
  ' Skip the keyboard while Z80→host or host→Z80 XMODEM is in progress.
  repeat
    if acia.takeParseIdle                             ' Z80 CR_RESET: abandon ESC/CSI/XMODEM
      z80Parse := PARSE_IDLE
      hostXmodem := 0
    if not inXmodem and not hostXmodem
      kbdToZ80
    termToZ80
    readZ80


PUB termEchoLoop | char
{{FTDI RX to FTDI TX. No ACIA. CR becomes CR+LF. LF is ignored after CR.}}

  repeat
    if term.rxCheck
      char := term.rx
      if char == ASCII_CR
        term.newLine
      elseif char <> ASCII_LF
        term.tx (char)


PUB aciaBridgeLoop | n
{{Host and PS/2 bytes to Z80 RDR. Z80 TDR to FTDI and text VGA.
  No local echo. No VECTORJET.}}

  repeat
    if acia.takeParseIdle                             ' Z80 CR_RESET: abandon ESC/CSI/XMODEM
      z80Parse := PARSE_IDLE
      hostXmodem := 0
    if not inXmodem and not hostXmodem
      kbdToZ80
    n := 0
    repeat while term.rxCount > 0 and acia.txCheck and n < PUMP_LIMIT
      acia.tx (term.rx)
      n++
    readZ80


PRI pulseZ80Reset
{{Drive RC2014 !RESET 1 ms. ACIA cog must already be running.}}

  outa[ acia#RESET_PIN_NUM ]~
  dira[ acia#RESET_PIN_NUM ]~~
  waitcnt (clkfreq / 1000 + cnt)
  dira[ acia#RESET_PIN_NUM ]~


CON

  '' Visual differentiation


PUB enterGraphics : okay
{{Stop text VGA and the I2C DDC cog. Start VECTORJET. Cog 0 still pumps ACIA.
  Empty list (black). Those three cogs become VGA + two render cogs.
  Call from a later draw cog or PORT_VJET handler. Not used at boot.}}

  if videoMode == VIDEO_GRAPHICS
    return true

  wmf.stop                                              ' free P16-P23
  stopDdc                                               ' free one cog for VECTORJET
  vjetReady := 0
  vjetDlistPtr := @vjetList
  gl.start (@vjetList, VJET_DLIST_LONGS * 4)            ' next=0 until a draw cog builds lists
  gl.done

  if not vjetvga.start(VJET_PIN_GROUP, @vjetLinebuf, @vjetStatus)
    resumeText
    return false
  if not vjetrend.start(0, VJET_RENDER_COGS, @vjetLinebuf, @vjetDlistPtr, @vjetStatus, @vjetReady)
    vjetvga.stop
    resumeText
    return false
  if not vjetrend.start(1, VJET_RENDER_COGS, @vjetLinebuf, @vjetDlistPtr, @vjetStatus, @vjetReady)
    vjetrend.stop
    vjetvga.stop
    resumeText
    return false

  videoMode := VIDEO_GRAPHICS
  vjetReady := 1                                        ' render cogs wait for this
  return true


PUB enterText
{{Stop VECTORJET. Restore VGA text and the I2C DDC cog. Cog 0 still pumps ACIA.}}

  if videoMode == VIDEO_TEXT
    return
  vjetReady := 0
  vjetrend.stop
  vjetvga.stop
  resumeText


PUB inGraphics : truefalse
{{True while VECTORJET owns P16-P23. Cog 0 still pumps ACIA.}}

  truefalse := videoMode == VIDEO_GRAPHICS


PUB screenInit | retVal
  ' Start VGA text and place the boot banner. Static init only.

  videoMode := VIDEO_TEXT

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


PRI resumeText
{{Text VGA plus I2C DDC. Used at a failed graphics start and at enterText.
  Does not wait for EDID. The I2C cog fills Hub when the read completes.}}

  screenInit
  i2c.startCog
  i2c.postEdid


PRI stopDdc
{{Free the I2C cog for VECTORJET. Pin DIRA drops when the cog stops.}}

  i2c.stopCog


PRI startDdc
{{Start the I2C cog after VGA. Read EDID, then DDC/CI brightness. Report on FTDI and VGA.
  Does not change VGA timing. Cog 0 waits up to 500 ms per request. Boot path only.}}

  if not i2c.startCog
    return
  i2c.postEdid
  i2c.waitIdle (500)
  if i2c.edidPresent
    i2c.postGetVcp (i2c#VCP_BRIGHT)
    i2c.waitIdle (500)
  reportDdc


PRI reportDdc
{{One EDID line and one DDC/CI line. Hardware cursor follows the VGA rows.}}

  term.str (string("EDID "))
  wmf.strScreen (string("EDID "))
  if i2c.edidPresent
    if byte[i2c.namePtr] <> 0
      term.str (i2c.namePtr)
      wmf.strScreen (i2c.namePtr)
    else
      term.str (i2c.mfgPtr)
      wmf.strScreen (i2c.mfgPtr)
    if i2c.hPix
      term.tx (" ")
      wmf.outScreen (" ")
      term.dec (i2c.hPix)
      wmf.decScreen (i2c.hPix, 4)
      term.tx ("x")
      wmf.outScreen ("x")
      term.dec (i2c.vPix)
      wmf.decScreen (i2c.vPix, 4)
  else
    term.str (string("none"))
    wmf.strScreen (string("none"))
  term.newLine
  wmf.newLine
  ++gTextCursY

  term.str (string("DDC/CI "))
  wmf.strScreen (string("DDC/CI "))
  if i2c.ddcPresent
    term.str (string("bright "))
    wmf.strScreen (string("bright "))
    term.dec (i2c.bright)
    wmf.decScreen (i2c.bright, 3)
  else
    term.str (string("none"))
    wmf.strScreen (string("none"))
  term.newLine
  wmf.newLine
  ++gTextCursY


PUB readZ80 | char, n, need
{{Drain Z80 TDR bytes to VGA and FTDI. Never blocks on acia.rx or term.tx.
  Bytes with ftdiNeed 0 (LF) still drain when FTDI TX is full.
  TDRE is allowed only when the next byte fits in FTDI TX.}}

    n := 0
    repeat while acia.rxCount > 0 and n < PUMP_LIMIT
      char := acia.rxPeek
      need := ftdiNeed (char)
      if need > 0 and term.txSpace < need
        quit
      char := acia.rx
      takeZ80Byte (char)
      n++

    if acia.rxCount > 0
      need := ftdiNeed (acia.rxPeek)
      if need > 0 and term.txSpace < need
        acia.tdreHold
      else
        acia.tdreAllow
    elseif term.txCheck
      acia.tdreAllow
    else
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
        n := 2                                        ' term.newLine sends CR then LF


PRI inXmodem : truefalse
{{True while readZ80 is inside a Z80→host XMODEM packet (SOH/STX through trailer).}}

  truefalse := z80Parse == PARSE_XMODEM_N or z80Parse == PARSE_XMODEM_M or z80Parse == PARSE_XMODEM or z80Parse == PARSE_XMODEM_CS or z80Parse == PARSE_XMODEM_CRC


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
        z80Remain := z80XmLen                       ' 128 or 1024 data; trailers follow
        z80Parse := PARSE_XMODEM
      else
        z80Parse := PARSE_IDLE                      ' bad header; n/~n already on FTDI, no payload yet

    PARSE_XMODEM:                                   ' payload to FTDI only (not VGA)
      term.tx (char)
      z80Remain := z80Remain - 1
      if ( z80Remain == 0 )
        z80Parse := PARSE_XMODEM_CS

    PARSE_XMODEM_CS:                                ' checksum or CRC hi
      term.tx (char)
      z80Parse := PARSE_XMODEM_CRC

    PARSE_XMODEM_CRC:                               ' CRC lo, or next-frame start (checksum mode)
      if char == XMODEM_SOH or char == XMODEM_STX or char == XMODEM_EOT or char == XMODEM_ETB or char == XMODEM_CAN
        z80Parse := PARSE_IDLE
        takeZ80Idle (char)
      else
        term.tx (char)
        z80Parse := PARSE_IDLE

    other:                                          ' PARSE_IDLE
      takeZ80Idle (char)


PRI takeZ80Idle(char)
{{Idle-state byte: XMODEM SOH, edits, CR, ESC, or printable.}}

  case char

    XMODEM_SOH:                                     ' XMODEM-128 Start of Header
      term.tx (char)
      z80XmLen := 128
      z80Parse := PARSE_XMODEM_N

    XMODEM_STX:                                     ' XMODEM-1K Start of Header
      term.tx (char)
      z80XmLen := 1024
      z80Parse := PARSE_XMODEM_N

    ASCII_BS, ASCII_DEL:                            ' backspace (edit), delete
      term.tx (ASCII_BS)
      term.tx (ASCII_SPACE)
      term.tx (ASCII_BS)
      if ( gTextCursX > 0 )
        --gTextCursX
      textOut (wmf#BS)
      textOut (wmf#ASCII_SPACE)
      textOut (wmf#BS)

    ASCII_TAB:                                      ' horizontal tab; WMF owns glyph cursor
      term.tx (char)
      if not videoMode
        wmf.outScreen (wmf#TB)
        gTextCursX := wmf.getColScreen
        gTextCursY := wmf.getRowScreen

    ASCII_LF:                                       ' eat linefeed from Z80

    ASCII_CR:                                       ' carriage return
      term.newLine                                  ' CR+LF for PST / typical hosts
      gTextCursX := 0
      if ( gTextCursY < gScreenRows-1 )
        ++gTextCursY
      textOut (wmf#NL)

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
    textOut (char)


PRI clampCurs(v, maxv) : r
{{Clamp v to 0 .. maxv-1.}}

  if v < 0
    r := 0
  elseif v => maxv
    r := maxv - 1
  else
    r := v


PRI setCursXY(x, y)
{{Clamp and publish the overlay and WMF cursors.}}

  gTextCursX := clampCurs (x, gScreenCols)
  gTextCursY := clampCurs (y, gScreenRows)
  textOut (wmf#PY)
  textOut (gTextCursY)
  textOut (wmf#PX)
  textOut (gTextCursX)


PRI textOut(c)
{{VGA text cell write. No-op in VECTORJET mode so Cog 0 still pumps ACIA.}}

  if not inGraphics
    wmf.outScreen (c)


PRI applyCsiH
{{CSI CUP with two parameters: ESC [ n ; m H}}

  if ( z80N == 0 )
    ++z80N
  if ( z80M == 0 )
    ++z80M
  setCursXY (z80M - 1, z80N - 1)


PRI applyCsi(char)
{{Apply a CSI final byte that uses n only (not the semicolon form).}}

  case char

    "A", "B", "C", "D", "E", "F", "G", "H":
      if ( z80N == 0 )
        ++z80N

  case char

    "A":                                            ' cursor up
      setCursXY (gTextCursX, gTextCursY - z80N)

    "B":                                            ' cursor down
      setCursXY (gTextCursX, gTextCursY + z80N)

    "C":                                            ' cursor right
      setCursXY (gTextCursX + z80N, gTextCursY)

    "D":                                            ' cursor left
      setCursXY (gTextCursX - z80N, gTextCursY)

    "E":                                            ' cursor next line n start
      setCursXY (0, gTextCursY + z80N)

    "F":                                            ' cursor previous line n start
      setCursXY (0, gTextCursY - z80N)

    "G":                                            ' cursor to column n
      setCursXY (z80N - 1, gTextCursY)

    "H":                                            ' cursor to row n, column 1
      setCursXY (0, z80N - 1)

    "J":                                            ' clear screen
      if not videoMode
        if ( z80N == 0 )
          bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenRows*gScreenCols - gTextCursY*gScreenCols - gTextCursX )
        elseif ( z80N == 1 )
          bytefill ( gScreenBufferPtr, ASCII_SPACE, gTextCursY*gScreenCols + gTextCursX + 1 )
        elseif ( z80N == 2 )
          gTextCursX := gTextCursY := 0
          textOut ( wmf#CS )

    "K":                                            ' clear line
      if not videoMode
        if ( z80N == 0 )
          bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenCols - gTextCursX)
        elseif ( z80N == 1 )
          bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gTextCursX + 1 )
        elseif ( z80N == 2 )
          bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gScreenCols )
          gTextCursX := 0
          textOut (wmf#PX)
          textOut (gTextCursX)

    "m":                                            ' set graphics rendition parameters
      if not videoMode
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
          panicReset

        other:                                      ' all other input
          acia.tx (char)


PUB termToZ80 | n, b
{{FTDI RX into the ACIA TX FIFO. Same cog as kbdToZ80. No XON/XOFF.
  SOH/STX from the host gates the keyboard until EOT/CAN.}}

  n := 0
  repeat while term.rxCount > 0 and acia.txCheck and n < PUMP_LIMIT
    b := term.rx
    if b == XMODEM_SOH or b == XMODEM_STX
      hostXmodem := 1
    elseif b == XMODEM_EOT or b == XMODEM_CAN
      hostXmodem := 0
    acia.tx (b)
    n++


PRI panicReset
{{Hold RC2014 !RESET while the ACIA is reset, then clear local consoles without blocking.}}

  outa[ acia#RESET_PIN_NUM ]~
  dira[ acia#RESET_PIN_NUM ]~~
  waitcnt (clkfreq / 1000 + cnt)                    ' 1 ms; C12 is 200 pF and does not stretch
  acia.masterReset                                  ' FIFOs, last_rdr, tdre_hold, config $03, status
  acia.tdreHold                                     ' keep TDR closed until readZ80 sees FTDI room
  z80Parse := PARSE_IDLE
  hostXmodem := 0
  gTextCursX := gTextCursY := 0
  textOut (wmf#CS)
  if term.txSpace => 4                              ' ESC [ 2 J
    term.clear
  dira[ acia#RESET_PIN_NUM ]~                       ' release Z80 after local state is quiet


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
