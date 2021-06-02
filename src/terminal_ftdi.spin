{{
File: Parallax Serial Terminal.spin
Version: 1.0
Copyright (c) 2009 Parallax, Inc.
See end of file for terms of use.

Authors: Jeff Martin, Andy Lindsay, Chip Gracey
}}

{
HISTORY:
  This object is made for direct use with the Parallax Serial Terminal; a simple serial communication program
  available with the Propeller Tool installer and also separately via the Parallax website (www.parallax.com).

  This object is heavily based on FullDuplexSerialPlus (by Andy Lindsay), which is itself heavily based on
  FullDuplexSerial (by Chip Gracey).

USAGE:
   Call start, or startRxTx, first.

}

CON

   BUFFER_LENGTH    = 512                               'Recommended as 64 or higher, but can be 2, 4, 8, 16, 32, 64, 128, 256 or 512.
   BUFFER_MASK      = BUFFER_LENGTH - 1
   BUFFER_FULLISH   = BUFFER_LENGTH / 2
   BUFFER_EMPTYISH  = BUFFER_LENGTH / 8

   MAXSTR_LENGTH    = 255                               'Maximum length of received numerical string (not including zero terminator).

   XOFF = 19                                            ' XOFF
   XON  = 17                                            ' XON
   NL   = 13                                            ' NL: New Line
   LF   = 10                                            ' LF: Line Feed


VAR

  long  cog                                             'Cog flag/id

  long  status_xoff                                     'Status of XOFF in XON/XOFF transmission

  long  rx_head                                         '9 contiguous longs (must keep order)
  long  rx_tail
  long  tx_head
  long  tx_tail
  long  rx_pin
  long  tx_pin
  long  rxtx_mode
  long  bit_ticks
  long  buffer_ptr

  byte  rx_buffer[BUFFER_LENGTH]                        'Receive and transmit buffers
  byte  tx_buffer[BUFFER_LENGTH]

  byte  str_buffer[MAXSTR_LENGTH+1]                     'String buffer for numerical strings


PUB start(baudrate) : okay
{{Start communication with the Parallax Serial Terminal using the Propeller's programming connection.
Waits 1/4 second for connection, then clears screen.
  Parameters:
    baudrate - bits per second.  Make sure it matches the Parallax Serial Terminal's
               Baud Rate field.
  Returns    : True (non-zero) if cog started, or False (0) if no cog is available.}}

  okay := startRxTx(31, 30, 0, baudrate)
  waitcnt(clkfreq >> 2 + cnt)                           'Wait 1/4 second for PST


PUB startRxTx(rxpin, txpin, mode, baudrate) : okay
{{Start serial communication with designated pins, mode, and baud.
  Parameters:
    rxpin    - input pin; receives signals from external device's TX pin.
    txpin    - output pin; sends signals to  external device's RX pin.
    mode     - signaling mode (4-bit pattern).
               bit 0 - inverts rx.
               bit 1 - inverts tx.
               bit 2 - open drain/source tx.
               bit 3 - ignore tx echo on rx.
    baudrate - bits per second.
  Returns    : True (non-zero) if cog started, or False (0) if no cog is available.}}

  stop
  longfill(@rx_head, 0, 4)
  longmove(@rx_pin, @rxpin, 3)
  bit_ticks := clkfreq / baudrate
  buffer_ptr := @rx_buffer
  status_xoff := FALSE
  okay := cog := cognew(@entry, @rx_head) + 1


PUB stop
{{Stop serial communication; frees a cog.}}

  if cog
    cogstop(cog~ - 1)
  longfill(@rx_head, 0, 9)


PUB tx(bytechr)
{{Send single-byte character.  Waits for room in transmit buffer if necessary.
  Parameter:
    bytechr - character (ASCII byte value) to send.}}

  repeat until (tx_tail <> ((tx_head + 1) & BUFFER_MASK))

  tx_buffer[tx_head] := bytechr
  tx_head := ++tx_head & BUFFER_MASK

  if rxtx_mode & %1000
    rx


PUB txn(bytechr, count)
{{Send multiple copies of a single-byte character. Waits for room in transmit buffer if necessary.
  Parameters:
    bytechr - character (ASCII byte value) to send.
    count   - number of bytechrs to send.}}

  repeat count
    tx(bytechr)


PUB txCheck : truefalse
{{Check and return true if space in transmit buffer; return immediately.
  Returns: t|f}}

  truefalse := tx_tail <> ((tx_head + 1) & BUFFER_MASK )


PUB rx : rxbyte
{{Receive single-byte character.  Waits until character received.
  Returns: $00..$FF}}

  repeat until rxCount > 0

  rxbyte := rx_buffer[rx_tail]
  rx_tail := ++rx_tail & BUFFER_MASK


PUB rxCount : count
{{Get count of characters in receive buffer. Manages XON/XOFF flow control.
  Returns: number of characters waiting in receive buffer.}}

  count := rx_head - rx_tail
  count -= BUFFER_LENGTH * (count < 0)

  if count =< BUFFER_EMPTYISH and status_xoff == TRUE
    status_xoff := FALSE
    tx(XON)

  elseif count => BUFFER_FULLISH and status_xoff == FALSE 
    status_xoff := TRUE
    tx(XOFF)


PUB rxFlush
{{Flush receive buffer.}}

  rx_tail := rx_head := 0


PUB rxCheck : truefalse
{Check if character received; return immediately.
  Returns: t|f}

  truefalse := rx_tail <> rx_head


CON

  ' Terminal Control


PUB clear
{{Clear screen and place cursor at top-left.}}

    str(string(27,"[2J"))


PUB clearEnd
{{Clear line from cursor to end of line.}}

    str(string(27,"[0K"))

PUB clearBelow
{{Clear all lines below cursor.}}

    str(string(27,"[J"))


PUB home
{{Send cursor to home position (top-left).}}

    str(string(27,"[H"))


PUB position(x, y)
{{Position cursor at column x, row y (from top-left).}}
    str(string(27,"[")) ' Position Cursor
    dec(y)
    tx(";")
    dec(x)
    tx("H")


PUB saveCurPos
    str(string(27,"7"))


PUB restoreCurPos
    str(string(27,"8"))


PUB hideCursor

    str(string(27,"[?25l")) ' Hide Cursor


PUB showCursor
    str(string(27,"[?25h")) ' Show Cursor


PUB newLine
{{Send cursor to new line (carriage return plus line feed).}}

  tx(NL)
  tx(LF)


PUB lineFeed
{{Send cursor down to next line.}}

  tx(LF)


CON

  ' String Handling


PUB str(stringptr)
{{Send zero terminated string.
  Parameter:
    stringptr - pointer to zero terminated string to send.}}

  repeat strsize(stringptr)
    tx(byte[stringptr++])


PUB strIn(stringptr)
{{Receive a string (carriage return terminated) and stores it (zero terminated) starting at stringptr.
Waits until full string received.
  Parameter:
    stringptr - pointer to memory in which to store received string characters.
                Memory reserved must be large enough for all string characters plus a zero terminator.}}

  strInMax(stringptr, -1)


PUB strInMax(stringptr, maxcount)
{{Receive a string of characters (either carriage return terminated or maxcount in length) and stores it (zero terminated)
starting at stringptr.  Waits until either full string received or maxcount characters received.
  Parameters:
    stringptr - pointer to memory in which to store received string characters.
                Memory reserved must be large enough for all string characters plus a zero terminator (maxcount + 1).
    maxcount  - maximum length of string to receive, or -1 for unlimited.}}

  repeat while (maxcount--)                                                     'While maxcount not reached
    if (byte[stringptr++] := rx) == NL                                          'Get chars until NL
      quit
  byte[stringptr+(byte[stringptr-1] == NL)]~                                    'Zero terminate string; overwrite NL or append 0 char



CON

  ' Numeric and Alternate Base Handling


PUB dec(value) | i, x
{{Send value as decimal characters.
  Parameter:
    value - byte, word, or long value to send as decimal characters.}}

  x := value == NEGX                                                            'Check for max negative
  if value < 0
    value := ||(value+x)                                                        'If negative, make positive; adjust for max negative
    tx("-")                                                                     'and output sign

  i := 1_000_000_000                                                            'Initialize divisor

  repeat 10                                                                     'Loop for 10 digits
    if value => i
      tx(value / i + "0" + x*(i == 1))                                          'If non-zero digit, output digit; adjust for max negative
      value //= i                                                               'and digit from value
      result~~                                                                  'flag non-zero found
    elseif result or i == 1
      tx("0")                                                                   'If zero digit (or only digit) output it
    i /= 10                                                                     'Update divisor


PUB decIn : value
{{Receive carriage return terminated string of characters representing a decimal value.
  Returns: the corresponding decimal value.}}

  strInMax(@str_buffer, MAXSTR_LENGTH)
  value := strToBase(@str_buffer, 10)


PUB bin(value, digits)
{{Send value as binary characters up to digits in length.
  Parameters:
    value  - byte, word, or long value to send as binary characters.
    digits - number of binary digits to send.  Will be zero padded if necessary.}}

  value <<= 32 - digits
  repeat digits
    tx((value <-= 1) & 1 + "0")


PUB binIn : value
{{Receive carriage return terminated string of characters representing a binary value.
 Returns: the corresponding binary value.}}

  strInMax(@str_buffer, MAXSTR_LENGTH)
  value := strToBase(@str_buffer, 2)


PUB hex(value, digits)
{{Send value as hexadecimal characters up to digits in length.
  Parameters:
    value  - byte, word, or long value to send as hexadecimal characters.
    digits - number of hexadecimal digits to send.  Will be zero padded if necessary.}}

  value <<= (8 - digits) << 2
  repeat digits
    tx(lookupz((value <-= 4) & $F : "0".."9", "A".."F"))


PUB hexIn : value
{{Receive carriage return terminated string of characters representing a hexadecimal value.
  Returns: the corresponding hexadecimal value.}}

  strInMax(@str_buffer, MAXSTR_LENGTH)
  value := strToBase(@str_buffer, 16)


PRI strToBase(stringptr, base) : value | chr, index
{Converts a zero terminated string representation of a number to a value in the designated base.
Ignores all non-digit characters (except negative (-) when base is decimal (10)).}

  value := index := 0
  repeat until ((chr := byte[stringptr][index++]) == 0)
    chr := -15 + --chr & %11011111 + 39*(chr > 56)                              'Make "0"-"9","A"-"F","a"-"f" be 0 - 15, others out of range
    if (chr > -1) and (chr < base)                                              'Accumulate valid values into result; ignore others
      value := value * base + chr
  if (base == 10) and (byte[stringptr] == "-")                                  'If decimal, address negative sign; ignore otherwise
    value := - value


DAT

'***********************************
'* Assembly language serial driver *
'***********************************

                        org
'
'
' Entry
'
entry                   mov     t1,par                'get structure address
                        add     t1,#4 << 2            'skip past heads and tails

                        rdlong  t2,t1                 'get rx_pin
                        mov     rxmask,#1
                        shl     rxmask,t2

                        add     t1,#4                 'get tx_pin
                        rdlong  t2,t1
                        mov     txmask,#1
                        shl     txmask,t2

                        add     t1,#4                 'get rxtx_mode
                        rdlong  rxtxmode,t1

                        add     t1,#4                 'get bit_ticks
                        rdlong  bitticks,t1

                        add     t1,#4                 'get buffer_ptr
                        rdlong  rxbuff,t1
                        mov     txbuff,rxbuff
                        add     txbuff,#BUFFER_MASK   ' transmit buffer address BUFFER_LENGTH
                        add     txbuff,#1             ' BUFFER_LENGTH := BUFFER_MASK + 1

                        test    rxtxmode,#%100  wz    'init tx pin according to mode
                        test    rxtxmode,#%010  wc
        if_z_ne_c       or      outa,txmask
        if_z            or      dira,txmask

                        mov     txcode,#transmit      'initialize ping-pong multitasking
'
'
' Receive
'
receive                 jmpret  rxcode,txcode         'run a chunk of transmit code, then return

                        test    rxtxmode,#%001  wz    'wait for start bit on rx pin
                        test    rxmask,ina      wc
        if_z_eq_c       jmp     #receive

                        mov     rxbits,#9             'ready to receive byte
                        mov     rxcnt,bitticks
                        shr     rxcnt,#1
                        add     rxcnt,cnt

:bit                    add     rxcnt,bitticks        'ready next bit period

:wait                   jmpret  rxcode,txcode         'run a chuck of transmit code, then return

                        mov     t1,rxcnt              'check if bit receive period done
                        sub     t1,cnt
                        cmps    t1,#0           wc
        if_nc           jmp     #:wait

                        test    rxmask,ina      wc    'receive bit on rx pin
                        rcr     rxdata,#1
                        djnz    rxbits,#:bit

                        shr     rxdata,#32-9          'justify and trim received byte
                        and     rxdata,#$FF
                        test    rxtxmode,#%001  wz    'if rx inverted, invert byte
        if_nz           xor     rxdata,#$FF

                        rdlong  t2,par                'save received byte and inc head
                        add     t2,rxbuff
                        wrbyte  rxdata,t2
                        sub     t2,rxbuff
                        add     t2,#1
                        and     t2,#BUFFER_MASK
                        wrlong  t2,par

                        jmp     #receive              'byte done, receive next byte
'
'
' Transmit
'
transmit                jmpret  txcode,rxcode         'run a chunk of receive code, then return

                        mov     t1,par                'check for head <> tail
                        add     t1,#2 << 2
                        rdlong  t2,t1
                        add     t1,#1 << 2
                        rdlong  t3,t1
                        cmp     t2,t3           wz
        if_z            jmp     #transmit

                        add     t3,txbuff             'get byte and inc tail
                        rdbyte  txdata,t3
                        sub     t3,txbuff
                        add     t3,#1
                        and     t3,#BUFFER_MASK
                        wrlong  t3,t1

                        or      txdata,#$100          'ready byte to transmit
                        shl     txdata,#2
                        or      txdata,#1
                        mov     txbits,#11
                        mov     txcnt,cnt

:bit                    test    rxtxmode,#%100  wz    'output bit on tx pin
                        test    rxtxmode,#%010  wc    'according to mode
        if_z_and_c      xor     txdata,#1
                        shr     txdata,#1       wc
        if_z            muxc    outa,txmask
        if_nz           muxnc   dira,txmask
                        add     txcnt,bitticks        'ready next cnt

:wait                   jmpret  txcode,rxcode         'run a chunk of receive code, then return

                        mov     t1,txcnt              'check if bit transmit period done
                        sub     t1,cnt
                        cmps    t1,#0           wc
        if_nc           jmp     #:wait

                        djnz    txbits,#:bit          'another bit to transmit?

                        jmp     #transmit             'byte done, transmit next byte
'
'
' Uninitialized data
'
t1                      res     1
t2                      res     1
t3                      res     1

rxtxmode                res     1
bitticks                res     1

rxmask                  res     1
rxbuff                  res     1
rxdata                  res     1
rxbits                  res     1
rxcnt                   res     1
rxcode                  res     1

txmask                  res     1
txbuff                  res     1
txdata                  res     1
txbits                  res     1
txcnt                   res     1
txcode                  res     1

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
