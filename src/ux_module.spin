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
  PORT_ROMWBW   = acia#PORT_40                          ' Alternate ACIA base port, when used together with SIO/2 Module on 0x80
  PORT_DEFAULT  = acia#PORT_80                          ' Default ACIA base port
  PORT_VJET     = acia#PORT_C0                          ' reserved Z80 graphics port; not decoded yet


CON

  ' set these constants based on the Propeller VGA hardware
  VGA_BASE_PIN  = 16                                    ' VGA pins 16-23

  ' set these constants based on the Propeller PS/2 hardware
  KBD_DATA_PIN  = 27                                    ' KEYBOARD data pin
  KBD_CLK_PIN   = 26                                    ' KEYBOARD clock pin

  ' DDC I2C pins live in ddc_i2c.spin (P29 SCL, P28 SDA). Boot EEPROM is the swapped pair.

  ' import some constants from the Propeller Window Manager
  VGACOLS       = wmf#VGACOLS
  VGAROWS       = wmf#VGAROWS


CON

  ' ASCII control codes

  ASCII_NULL    = $00                                   ' null character

  ASCII_BELL    = $07                                   ' bell
  ASCII_BS      = $08                                   ' backspace
  ASCII_TAB     = $09                                   ' horizontal tab
  ASCII_LF      = $0A                                   ' line feed
  ASCII_VT      = $0B                                   ' vertical tab
  ASCII_FF      = $0C                                   ' form feed (new page)
  ASCII_CR      = $0D                                   ' carriage return

  ASCII_ESC     = $1B                                   ' escape

  ASCII_SPACE   = $20                                   ' space
  ASCII_HASH    = $23                                   ' #
  ASCII_COMMA   = $2C                                   ' ,
  ASCII_PERIOD  = $2E                                   ' .

  ASCII_SEMI    = $3B                                   ' ;

  ASCII_0       = $30                                   ' 0
  ASCII_9       = $39                                   ' 9

  ASCII_LB      = $5B                                   ' [
  ASCII_RB      = $5D                                   ' ]

  ASCII_DEL     = $7F                                   ' delete

CON

  ' XMODEM control codes

  XMODEM_SOH    = $01                                   ' Start of Header (128-byte packet)
  XMODEM_STX    = $02                                   ' Start of Header (1024-byte packet)
  XMODEM_EOT    = $04                                   ' End of Transmission (passed through as data)
  XMODEM_ACK    = $06                                   ' Acknowledge
  XMODEM_NAK    = $15                                   ' Negative acknowledge
  XMODEM_ETB    = $17                                   ' End of Transmission Block
  XMODEM_CAN    = $18                                   ' Cancel
  XMODEM_C      = $43                                   ' receiver CRC request

  ' Non-blocking Z80 output parser (readZ80). Up to PUMP_LIMIT bytes per call.
  PARSE_IDLE      = 0                                   ' normal stream
  PARSE_ESC       = 1                                   ' saw ESC, waiting for next byte
  PARSE_CSI       = 2                                   ' ESC [ ... collecting n
  PARSE_CSI_M     = 3                                   ' ESC [ n ; ... collecting m
  PARSE_XMODEM_N  = 4                                   ' SOH/STX, waiting packet number
  PARSE_XMODEM_M  = 5                                   ' waiting complemented packet number
  PARSE_XMODEM    = 6                                   ' data bytes (z80Remain)
  PARSE_XMODEM_CS = 7                                   ' opaque trailers (z80XmTrail: 1 checksum, 2 CRC)

  HOST_XM_OFF     = 0                                   ' no host→Z80 XMODEM session
  HOST_XM_GAP     = 1                                   ' between packets: SOH/STX/EOT/ETB/CAN only
  HOST_XM_BLK     = 2
  HOST_XM_NBLK    = 3
  HOST_XM_DATA    = 4
  HOST_XM_TRAIL   = 5

  PUMP_LIMIT      = 16                                  ' max bytes each of kbd / FTDI / ACIA drain per main-loop pass


VAR

' -----------------------------------------------------------------------------
' DECLARED VARIABLES, ARRAYS, ETC.
' -----------------------------------------------------------------------------

  byte  gScreenRows, gScreenCols                        ' convenient globals to store number of screen columns and rows

  ' these data structures contains two cursors in the format [x,y,mode]
  ' these are passed to the VGA driver, so it can render them over the text in the display
  ' like "hardware" cursors, that don't disturb the graphics under them. We can use them
  ' to show where the text cursor and mouse cursor is
  ' The data structure is 6 contiguous bytes which we pass to the VGA driver ultimately

  byte  gTextCursX, gTextCursY, gTextCursMode           ' text cursor 0 [x0,y0,mode0]
  byte  gMouseCursX, gMouseCursY, gMouseCursMode        ' mouse cursor 1 [x1,y1,mode1] (unused but required for VGA driver)

  long  gScreenBufferPtr                                ' holds the address of the video buffer passed back from the VGA driver

  byte  z80Parse                                        ' PARSE_* state for readZ80
  byte  z80XmSess                                       ' Z80→host session (SOH/STX until idle EOT/ETB/CAN)
  byte  z80XmCrc                                        ' 1: CRC-16 trailers (2), 0: checksum (1)
  byte  z80XmTrail                                      ' trailer bytes still opaque
  byte  hostXm                                          ' HOST_XM_* host→Z80 packet machine
  byte  hostXmCrc                                       ' 1: CRC-16 trailers for host packets
  byte  hostXmTrail
  long  hostXmLen                                       ' 128 or 1024
  long  hostXmRemain
  long  z80N, z80M                                      ' CSI n and m (ESC [ n ; m H)
  long  z80Remain                                       ' XMODEM data bytes still to copy to FTDI
  long  z80XmLen                                        ' 128 (SOH) or 1024 (STX)
  byte  busRstArmed                                     ' 1: P5 low, debounce clock running
  byte  busRstDidWipe                                   ' 1: already wiped this backplane pulse
  long  busRstStamp                                     ' CNT at first P5-low sample


OBJ

      term            : "terminal_ftdi"
      kbd             : "keyboard_ps2"
      wmf             : "wmf_terminal_vga"
      i2c             : "ddc_i2c"
      acia            : "acia_rc2014"


PUB main | busHeld

  'start the serial terminal
  term.start (115200)
  term.str (string("UX Module Initialised"))
  term.newLine

  'start the ACIA interface
  acia.start (PORT_DEFAULT)                             'default for RC2014 ROM
' acia.start (PORT_ROMWBW)  'optional for RomWBW, when used together with SIO/2 Module on 0x80

  waitcnt (clkfreq / 100 + cnt)                         ' 10 ms for the ACIA cog
  screenInit
  startDdc
  kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)
  pulseZ80Reset

  ' MAIN COG EVENT LOOP — one writer for acia.tx (no extra pump cog).
  ' Skip the keyboard while Z80→host or host→Z80 XMODEM is in progress.
  ' Backplane /RESET holds P5 low through D1/C12. Do not drive P5. Wipe once.
  repeat
    busHeld := pollBusReset
    if acia.takeParseIdle                               ' Z80 CR_RESET: abandon ESC/CSI/XMODEM
      z80Parse := PARSE_IDLE
      z80XmSess := 0
      hostXm := HOST_XM_OFF
    if not busHeld
      if not inXmodem and not hostXmodem
        kbdToZ80
      termToZ80
      readZ80


PRI pulseZ80Reset
{{Drive RC2014 !RESET 1 ms. Drop host leftovers before the 8085 runs.}}

  holdZ80Reset
  waitcnt (clkfreq / 1000 + cnt)                        ' 1 ms; C12 is 200 pF and does not stretch
  wipeAciaWhileReset
  releaseZ80Reset


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
  syncCurs

  ' return to caller
  return


PRI startDdc
{{Start the DDC I2C cog after VGA. Read EDID, then DDC/CI brightness. Report on FTDI and VGA.
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
{{One EDID line and one DDC/CI line. Overlay cursor follows WMF.}}

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
  syncCurs


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
        if wmf.getColScreen > 0
          n := 3
        else
          n := 0
      ASCII_LF:
        n := 0
      ASCII_CR:
        n := 2                                          ' term.newLine sends CR then LF


PRI inXmodem : truefalse
{{True for the whole Z80→host XMODEM session, including the ACK gap.}}

  truefalse := z80XmSess


PRI hostXmodem : truefalse
{{True while the host→Z80 packet machine is not OFF (includes GAP).}}

  truefalse := hostXm <> HOST_XM_OFF


PRI takeZ80Byte(char)
{{One byte from the ACIA RX FIFO. Advances PARSE_* without waiting for more input.}}

  case z80Parse

    PARSE_ESC:                                          ' byte after ESC
      term.tx (char)
      if ( char == ASCII_LB )                           ' CSI Control Sequence Introducer
        z80N := 0
        z80Parse := PARSE_CSI
      else
        echoPrintable (char)                            ' printable non-CSI after ESC
        z80Parse := PARSE_IDLE

    PARSE_CSI:                                          ' ESC [ n ...
      term.tx (char)
      if ( char => "0" AND char =< "9" )
        z80N := z80N*10 + char - ASCII_0
      elseif ( char == ASCII_SEMI )
        z80M := 0
        z80Parse := PARSE_CSI_M
      else
        applyCsi (char)
        z80Parse := PARSE_IDLE

    PARSE_CSI_M:                                        ' ESC [ n ; m ...
      term.tx (char)
      if ( char => "0" AND char =< "9" )
        z80M := z80M*10 + char - ASCII_0
      else
        if ( char == "H" )                              ' cursor to row n, column m
          applyCsiH
        z80Parse := PARSE_IDLE

    PARSE_XMODEM_N:                                     ' packet number
      term.tx (char)
      z80N := char
      z80Parse := PARSE_XMODEM_M

    PARSE_XMODEM_M:                                     ' complemented packet number
      term.tx (char)
      z80M := char
      if ( z80N == $FF - z80M )
        z80Remain := z80XmLen                           ' 128 or 1024 data; trailers follow
        z80Parse := PARSE_XMODEM
      else
        z80XmSess := 0                                  ' bad header; do not keep the keyboard muted
        z80Parse := PARSE_IDLE                          ' n/~n already on FTDI, no payload yet

    PARSE_XMODEM:                                       ' payload to FTDI only (not VGA)
      term.tx (char)
      z80Remain := z80Remain - 1
      if ( z80Remain == 0 )
        z80Parse := PARSE_XMODEM_CS

    PARSE_XMODEM_CS:                                    ' checksum or CRC bytes; never delimiters
      term.tx (char)
      z80XmTrail := z80XmTrail - 1
      if ( z80XmTrail == 0 )
        z80Parse := PARSE_IDLE

    other:                                              ' PARSE_IDLE
      takeZ80Idle (char)


PRI takeZ80Idle(char)
{{Idle-state byte: XMODEM SOH, edits, CR, ESC, or printable.}}

  case char

    XMODEM_SOH:                                         ' XMODEM-128 Start of Header
      term.tx (char)
      z80XmLen := 128
      if z80XmCrc
        z80XmTrail := 2
      else
        z80XmTrail := 1
      z80XmSess := 1
      z80Parse := PARSE_XMODEM_N

    XMODEM_STX:                                         ' XMODEM-1K Start of Header (CRC-16)
      term.tx (char)
      z80XmLen := 1024
      z80XmCrc := 1
      z80XmTrail := 2
      z80XmSess := 1
      z80Parse := PARSE_XMODEM_N

    XMODEM_EOT, XMODEM_ETB, XMODEM_CAN:
      term.tx (char)
      z80XmSess := 0

    ASCII_BS, ASCII_DEL:                                ' backspace (edit), delete
      if wmf.getColScreen > 0
        term.tx (ASCII_BS)
        term.tx (ASCII_SPACE)
        term.tx (ASCII_BS)
        textOut (wmf#BS)
        textOut (wmf#ASCII_SPACE)
        textOut (wmf#BS)
      syncCurs

    ASCII_TAB:                                          ' horizontal tab; WMF owns glyph cursor
      term.tx (char)
      wmf.outScreen (wmf#TB)
      syncCurs

    ASCII_LF:                                           ' eat linefeed from Z80 (CP/M CR+LF)

    ASCII_CR:                                           ' carriage return
      term.newLine                                      ' CR+LF for PST / typical hosts
      textOut (wmf#NL)
      syncCurs

    ASCII_ESC:                                          ' escape; next byte decides CSI vs literal
      term.tx (char)
      z80Parse := PARSE_ESC

    other:                                              ' all other cases
      term.tx (char)
      echoPrintable (char)


PRI echoPrintable(char)
{{Write a printable byte through WMF, then copy the overlay from WMF.}}

  if ( char => $20 )                                    ' only printable characters to the screen
    textOut (char)
    syncCurs


PRI clampCurs(v, maxv) : r
{{Clamp v to 0 .. maxv-1.}}

  if v < 0
    r := 0
  elseif v => maxv
    r := maxv - 1
  else
    r := v


PRI syncCurs
{{Hardware overlay follows WMF column and row.}}

  gTextCursX := wmf.getColScreen
  gTextCursY := wmf.getRowScreen


PRI setCursXY(x, y)
{{Clamp and publish the overlay and WMF cursors.}}

  gTextCursX := clampCurs (x, gScreenCols)
  gTextCursY := clampCurs (y, gScreenRows)
  textOut (wmf#PY)
  textOut (gTextCursY)
  textOut (wmf#PX)
  textOut (gTextCursX)
  syncCurs


PRI textOut(c)
{{VGA text cell write.}}

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

    "A":                                                ' cursor up
      setCursXY (gTextCursX, gTextCursY - z80N)

    "B":                                                ' cursor down
      setCursXY (gTextCursX, gTextCursY + z80N)

    "C":                                                ' cursor right
      setCursXY (gTextCursX + z80N, gTextCursY)

    "D":                                                ' cursor left
      setCursXY (gTextCursX - z80N, gTextCursY)

    "E":                                                ' cursor next line n start
      setCursXY (0, gTextCursY + z80N)

    "F":                                                ' cursor previous line n start
      setCursXY (0, gTextCursY - z80N)

    "G":                                                ' cursor to column n
      setCursXY (z80N - 1, gTextCursY)

    "H":                                                ' cursor to row n, column 1
      setCursXY (0, z80N - 1)

    "J":                                                ' clear screen
      if ( z80N == 0 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenRows*gScreenCols - gTextCursY*gScreenCols - gTextCursX )
      elseif ( z80N == 1 )
        bytefill ( gScreenBufferPtr, ASCII_SPACE, gTextCursY*gScreenCols + gTextCursX + 1 )
      elseif ( z80N == 2 )
        textOut ( wmf#CS )
      syncCurs

    "K":                                                ' clear line
      if ( z80N == 0 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols + gTextCursX, ASCII_SPACE, gScreenCols - gTextCursX)
      elseif ( z80N == 1 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gTextCursX + 1 )
      elseif ( z80N == 2 )
        bytefill ( gScreenBufferPtr + gTextCursY*gScreenCols, ASCII_SPACE, gScreenCols )
        gTextCursX := 0
        textOut (wmf#PX)
        textOut (gTextCursX)
      syncCurs

    "m":                                                ' set graphics rendition parameters
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
          if acia.txSpace < 3                           ' CSI is ESC [ x — need three FIFO slots
            quit
        other:
          if not acia.txCheck                           ' one slot for a normal key
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

        other:                                          ' all other input
          acia.tx (char)


PUB termToZ80 | n, b
{{FTDI RX into the ACIA TX FIFO. Same cog as kbdToZ80. No XON/XOFF.
  Host packet machine: EOT/ETB/CAN end the session only in OFF or GAP.}}

  n := 0
  repeat while term.rxCount > 0 and acia.txCheck and n < PUMP_LIMIT
    b := term.rx
    takeHostXm (b)
    acia.tx (b)
    n++


PRI takeHostXm(b)
{{Advance HOST_XM_*. Payload bytes are never session delimiters.}}

  case hostXm

    HOST_XM_BLK:
      hostXm := HOST_XM_NBLK

    HOST_XM_NBLK:
      hostXmRemain := hostXmLen
      hostXm := HOST_XM_DATA

    HOST_XM_DATA:
      hostXmRemain := hostXmRemain - 1
      if hostXmRemain == 0
        hostXm := HOST_XM_TRAIL

    HOST_XM_TRAIL:
      hostXmTrail := hostXmTrail - 1
      if hostXmTrail == 0
        hostXm := HOST_XM_GAP

    other:                                              ' OFF or GAP
      if b == XMODEM_SOH
        hostXmBegin (128)
      elseif b == XMODEM_STX
        hostXmCrc := 1
        hostXmBegin (1024)
      elseif b == XMODEM_EOT or b == XMODEM_ETB or b == XMODEM_CAN
        hostXm := HOST_XM_OFF
      elseif hostXm == HOST_XM_OFF and b == XMODEM_NAK
        z80XmCrc := 0
      elseif hostXm == HOST_XM_OFF and b == XMODEM_C
        z80XmCrc := 1


PRI hostXmBegin(len)
{{Enter a host→Z80 data packet after SOH or STX.}}

  hostXmLen := len
  if len == 1024
    hostXmTrail := 2
  elseif hostXmCrc
    hostXmTrail := 2
  else
    hostXmTrail := 1
  hostXm := HOST_XM_BLK


PRI holdZ80Reset
{{Drive P5 low. Spin DIRA[5] stays set until releaseZ80Reset.}}

  outa[ acia#RESET_PIN_NUM ]~
  dira[ acia#RESET_PIN_NUM ]~~


PRI releaseZ80Reset
{{Float P5. ACIA PASM DIRA does not drive this pin.}}

  dira[ acia#RESET_PIN_NUM ]~


PRI discardHostInputs
{{Drop FTDI RX and PS/2 so they cannot refill the ACIA TX FIFO.}}

  repeat while term.rxCount > 0
    term.rx
  repeat while kbd.gotKey
    kbd.getKey


PRI wipeAciaWhileReset
{{Z80 must already be in reset. Restart the ACIA cog so last_rdr and both
  FIFOs are zero. Do not wait on req_master (PASM is in waitpeq). Discard
  FTDI RX and PS/2 so termToZ80 cannot inject leftovers after release.}}

  discardHostInputs
  acia.start (PORT_DEFAULT)                             ' stop + cognew; last_rdr := 0
  waitcnt (clkfreq / 1000 + cnt)                        ' ACIA cog before 8085 runs
  acia.tdreHold                                         ' keep TDR closed until readZ80 sees FTDI room
  z80Parse := PARSE_IDLE
  z80XmSess := 0
  hostXm := HOST_XM_OFF


PRI pollBusReset : held
{{True while the backplane holds /RESET and we are not driving P5.
  D1 pulls P5 high when /RESET is idle. A 1 ms low is a button pulse.
  Wipe FIFOs once. Do not drive P5.}}

  if dira[ acia#RESET_PIN_NUM ]                         ' our pulse owns the pin
    busRstArmed := 0
    busRstDidWipe := 0
    held := 0
    return
  if ina[ acia#RESET_PIN_NUM ]
    busRstArmed := 0
    busRstDidWipe := 0
    held := 0
    return
  held := 1
  if busRstArmed == 0
    busRstArmed := 1
    busRstStamp := cnt
    return
  if busRstDidWipe
    discardHostInputs
    return
  if (cnt - busRstStamp) < clkfreq / 1000               ' 1 ms debounce
    return
  wipeAciaWhileReset
  busRstDidWipe := 1


PRI panicReset
{{Hold RC2014 !RESET while the ACIA is reset, then clear local consoles without blocking.}}

  holdZ80Reset
  waitcnt (clkfreq / 1000 + cnt)                        ' 1 ms; C12 is 200 pF and does not stretch
  wipeAciaWhileReset
  textOut (wmf#CS)
  syncCurs
  if term.txSpace => 4                                  ' ESC [ 2 J
    term.clear
  releaseZ80Reset                                       ' release Z80 after local state is quiet


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
