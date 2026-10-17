''***************************************
''*  User Experience Module             *
''*  Designed for RC2014                *
''*  Author: Phillip Stevens            *
''*  Copyright (c) 2021                 *
''*  See end of file for licence        *
''***************************************
''
'' Stage 1 bring-up top. Boot is the text console.
'' Ctrl+Alt+G enters VECTORJET. The same chord returns to text.
'' Control-G on the FTDI console does the same toggle.
'' Cog 0 parks on waitcnt. A tight second Spin loop tears the picture.
'' The draw cog uses the text buffer as its stack. Cog 0 has about 2KB free.
'' Three render cogs. The PS/2 cog stops for that session.
'' The ACIA cog and the FTDI cog stay up.
'' Product upload remains src/ux_module.spin.

CON

  _clkmode      = XTAL1 + PLL16X
  _xinfreq      = 7_372_800

  DLIST_SIZE    = 300                                   ' longs in each display list
  _STACK        = 256                                   ' Cog 0 stack, in longs. Cog 0 draws.


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

  byte  gfxMode                                         ' 1: VECTORJET owns P16-P23
  byte  gfxChordArm                                     ' 1: Ctrl+Alt+G is a new press
  byte  gfxNeedDdc                                      ' 1: start DDC after P5 is released
  long  gfxReady                                        ' render cogs rdbyte this. Must be long-aligned.
  long  drawCog                                         ' cognew id + 1, or 0
  long  framecount
  long  vga_status                                      ' VECTORJET VGA phase. VGA cog writes it.
  long  dlist_ptr                                       ' Cog 0 writes it. Render cogs read it.
  long  dlist1[DLIST_SIZE]                              ' demo handshake, list A
  long  dlist2[DLIST_SIZE]                              ' demo handshake, list B
  long  linebuffers[(render#WIDTH * render#LINE_BUFFERS) / 4]


OBJ

      term            : "terminal_ftdi"
      kbd             : "keyboard_ps2"
      wmf             : "wmf_terminal_vga"
      i2c             : "ddc_i2c"
      acia            : "acia_rc2014"
      vga             : "VJET_vUXM_vga"
      render          : "VJET_vUXM_rendering"
      gl              : "VJET_v01_displaylist"
      font            : "hexfont"


CON

  gfxChord = kbd#KBD_ASCII_CTRL | kbd#KBD_ASCII_ALT | kbd#KBD_ASCII_G


PUB main | busHeld

  'start the serial terminal, then the text VGA before slower boot work
  term.start (115200)
  screenInit
  term.str (string("UX Module Initialised"))
  term.newLine

  ' Hold the 8085 while DDC and the keyboard take their cogs.
  ' pulseZ80Reset starts the ACIA cog after those, on cog 6.
  ' Graphics stops text, DDC, and the keyboard. VGA takes cog 2.
  ' The draw cog takes cog 4. Render then takes cogs 3, 5, and 7.
  holdZ80Reset
  startDdc
  kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)
  gfxChordArm := 1
  pulseZ80Reset

  ' MAIN COG EVENT LOOP — one writer for acia.tx (no extra pump cog).
  ' Skip the keyboard while Z80→host or host→Z80 XMODEM is in progress.
  ' Backplane /RESET holds P5 low through D1/C12. Do not drive P5. Wipe once.
  repeat
    busHeld := pollBusReset
    if gfxNeedDdc and not busHeld
      i2c.startCog
      gfxNeedDdc := 0
    if acia.takeParseIdle                               ' Z80 CR_RESET: abandon ESC/CSI/XMODEM
      z80Parse := PARSE_IDLE
      z80XmSess := 0
      hostXm := HOST_XM_OFF
    if not busHeld
      if inXmodem or hostXmodem
        repeat while kbd.peekKey == gfxChord
          kbd.getKey
      else
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
{{PS/2 keys into the ACIA TX FIFO. Called from main except during XMODEM.
  Ctrl+Alt+Del and Ctrl+Alt+G run before the TX-full leave.}}

    n := 0
    if kbd.peekKey <> gfxChord
      gfxChordArm := 1
    repeat while kbd.gotKey and n < PUMP_LIMIT

      char := kbd.peekKey

      if char == (kbd#KBD_ASCII_CTRL | kbd#KBD_ASCII_ALT | kbd#KBD_ASCII_DEL)
        kbd.getKey
        n++
        panicReset
        next
      if char == gfxChord
        kbd.getKey
        n++
        if gfxChordArm and not inXmodem and not hostXmodem
          gfxChordArm := 0
          if gfxMode
            leaveGraphics
          else
            enterGraphics
        next

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

        other:                                          ' all other input
          acia.tx (char)


PUB termToZ80 | n, b
{{FTDI RX into the ACIA TX FIFO. Same cog as kbdToZ80. No XON/XOFF.
  Host packet machine: EOT/ETB/CAN end the session only in OFF or GAP.}}

  n := 0
  repeat while term.rxCount > 0 and acia.txCheck and n < PUMP_LIMIT
    b := term.rx
    if b == ASCII_BELL and not inXmodem and not hostXmodem
      n++
      if gfxMode
        leaveGraphics
      else
        enterGraphics
      next
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
  FTDI RX and PS/2 so termToZ80 cannot inject leftovers after release.
  A graphics session restores text before the ACIA cog restarts. DDC stays down
  until the caller releases P5.}}

  if gfxMode
    stopVectorjet
    screenInit
    gfxMode := 0
    gfxNeedDdc := 1
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
{{Hold RC2014 !RESET while the ACIA is reset, then clear local consoles without blocking.
  Stop VECTORJET before wmf.init. Do not hold P5 across the DDC cog.}}

  holdZ80Reset
  waitcnt (clkfreq / 1000 + cnt)                        ' 1 ms; C12 is 200 pF and does not stretch
  wipeAciaWhileReset
  textOut (wmf#CS)
  syncCurs
  if term.txSpace => 4                                  ' ESC [ 2 J
    term.clear
  releaseZ80Reset                                       ' release Z80 after local state is quiet


PRI enterGraphics
{{Stop text VGA, DDC, and the PS/2 cog, then start VECTORJET.
  Cog 0 waits. The draw cog builds the list. A tight Spin loop tears the picture.
  The ACIA cog and the FTDI cog stay up.}}

  if gfxMode or inXmodem or hostXmodem
    return
  gfxMode := 1
  wmf.stop
  i2c.stopCog
  kbd.stop
  waitcnt (clkfreq / 4 + cnt)                           ' 250 ms blank
  if not startVectorjet
    term.str (string("Graphics start failed"))
    term.newLine
    restoreText
    return
  repeat
    waitcnt (clkfreq / 10 + cnt)                        ' Cog 0 stays off the Hub
    if takeBell
      quit
  restoreText


PRI leaveGraphics
{{Stop VECTORJET and restore the text console.}}

  if gfxMode
    restoreText


PRI restoreText
{{Text VGA, the DDC cog, then the PS/2 cog. P5 must already be released.}}

  stopVectorjet
  screenInit
  i2c.startCog
  kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)
  gfxMode := 0
  gfxNeedDdc := 0


PRI stopVectorjet
{{Stop the draw cog, the render cogs, and the VECTORJET VGA cog.
  Do this before screenInit reuses the text buffer.}}

  gfxReady := 0
  if drawCog
    cogstop (drawCog~ - 1)
  render.stop
  vga.stop


PRI startVectorjet : ok
{{Start VGA, then one render cog, the draw cog, then the other two render cogs.
  With the ACIA cog on cog 6, render lands on cogs 3, 5, and 7.
  The empty list is published before ready.
  gfxReady is a long. cognew stores a long-aligned parameter address.
  On failure, stop every cog this call started.}}

  gfxReady := 0
  framecount := 0
  longfill (@dlist1, 0, DLIST_SIZE)
  longfill (@dlist2, 0, DLIST_SIZE)
  dlist_ptr := @dlist2
  if not vga.start (VGA_BASE_PIN / 8, @linebuffers, @vga_status)
    return 0
  if not render.start (0, 3, @linebuffers, @dlist_ptr, @vga_status, @gfxReady)
    vga.stop
    return 0
  drawCog := cognew (drawLoop, gScreenBufferPtr) + 1
  if not drawCog
    render.stop
    vga.stop
    return 0
  if not render.start (1, 3, @linebuffers, @dlist_ptr, @vga_status, @gfxReady)
    cogstop (drawCog~ - 1)
    render.stop
    vga.stop
    return 0
  if not render.start (2, 3, @linebuffers, @dlist_ptr, @vga_status, @gfxReady)
    cogstop (drawCog~ - 1)
    render.stop
    vga.stop
    return 0
  gfxReady := 1
  return 1


PRI drawLoop
{{Demo draw loop. Publish at the front porch, then build the other list.
  Stack is the text buffer. Text VGA is stopped.}}

  repeat
    vblank
    if framecount & 1
      dlist_ptr := @dlist1
      gl.start (@dlist2, constant(DLIST_SIZE * 4))
    else
      dlist_ptr := @dlist2
      gl.start (@dlist1, constant(DLIST_SIZE * 4))
    \drawScene
    gl.done
    framecount++


PRI takeBell : hit | b
{{Read queued FTDI bytes. Return true when one byte is Control-G.
  Other queued bytes are discarded for this picture test.}}

  repeat while term.rxCount > 0
    b := term.rx
    if b == ASCII_BELL
      return 1


PRI drawScene

  gl.set_clip (0, render#NUM_LINES << 16, 0, render#WIDTH << 16)
  gl.triangle (constant((render#WIDTH / 2) << 16), constant(-render#NUM_LINES << 16), constant(-render#WIDTH << 16), constant(render#NUM_LINES << 16), constant((2 * render#WIDTH) << 16), constant(render#NUM_LINES << 16), $ECEC)
  gl.triangle (208 << 16 + sin(framecount << 5) * 75, 90 << 16 + sin(2048 + framecount << 5) * 75, 208 << 16 + sin(2730 + framecount << 5) * 75, 90 << 16 + sin(4778 + framecount << 5) * 75, 208 << 16 + sin(5460 + framecount << 5) * 75, 90 << 16 + sin(7508 + framecount << 5) * 75, $0055)
  gl.triangle (192 << 16 + sin(framecount << 5) * 80, 90 << 16 + sin(2048 + framecount << 5) * 80, 192 << 16 + sin(2730 + framecount << 5) * 80, 90 << 16 + sin(4778 + framecount << 5) * 80, 192 << 16 + sin(5460 + framecount << 5) * 80, 90 << 16 + sin(7508 + framecount << 5) * 80, $5555)
  gl.triangle (176 << 16 + sin(framecount << 5) * 85, 90 << 16 + sin(2048 + framecount << 5) * 85, 176 << 16 + sin(2730 + framecount << 5) * 85, 90 << 16 + sin(4778 + framecount << 5) * 85, 176 << 16 + sin(5460 + framecount << 5) * 85, 90 << 16 + sin(7508 + framecount << 5) * 85, $55AA)
  gl.triangle (160 << 16 + sin(framecount << 5) * 90, 90 << 16 + sin(2048 + framecount << 5) * 90, 160 << 16 + sin(2730 + framecount << 5) * 90, 90 << 16 + sin(4778 + framecount << 5) * 90, 160 << 16 + sin(5460 + framecount << 5) * 90, 90 << 16 + sin(7508 + framecount << 5) * 90, $AAAA)
  gl.triangle (128 << 16 + sin(0 - framecount << 4) * 500, 90 << 16 + sin(2048 - framecount << 4) * 500, 128 << 16 + sin(0100 - framecount << 4) * 500, 90 << 16 + sin(2148 - framecount << 4) * 500, 128 << 16, 90 << 16, $C0C0)
  gl.triangle (128 << 16 + sin(0100 - framecount << 4) * 500, 90 << 16 + sin(2148 - framecount << 4) * 500, 128 << 16 + sin(0200 - framecount << 4) * 500, 90 << 16 + sin(2248 - framecount << 4) * 500, 128 << 16, 90 << 16, $D0D0)
  gl.triangle (128 << 16 + sin(0200 - framecount << 4) * 500, 90 << 16 + sin(2248 - framecount << 4) * 500, 128 << 16 + sin(0300 - framecount << 4) * 500, 90 << 16 + sin(2348 - framecount << 4) * 500, 128 << 16, 90 << 16, $F0F0)
  gl.triangle (128 << 16 + sin(0300 - framecount << 4) * 500, 90 << 16 + sin(2348 - framecount << 4) * 500, 128 << 16 + sin(0400 - framecount << 4) * 500, 90 << 16 + sin(2448 - framecount << 4) * 500, 128 << 16, 90 << 16, $7474)
  gl.triangle (128 << 16 + sin(0400 - framecount << 4) * 500, 90 << 16 + sin(2448 - framecount << 4) * 500, 128 << 16 + sin(0500 - framecount << 4) * 500, 90 << 16 + sin(2548 - framecount << 4) * 500, 128 << 16, 90 << 16, $3C3C)
  gl.triangle (128 << 16 + sin(0500 - framecount << 4) * 500, 90 << 16 + sin(2548 - framecount << 4) * 500, 128 << 16 + sin(0600 - framecount << 4) * 500, 90 << 16 + sin(2648 - framecount << 4) * 500, 128 << 16, 90 << 16, $4848)
  gl.triangle (144 << 16 + sin(framecount << 5) * 95, 90 << 16 + sin(2048 + framecount << 5) * 95, 144 << 16 + sin(2730 + framecount << 5) * 95, 90 << 16 + sin(4778 + framecount << 5) * 95, 144 << 16 + sin(5460 + framecount << 5) * 95, 90 << 16 + sin(7508 + framecount << 5) * 95, $AAFF)
  gl.triangle (128 << 16 + sin(framecount << 5) * 100, 90 << 16 + sin(2048 + framecount << 5) * 100, 128 << 16 + sin(2730 + framecount << 5) * 100, 90 << 16 + sin(4778 + framecount << 5) * 100, 128 << 16 + sin(5460 + framecount << 5) * 100, 90 << 16 + sin(7508 + framecount << 5) * 100, $FFFF)
  gl.text_centered (render#WIDTH >> 1, 192 + (sin(framecount << 6) ~> 12), 0, 2, string(" WOOO! SPINNING TRIANGLES!"), font.get, $FFFF)


PRI sin(angle) : s
{{Hub ROM sine. 0 to 8191 is one turn. Result is -65535 to 65535.}}

  s := angle
  if angle & $800
    s := -s
  s |= $E000 >> 1
  s <<= 1
  s := word[s]
  if angle & $1000
    s := -s


PRI vblank

  repeat while vga_status & $01_00_00
  repeat until vga_status & $01_00_00


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
