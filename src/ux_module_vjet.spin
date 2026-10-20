''***************************************
''*  User Experience Module             *
''*  Designed for RC2014                *
''*  Based on ux_module.spin            *
''*  Author: Phillip Stevens            *
''*  Copyright (c) 2021                 *
''*  Bring-up: feilipu                  *
''*  Copyright (c) 2026                 *
''*  See end of file for licence        *
''***************************************
''
'' Stage 1 bring-up top. Boot is the text console.
'' Graphics keeps the input that requested it and stops the other input.
'' Eight line slots. Three render cogs. The picture is scene/scene_triangles.spin.
'' A streamed list replaces that picture. Cog 0 copies it from the ACIA ring.
'' The triangles spin. Cog 0 keeps the ACIA pump. The draw cog has its own stack.
'' Compile this file with -u so the copier fits. Keep the font.get call below.
'' openspin -u -L src -L src/lib_vjet -b -o build/ux_module_vjet.binary src/ux_module_vjet.spin
'' Product upload remains src/ux_module.spin.

CON

  _clkmode      = XTAL1 + PLL16X
  _xinfreq      = 7_372_800

  DLIST_SIZE    = 296                                   ' longs in each list
  _STACK        = 256                                   ' Cog 0 stack, in longs. Cog 0 does not draw.


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
  PARSE_LIST_LO   = 8                                   ' list count, low byte
  PARSE_LIST_HI   = 9                                   ' list count, high byte
  PARSE_LIST      = 10                                  ' list payload bytes
  PARSE_LIST_ARM  = 11                                  ' wait until the draw cog leaves gl.start

  LIST_MARK       = $1C                                 ' list lead-in. Trial only. Not an XMODEM byte.

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
  byte  gfxArm                                          ' GFX_ARM_FTDI or GFX_ARM_KBD while gfxMode is 1
  byte  gfxBellHold                                     ' 1: eat repeated Control-G until RX is idle
  byte  gfxChordArm                                     ' 1: Ctrl+Alt+G is a new press
  byte  gfxNeedDdc                                      ' 1: start DDC after P5 is released
  byte  ftdiUp                                          ' 1: FTDI cog is running. readZ80 may call term.tx
  long  gfxReady                                        ' render cogs rdbyte this. Must be long-aligned.
  long  drawCog                                         ' cognew id + 1, or 0
  long  framecount
  long  vga_status                                      ' VECTORJET VGA phase. VGA cog writes it.
  long  dlist_ptr                                       ' Draw cog writes it. Render cogs read it.
  long  dlist1[DLIST_SIZE]                              ' list A
  long  dlist2[DLIST_SIZE]                              ' list B
  byte  listFill                                        ' 0 fills dlist1. 1 fills dlist2.
  byte  listReady                                       ' 1: the fill target is complete
  byte  listShown                                       ' 1: a streamed list is on screen
  byte  drawHold                                        ' 1: the draw cog will not call gl.start
  long  listCount                                       ' payload bytes still to store
  long  listAt                                          ' next Hub byte in the fill target
  long  linebuffers[(render#WIDTH * render#LINE_BUFFERS) / 4]
  long  polyXY[20]                                      ' polygon vertices, x then y, 16.16
  long  drawStack[192]                                  ' Draw cog stack. The next Hub is the FTDI rings.


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

  WIDTH         = render#WIDTH
  HEIGHT        = render#NUM_LINES

  GFX_ARM_FTDI = 1                                      ' Control-G entered graphics. FTDI cog stays.
  GFX_ARM_KBD  = 2                                      ' PS/2 chord entered graphics. Keyboard cog stays.

  gfxChord = kbd#KBD_ASCII_CTRL | kbd#KBD_ASCII_ALT | kbd#KBD_ASCII_G


PUB main | busHeld

  'start the serial terminal, then the text VGA before slower boot work
  ftdiUp := term.start (115200)
  screenInit
  term.str (string("UX Module Initialised"))
  term.newLine
  keepFont                                              ' openspin -u must keep hexfont

  ' Hold the 8085 while DDC and the keyboard take their cogs.
  ' pulseZ80Reset starts the ACIA cog after those.
  ' Graphics stops text VGA, DDC, and the input that did not request it.
  ' The request input stays. It is the only return path.
  holdZ80Reset
  startDdc
  kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)
  gfxChordArm := 1
  pulseZ80Reset
  acia.setGfxFlag (0)                                   ' flag stays clear. Control-G does not set it.
  keepGfx

  ' MAIN COG EVENT LOOP — one writer for acia.tx (no extra pump cog).
  ' Skip the keyboard while Z80→host or host→Z80 XMODEM is in progress.
  ' Backplane /RESET holds P5 low through D1/C12. Do not drive P5. Wipe once.
  repeat
    busHeld := pollBusReset
    if gfxNeedDdc and not busHeld
      i2c.startCog
      gfxNeedDdc := 0
    if acia.takeParseIdle                               ' Z80 CR_RESET: abandon ESC/CSI/XMODEM/list
      z80Parse := PARSE_IDLE                            ' a sealed list stays in listReady
      z80XmSess := 0
      hostXm := HOST_XM_OFF
    if not busHeld
      if gfxMode
        if gfxArm == GFX_ARM_KBD
          kbdToZ80
        else
          termToZ80
        readZ80
      elseif inXmodem or hostXmodem
        repeat while kbd.peekKey == gfxChord
          kbd.getKey
        termToZ80
        readZ80
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
      hostTx (" ")
      wmf.outScreen (" ")
      term.dec (i2c.hPix)
      wmf.decScreen (i2c.hPix, 4)
      hostTx ("x")
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
  A list mark stays in the ring while listReady is set.
  TDRE is allowed only when the next byte fits in FTDI TX.}}

    if z80Parse == PARSE_LIST_ARM and ((not gfxMode) or drawHold)
      claimList
      z80Parse := PARSE_LIST

    n := 0
    repeat while acia.rxCount > 0 and n < PUMP_LIMIT
      if z80Parse == PARSE_LIST_ARM
        quit
      char := acia.rxPeek
      if listReady and z80Parse == PARSE_IDLE and char == LIST_MARK
        quit
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
    elseif (not ftdiUp) or term.txCheck
      acia.tdreAllow
    else
      acia.tdreHold


PRI ftdiNeed(char) : n
{{FTDI TX slots takeZ80Byte will use for this ACIA byte in the current PARSE_* state.
  Zero while the FTDI cog is stopped, so the Z80 drain does not wait on term.tx.
  Zero from the list count onward, so the payload does not wait on term.tx.}}

  if (not ftdiUp) or (z80Parse => PARSE_LIST_LO)
    return 0
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


PRI hostTx(c)
{{One FTDI byte when that cog is running. A stopped cog must not fill the ring.}}

  if ftdiUp
    term.tx (c)


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
      hostTx (char)
      if ( char == ASCII_LB )                           ' CSI Control Sequence Introducer
        z80N := 0
        z80Parse := PARSE_CSI
      else
        echoPrintable (char)                            ' printable non-CSI after ESC
        z80Parse := PARSE_IDLE

    PARSE_CSI:                                          ' ESC [ n ...
      hostTx (char)
      if ( char => "0" AND char =< "9" )
        z80N := z80N*10 + char - ASCII_0
      elseif ( char == ASCII_SEMI )
        z80M := 0
        z80Parse := PARSE_CSI_M
      else
        applyCsi (char)
        z80Parse := PARSE_IDLE

    PARSE_CSI_M:                                        ' ESC [ n ; m ...
      hostTx (char)
      if ( char => "0" AND char =< "9" )
        z80M := z80M*10 + char - ASCII_0
      else
        if ( char == "H" )                              ' cursor to row n, column m
          applyCsiH
        z80Parse := PARSE_IDLE

    PARSE_XMODEM_N:                                     ' packet number
      hostTx (char)
      z80N := char
      z80Parse := PARSE_XMODEM_M

    PARSE_XMODEM_M:                                     ' complemented packet number
      hostTx (char)
      z80M := char
      if ( z80N == $FF - z80M )
        z80Remain := z80XmLen                           ' 128 or 1024 data; trailers follow
        z80Parse := PARSE_XMODEM
      else
        z80XmSess := 0                                  ' bad header; do not keep the keyboard muted
        z80Parse := PARSE_IDLE                          ' n/~n already on FTDI, no payload yet

    PARSE_XMODEM:                                       ' payload to FTDI only (not VGA)
      hostTx (char)
      z80Remain := z80Remain - 1
      if ( z80Remain == 0 )
        z80Parse := PARSE_XMODEM_CS

    PARSE_XMODEM_CS:                                    ' checksum or CRC bytes; never delimiters
      hostTx (char)
      z80XmTrail := z80XmTrail - 1
      if ( z80XmTrail == 0 )
        z80Parse := PARSE_IDLE

    PARSE_LIST_LO:                                      ' count low byte. Do not echo.
      listCount := char
      z80Parse := PARSE_LIST_HI

    PARSE_LIST_HI:                                      ' count high byte. Do not echo.
      listCount := listCount | (char << 8)
      if (listCount == 0) or (listCount > constant(DLIST_SIZE * 4))
        z80Parse := PARSE_IDLE                          ' reject. Leave listReady as it is.
      elseif (not gfxMode) or drawHold
        claimList
        z80Parse := PARSE_LIST
      else
        z80Parse := PARSE_LIST_ARM

    PARSE_LIST:                                         ' payload. Do not echo.
      byte[listAt] := char
      listAt++
      listCount--
      if listCount == 0
        listReady := 1
        z80Parse := PARSE_IDLE

    other:                                              ' PARSE_IDLE
      takeZ80Idle (char)


PRI takeZ80Idle(char)
{{Idle-state byte: XMODEM SOH, edits, CR, ESC, or printable.}}

  case char

    XMODEM_SOH:                                         ' XMODEM-128 Start of Header
      hostTx (char)
      z80XmLen := 128
      if z80XmCrc
        z80XmTrail := 2
      else
        z80XmTrail := 1
      z80XmSess := 1
      z80Parse := PARSE_XMODEM_N

    XMODEM_STX:                                         ' XMODEM-1K Start of Header (CRC-16)
      hostTx (char)
      z80XmLen := 1024
      z80XmCrc := 1
      z80XmTrail := 2
      z80XmSess := 1
      z80Parse := PARSE_XMODEM_N

    XMODEM_EOT, XMODEM_ETB, XMODEM_CAN:
      hostTx (char)
      z80XmSess := 0

    LIST_MARK:                                          ' list lead-in. SOH and STX are above.
      if inXmodem or hostXmodem
        hostTx (char)
        echoPrintable (char)
      elseif not listReady
        z80Parse := PARSE_LIST_LO

    ASCII_BS, ASCII_DEL:                                ' backspace (edit), delete
      if wmf.getColScreen > 0
        hostTx (ASCII_BS)
        hostTx (ASCII_SPACE)
        hostTx (ASCII_BS)
        textOut (wmf#BS)
        textOut (wmf#ASCII_SPACE)
        textOut (wmf#BS)
      syncCurs

    ASCII_TAB:                                          ' horizontal tab; WMF owns glyph cursor
      hostTx (char)
      wmf.outScreen (wmf#TB)
      syncCurs

    ASCII_LF:                                           ' eat linefeed from Z80 (CP/M CR+LF)

    ASCII_CR:                                           ' carriage return
      if ftdiUp
        term.newLine                                    ' CR+LF for PST / typical hosts
      textOut (wmf#NL)
      syncCurs

    ASCII_ESC:                                          ' escape; next byte decides CSI vs literal
      hostTx (char)
      z80Parse := PARSE_ESC

    other:                                              ' all other cases
      hostTx (char)
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
            enterGraphics (GFX_ARM_KBD)
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
  Host packet machine: EOT/ETB/CAN end the session only in OFF or GAP.
  A Control-G that enters or leaves graphics eats repeats until RX is idle.}}

  if gfxBellHold and term.rxCount == 0
    gfxBellHold := 0
    return
  n := 0
  repeat while term.rxCount > 0 and acia.txCheck and n < PUMP_LIMIT
    b := term.rx
    if b == ASCII_BELL and not inXmodem and not hostXmodem
      n++
      if gfxBellHold
        next
      if gfxMode
        leaveGraphics
      else
        enterGraphics (GFX_ARM_FTDI)
      gfxBellHold := 1
      next
    gfxBellHold := 0
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

  if ftdiUp
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
    reviveInput
    gfxMode := 0
    gfxArm := 0
    gfxNeedDdc := 1
  discardHostInputs
  acia.start (PORT_DEFAULT)                             ' stop + cognew; last_rdr := 0
  waitcnt (clkfreq / 1000 + cnt)                        ' ACIA cog before 8085 runs
  acia.tdreHold                                         ' keep TDR closed until readZ80 sees FTDI room
  z80Parse := PARSE_IDLE                                ' a sealed list stays in listReady
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
  if ftdiUp and term.txSpace => 4                       ' ESC [ 2 J
    term.clear
  releaseZ80Reset                                       ' release Z80 after local state is quiet


PRI enterGraphics(arm)
{{Stop text VGA, DDC, and the input cog that did not request graphics.
  arm is GFX_ARM_FTDI or GFX_ARM_KBD. That input stays and is the return path.
  Graphics uses all eight cogs. Cog 0 returns to the ACIA pump.}}

  if gfxMode or inXmodem or hostXmodem
    return
  gfxArm := arm
  gfxMode := 1
  wmf.stop
  i2c.stopCog
  if arm == GFX_ARM_FTDI
    kbd.stop
  else
    ftdiUp := 0
    term.stop
  waitcnt (clkfreq / 4 + cnt)                           ' 250 ms blank
  if not startVectorjet
    restoreText
    if ftdiUp and term.txSpace => 24
      term.str (string("Graphics start failed"))
      term.newLine


PRI leaveGraphics
{{Stop VECTORJET and restore the text console.}}

  if gfxMode
    restoreText


PRI reviveInput
{{Start the input cog that graphics stopped. The request cog stays as it is.}}

  if gfxArm == GFX_ARM_KBD
    if term.startRxTx (31, 30, 0, 115200)              ' no boot delay. The host is already open.
      ftdiUp := 1
  else
    term.healRings
    kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)
    gfxChordArm := 1


PRI restoreText
{{Text VGA, the stopped input cog, one FTDI line, then DDC.
  P5 must already be released. The VGA banner does not go to FTDI.
  Wait after VECTORJET stops so the pins and the PLL are free.}}

  stopVectorjet
  waitcnt (clkfreq / 4 + cnt)                           ' 250 ms blank, same as enter
  screenInit
  reviveInput
  if ftdiUp and term.txSpace => 12
    term.str (string("Text mode"))
    term.newLine
  i2c.startCog
  gfxMode := 0
  gfxArm := 0
  gfxNeedDdc := 0


PRI stopVectorjet
{{Stop the draw cog, the render cogs, and the slice VGA cog.
  Do this before screenInit. Float P16–P23 after those cogs stop.}}

  gfxReady := 0
  drawHold := 0
  listShown := 0                                        ' the next entry can show the triangles
  if drawCog
    cogstop (drawCog~ - 1)
  render.stop
  vga.stop
  dira[23..16]~                                         ' float the VGA pins



PRI startVectorjet : ok
{{Start the slice VGA cog and three render cogs.
  Keep a list that is ready or still filling.
  The draw cog publishes on the front porch.
  gfxReady is a long. On failure, stop every cog this call started.}}

  gfxReady := 0
  framecount := 0
  vga_status := 0
  if listReady or (z80Parse => PARSE_LIST_LO)
    drawHold := 1
    if listFill
      longfill (@dlist1, 0, DLIST_SIZE)
      dlist_ptr := @dlist1
    else
      longfill (@dlist2, 0, DLIST_SIZE)
      dlist_ptr := @dlist2
  else
    drawHold := 0
    longfill (@dlist1, 0, DLIST_SIZE)
    longfill (@dlist2, 0, DLIST_SIZE)
    dlist_ptr := @dlist2
  longfill (@linebuffers, 0, (render#WIDTH * render#LINE_BUFFERS) / 4)
  if not vga.start (VGA_BASE_PIN / 8, @linebuffers, @vga_status)
    return 0
  if not render.start (0, 3, @linebuffers, @dlist_ptr, @vga_status, @gfxReady)
    vga.stop
    return 0
  if not render.start (1, 3, @linebuffers, @dlist_ptr, @vga_status, @gfxReady)
    render.stop
    vga.stop
    return 0
  if not render.start (2, 3, @linebuffers, @dlist_ptr, @vga_status, @gfxReady)
    render.stop
    vga.stop
    return 0
  drawCog := cognew (drawLoop, @drawStack) + 1
  if not drawCog
    render.stop
    vga.stop
    return 0
  gfxReady := 1
  return 1


PRI drawLoop
{{Publish a streamed list on the front porch.
  Otherwise hold that picture, or build the spinning triangles.
  Stack is drawStack. Text VGA is stopped.}}

  repeat
    vblank
    if listReady
      if listFill
        dlist_ptr := @dlist2
      else
        dlist_ptr := @dlist1
      listFill := 1 - listFill
      listReady := 0
      listShown := 1
      drawHold := 1
    elseif listShown or (z80Parse => PARSE_LIST_LO)
      drawHold := 1
    else
      drawHold := 0
      if framecount & 1
        dlist_ptr := @dlist1
        gl.start (@dlist2, constant(DLIST_SIZE * 4))
      else
        dlist_ptr := @dlist2
        gl.start (@dlist1, constant(DLIST_SIZE * 4))
      \drawScene
      gl.done
      framecount++


PRI keepFont | p
{{Call the font so openspin -u keeps hexfont in the image.}}

  p := font.get


PRI keepGfx | n
{{Keep the graphics flag methods in an openspin -u image. Do not set the flag.}}

  n := acia.gfxFlag
  n := acia.gfxCommand


PRI claimList
{{Clear the list that dlist_ptr does not name. Cog 0 then stores the payload there.}}

  if dlist_ptr == @dlist1
    listFill := 1
    listAt := @dlist2
  elseif dlist_ptr == @dlist2
    listFill := 0
    listAt := @dlist1
  elseif listFill
    listAt := @dlist2
  else
    listAt := @dlist1
  longfill (listAt, 0, DLIST_SIZE)


PRI vblank
{{Wait until bit 16 rises. That edge is the front porch.}}

  repeat while vga_status & $01_00_00
  repeat until vga_status & $01_00_00


PRI drawScene
{{Build the spinning triangles. The draw cog calls this while graphics is on.}}

  draw


#include "scene/scene_triangles.spin"
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
