''
'' UX Module RC2014 Bus Interface
''
'' ACIA emulation
''
'' Copyright (c) 2021 Phillip Stevens
''
'' I/O Address line mapping (Production):
''
''             P7  P6  P5  P4  P3  P2  P1  P0
''             x   x   1   1   x   1   x   x
''             |   |   |   |   |   |   |   |
''             |   |   |   |   |   |   |   |
''      /RD ---+   |   |   |   |   |   |   |
''      /WR -------+   |   |   |   |   |   |
''      /RESET --------+   |   |   |   |   |
''      /M1 ---------------+   |   |   |   |
''      A0 --------------------+   |   |   |
''      !(/IORQ|A5|A4|A3|A2|A1) ---+   |   |
''      A6 ----------------------------+   |
''      A7 --------------------------------+
''
''
'' I/O Data line mapping:
''
''             P15 P14 P13 P12 P11 P10 P9  P8
''             x   x   x   x   x   x   x   x
''             |   |   |   |   |   |   |   |
''             |   |   |   |   |   |   |   |
''      D7 ----+   |   |   |   |   |   |   |
''      D6 --------+   |   |   |   |   |   |
''      D5 ------------+   |   |   |   |   |
''      D4 ----------------+   |   |   |   |
''      D3 --------------------+   |   |   |
''      D2 ------------------------+   |   |
''      D1 ----------------------------+   |
''      D0 --------------------------------+
''
''
'' I/O Signal line mapping:
''
''             P25 P24
''             x   x
''             |   |
''             |   |
''      INT ---+   |
''      WAIT ------+
''

CON

  DATA_BASE   =   8                   'DATA bus is Pin P8 to Pin P15
  DATA_PINS   =   %1111_1111          '8 bit data bus

  INT_PIN_NUM   = 25                  'Pins used for output - open collector - behind diodes
  WAIT_PIN_NUM  = 24
  RESET_PIN_NUM = 5

  INT_PIN     =   |< INT_PIN_NUM
  WAIT_PIN    =   |< WAIT_PIN_NUM

  RD_PIN      =   |< 7
  WR_PIN      =   |< 6
  RESET_PIN   =   |< RESET_PIN_NUM
  M1_PIN      =   |< 4

  A0_PIN      =   |< 3
  A5_A1_PINS  =   |< 2                'NOR Gated, so will be logic high for Addr Pins 0 including /IORQ
  A6_PIN      =   |< 1
  A7_PIN      =   |< 0

  BUFFER_LENGTH   = 512               'Recommended as 64 or higher, but can be 2, 4, 8, 16, 32, 64, 128, 256 or 512.
  BUFFER_MASK     = BUFFER_LENGTH - 1
  IRQ_POLL        = 32                ' idle INA polls between /INT Hub refresh (9-bit immediate)

CON

  PORT_00     =   A5_A1_PINS
  PORT_01     =   A5_A1_PINS | A0_PIN

  PORT_40     =   A6_PIN | A5_A1_PINS
  PORT_41     =   A6_PIN | A5_A1_PINS | A0_PIN

  PORT_80     =   A7_PIN | A5_A1_PINS
  PORT_81     =   A7_PIN | A5_A1_PINS | A0_PIN

  PORT_C0     =   A7_PIN | A6_PIN | A5_A1_PINS
  PORT_C1     =   A7_PIN | A6_PIN | A5_A1_PINS | A0_PIN

  PORT_MASK   =   A7_PIN | A6_PIN | A5_A1_PINS

  ' ACIA Control Register

  CR_RIE      = |< 7                ' Receiving Interrupt Enabled (Z80 view)

  CR_TIX_MASK = |< 6 | |< 5         ' Mask just the Tx Interrupt relevant bits (CR6,CR5)

  CR_TID_BRK  = |< 6 | |< 5         ' _RTS low,  Transmitting Interrupt Disabled, BRK on Tx
  CR_TID_RTS1 = |< 6                ' _RTS high, Transmitting Interrupt Disabled
  CR_TIE_RTS0 = |< 5                ' _RTS low,  Transmitting Interrupt Enabled
  CR_TID_RTS0 = 0                   ' _RTS low,  Transmitting Interrupt Disabled

  CR_8O1      = |< 4 | |< 3 | |< 2  ' 8 Bits  Odd Parity 1 Stop Bit
  CR_8E1      = |< 4 | |< 3         ' 8 Bits Even Parity 1 Stop Bit
  CR_8N1      = |< 4 | |< 2         ' 8 Bits   No Parity 1 Stop Bit
  CR_8N2      = |< 4                ' 8 Bits   No Parity 2 Stop Bits
  CR_7O1      = |< 3 | |< 2         ' 7 Bits  Odd Parity 1 Stop Bit
  CR_7E1      = |< 3                ' 7 Bits Even Parity 1 Stop Bit
  CR_7O2      = |< 2                ' 7 Bits  Odd Parity 2 Stop Bits
  CR_7E2      = 0                   ' 7 Bits Even Parity 2 Stop Bits

  CR_RESET    = |< 1 | |< 0         ' Master Reset (issue before any other Control word)
  CR_DIV_64   = |< 1                ' Divide the Clock by 64 (default value)
  CR_DIV_16   = |< 0                ' Divide the Clock by 16
  CR_DIV_01   = 0                   ' Divide the Clock by 1

  ' ACIA Status Register

  SR_IRQ      = |< 7
  SR_PE       = |< 6
  SR_OVRN     = |< 5
  SR_FE       = |< 4
  SR_CTS      = |< 3
  SR_DCD      = |< 2
  SR_TDRE     = |< 1
  SR_RDRF     = |< 0


VAR

  long  cog                         'cog flag/id

                                    '8 contiguous longs (PAR mailbox for the PASM cog)
                                    ' Z80 TDR writes fill rx_*; Z80 RDR reads drain tx_*
  long  rx_head                     '#0   index into rx_buffer (Z80 transmit)
  long  rx_tail                     '#4
  long  tx_head                     '#8   index into tx_buffer (Z80 receive)
  long  tx_tail                     '#12
  long  acia_base                   '#16  ACIA base address (allowing for multiple instances)
  long  acia_config                 '#20  ACIA configuration byte stored shifted by DATA_BASE
  long  acia_status                 '#24  ACIA status byte stored shifted by DATA_BASE
  long  buffer_ptr                  '#28
  byte  rx_buffer[BUFFER_LENGTH]    '#32
  byte  tx_buffer[BUFFER_LENGTH]    '#32 + BUFFER_LENGTH


PUB start(base) : okay
{{Starts RC2014 acia bus driver in a new cog
      okay - returns false if no cog is available.}}

  stop
  longfill(@rx_head, 0, 4)                                ' These are indexes to bytes in the buffer, not pointers
  acia_base := base
  acia_config := constant (( CR_TID_RTS0 | CR_8N1 | CR_DIV_64 ) << DATA_BASE )
  acia_status := constant ( SR_TDRE << DATA_BASE )        ' Initially ready to receive bytes from the Z80
  buffer_ptr := @rx_buffer                                ' Record the origin address of the Rx and Tx buffers
  okay := cog := cognew(@entry,@rx_head) + 1


PUB stop
{{Stops acia driver - frees a cog}}

  if cog
      cogstop(cog~ - 1)
      longfill(@rx_head, 0, 8)


PUB txString( pStringPtr )
{{Print a zero-terminated string to terminal.
 pStrPtr - Pointer to null terminated string to print.}}

  repeat strsize( pStringPtr)
    tx(byte[pStringPtr++])


PUB tx(txbyte)
{{Sends byte. Will wait for room in buffer.
  Sets RDRF when /RTS is low so the Z80 can take the byte. /INT is owned by the PASM cog.}}

  repeat until (tx_tail - tx_head) & BUFFER_MASK <> 1     ' wait until buffer is not full

  tx_buffer[tx_head] := txbyte
  tx_head := ++tx_head & BUFFER_MASK

  if (acia_config & constant(CR_TIX_MASK << DATA_BASE)) <> constant(CR_TID_RTS1 << DATA_BASE)
                                                          ' CR5/CR6 is not /RTS high
    acia_status |= constant(SR_RDRF << DATA_BASE)         ' byte ready for Z80 (RDR)


PUB txFlush
{{Flush transmit buffer and hide RDRF.}}

  tx_tail := tx_head := 0
  acia_status &= !constant(SR_RDRF << DATA_BASE)


PUB txCheck : truefalse
{{Check and return true if space in transmit buffer; return immediately.
  Returns: t|f}}

  truefalse := tx_tail <> ((tx_head + 1) & BUFFER_MASK )


PUB txSpace : count
{{Free slots in the TX FIFO (Z80 RDR). Full is 0. Empty is BUFFER_LENGTH-1.}}

  count := (tx_tail - tx_head - 1) & BUFFER_MASK


PUB rx : rxbyte
{{Receive single-byte character.  Waits until character received.
  Returns: $00..$FF
  Frees a FIFO slot, so TDRE is set (Z80 may write TDR again).}}

  repeat until rxCount > 0

  rxbyte := rx_buffer[rx_tail]
  rx_tail := ++rx_tail & BUFFER_MASK
  acia_status |= constant(SR_TDRE << DATA_BASE)


PUB rxCount : count
{{Get count of characters in receive buffer. No status-bit side effects.
  Returns: number of characters waiting in receive buffer.}}

  count := rx_head - rx_tail
  count -= BUFFER_LENGTH * (count < 0)


PUB rxFlush
{{Flush receive buffer and mark TDR empty.}}

  rx_tail := rx_head := 0
  acia_status |= constant(SR_TDRE << DATA_BASE)
  acia_status &= !constant(SR_OVRN << DATA_BASE)


PUB rxCheck : truefalse
{{Check if character received; return immediately.
  Returns: t|f}}

  truefalse := rx_tail <> rx_head


PUB tdreHold
{{Clear TDRE so the Z80 stops writing TDR. Used when the output path cannot drain.}}

  acia_status &= !constant(SR_TDRE << DATA_BASE)


PUB tdreAllow
{{Set TDRE if the RX FIFO has room. Used when the output path can drain again.}}

  if rxCount < BUFFER_LENGTH - 1
    acia_status |= constant(SR_TDRE << DATA_BASE)


DAT

'****************************************
'* Assembly language ACIA Z80 Emulation *
'****************************************

                        org
'
'
' Entry
'
entry
                        mov     t1,par                  ' get structure address #0

                        add     t1,#16                  ' get acia_base address #16
                        mov     acia_base_addr,t1

                        add     t1,#4                   ' get acia_config address #20
                        mov     acia_config_addr,t1

                        add     t1,#4                   ' get acia_status address #24
                        mov     acia_status_addr,t1

                        add     t1,#4                   ' resolve buffer addresses using buffer_ptr #28
                        rdlong  rxbuff,t1               ' rx_buffer base address is stored there
                        mov     txbuff,rxbuff           ' tx_buffer base address is rx_buffer + BUFFER_LENGTH
                        add     txbuff,#BUFFER_MASK     ' BUFFER_LENGTH := BUFFER_MASK + 1
                        add     txbuff,#1

                        rdlong  t1,acia_base_addr
                        or      t1,#M1_PIN              ' add in the /M1 pin to tighten our addressing to I/O only
                        or      t1,bus_wait             ' add the /WAIT pin to the address for waitpeq wr effect
                        wrlong  t1,acia_base_addr       ' save the tightened addressing for later

                        mov     dira,bus_wait           ' set /WAIT pin to output (all other pins remain as inputs)
                        mov     outa,bus_wait           ' clear /WAIT high by default
                                                        ' it is behind a diode, and the bus is open collector

wait
                        call    #sync_irq               ' hold /INT from Hub RDRF/TDRE and enables
                        rdlong  outa,acia_base_addr     ' configure the base address to compare with ina
                                                        ' including /M1 and /WAIT pin

                        waitpne outa,port_active_mask   ' wait until this cycle has ended
                        mov     pollcnt,#IRQ_POLL
:idle
                        mov     t1,ina                  ' poll so /INT can track Spin RDRF/TDRE while idle
                        xor     t1,outa
                        and     t1,port_active_mask
                        tjz     t1,#matched             ' address match: assert /WAIT via waitpeq wr
                        djnz    pollcnt,#:idle
                        call    #sync_irq               ' Hub RDRF/TDRE may have changed while we waited
                        rdlong  outa,acia_base_addr
                        mov     pollcnt,#IRQ_POLL
                        jmp     #:idle

matched
                        waitpeq outa,port_active_mask wr' wait until we see our addresses (including /IORQ within A5_A1_PINS)
                                                        ' use wr effect to set /WAIT low on match (/INT gets hit as a side effect)

                        andn    outa,bus_int            ' reset /INT pin (modified as a side effect of the waitpeq outa wr effect)

                        testn   bus_a0,ina           wz ' isolate the base address
            if_z        jmp     #handler_data           ' handle data, otherwise fall through for handling command/status at base address

                        testn   bus_rd,ina           wz ' capture port data again, test for /RD pin low
            if_nz       jmp     #transmit_status

                        testn   bus_wr,ina           wz ' capture port data again, test for /WR pin low
            if_nz       jmp     #receive_command

                        jmp     #wait                   ' then go back and wait for next address chance

handler_data
                        testn   bus_rd,ina           wz ' capture port data again, test for /RD pin low
            if_nz       jmp     #transmit_data

                        testn   bus_wr,ina           wz ' capture port data again, test for /WR pin low
            if_nz       jmp     #receive_data

                        jmp     #wait                   ' then go back and wait for next address chance

receive_command
                        or      outa,bus_wait           ' set /WAIT line high to continue
                        mov     bus,ina                 ' capture the command byte (stored shifted by DATA_BASE)
                        waitpeq bus_wr,bus_wr           ' wait for /WR high
                        and     bus,data_active_mask    ' mask received command byte
                        wrlong  bus,acia_config_addr
                        xor     bus,acia_config_reset wz' master reset if we've received the RESET command
            if_nz       jmp     #command_apply

                        mov     t1,par                  ' zero both FIFOs
                        mov     t2,#0
                        wrlong  t2,t1                   ' rx_head
                        add     t1,#4
                        wrlong  t2,t1                   ' rx_tail
                        add     t1,#4
                        wrlong  t2,t1                   ' tx_head
                        add     t1,#4
                        wrlong  t2,t1                   ' tx_tail
                        wrlong  acia_status_initial,acia_status_addr  ' TDRE, RDRF clear
                        jmp     #wait

command_apply                                           ' non-reset control write
                        rdlong  t1,acia_config_addr     ' CR5/CR6 field
                        and     t1,acia_config_tx_mask
                        xor     t1,acia_config_rts1  wz
            if_z        jmp     #clear_rdrf             ' /RTS high: do not present RDR

                        mov     t1,par                  ' /RTS low: RDRF if TX FIFO holds data
                        add     t1,#8
                        rdlong  t2,t1                   ' tx_head
                        add     t1,#4
                        rdlong  t3,t1                   ' tx_tail
                        cmp     t2,t3                wz
            if_e        jmp     #clear_rdrf

                        rdlong  t1,acia_status_addr
                        or      t1,acia_status_rdrf
                        and     t1,data_active_mask
                        wrlong  t1,acia_status_addr
                        jmp     #wait

transmit_status
                        rdlong  t1,acia_config_addr
                        xor     t1,acia_config_reset wz ' RESET command: RomWBW probe wants status 0
            if_z        jmp     #:null
                        call    #sync_irq               ' IRQ bit must follow the pin
                        rdlong  bus,acia_status_addr
                        jmp     #:put
:null
                        mov     bus,#0
:put
                        and     bus,data_active_mask    ' mask transmitted status byte
                        or      outa,bus                ' transmit the status byte (stored shifted by DATA_BASE)
                        or      dira,data_active_mask   ' set data bus lines to active (output)
                        nop                             ' wait for data bus lines to settle before releasing /WAIT
                        nop
                        nop
                        nop
                        or      outa,bus_wait           ' set /WAIT line high to continue
                        waitpeq bus_rd,bus_rd           ' wait for /RD to raise
                        andn    dira,data_active_mask   ' clear data bus lines to inactive (input)
                        andn    outa,data_active_mask   ' ensure data bus pins are cleared to zero
                        jmp     #wait

receive_data                                            ' Z80 write TDR → Propeller rx FIFO
                        mov     t1,par                  ' rx_head
                        rdlong  t2,t1
                        add     t1,#4                   ' rx_tail
                        rdlong  t3,t1

                        or      outa,bus_wait           ' set /WAIT line high to continue
                        mov     bus,ina                 ' capture the data byte
                        waitpeq bus_wr,bus_wr           ' wait for /WR high
                        shr     bus,#DATA_BASE          ' shift data so that the LSB corresponds with D0

                        mov     t1,t2                   ' next head
                        add     t1,#1
                        and     t1,#BUFFER_MASK
                        cmp     t1,t3                wz
            if_e        jmp     #rx_overrun             ' full: do not store, set OVRN, keep TDRE clear

                        add     t2,rxbuff
                        wrbyte  bus,t2
                        sub     t2,rxbuff
                        add     t2,#1
                        and     t2,#BUFFER_MASK
                        wrlong  t2,par                  ' rx_head

                        add     t2,#1                   ' full after this store?
                        and     t2,#BUFFER_MASK
                        cmp     t2,t3                wz
            if_e        jmp     #clear_tdre

                        rdlong  t1,acia_status_addr
                        or      t1,acia_status_tdre     ' room remains, TDR empty
                        and     t1,data_active_mask
                        wrlong  t1,acia_status_addr
                        jmp     #wait

rx_overrun                                              ' Z80 wrote TDR with FIFO full
                        rdlong  t1,acia_status_addr
                        or      t1,acia_status_ovrn
                        andn    t1,acia_status_tdre
                        and     t1,data_active_mask
                        wrlong  t1,acia_status_addr
                        jmp     #wait

transmit_data                                           ' Z80 read RDR ← Propeller tx FIFO
                        mov     t1,par
                        add     t1,#8                   ' tx_head
                        rdlong  t2,t1
                        add     t1,#4                   ' tx_tail
                        rdlong  t3,t1
                        cmp     t2,t3                wz ' empty?

            if_nz       add     t3,txbuff
            if_nz       rdbyte  bus,t3
            if_nz       sub     t3,txbuff
            if_z        mov     bus,#0                  ' empty RDR: present 0, do not move tail

                        shl     bus,#DATA_BASE
                        or      outa,bus
                        or      dira,data_active_mask

            if_nz       add     t3,#1
            if_nz       and     t3,#BUFFER_MASK
            if_nz       wrlong  t3,t1                   ' tx_tail

                        or      outa,bus_wait           ' clear /WAIT line high to continue
                        waitpeq bus_rd,bus_rd           ' wait for /RD to raise
                        andn    dira,data_active_mask
                        andn    outa,data_active_mask

                        rdlong  t1,acia_status_addr
                        andn    t1,acia_status_ovrn     ' reading RDR clears OVRN

                        rdlong  bus,acia_config_addr
                        and     bus,acia_config_tx_mask
                        xor     bus,acia_config_rts1 wz
            if_z        jmp     #:drop_rdrf             ' /RTS high: hide RDRF, keep bytes

                        cmp     t2,t3                wz
            if_ne       jmp     #:keep_rdrf             ' bytes remain

:drop_rdrf
                        andn    t1,acia_status_rdrf
                        jmp     #:wrstat
:keep_rdrf
                        or      t1,acia_status_rdrf
:wrstat
                        and     t1,data_active_mask
                        wrlong  t1,acia_status_addr
                        jmp     #wait

clear_tdre
                        rdlong  t1,acia_status_addr
                        andn    t1,acia_status_tdre
                        and     t1,data_active_mask
                        wrlong  t1,acia_status_addr
                        jmp     #wait

clear_rdrf
                        rdlong  t1,acia_status_addr
                        andn    t1,acia_status_rdrf
                        and     t1,data_active_mask
                        wrlong  t1,acia_status_addr
                        jmp     #wait

' Drive /INT as a level from this cog only (DIRA bit 25).
' Assert while (RIE and (RDRF or OVRN)) or (TIE mode and TDRE).
' OUTA bit 25 stays 0 so the pin is low when driven. waitpeq wr may
' carry into that bit; the wait loop clears it.
sync_irq
                        rdlong  t1,acia_config_addr
                        rdlong  t2,acia_status_addr
                        mov     t3,#0                   ' 0 = release, 1 = assert

                        mov     bus,t1
                        and     bus,acia_config_tx_mask
                        xor     bus,acia_config_tie  wz
            if_nz       jmp     #:chk_rx
                        test    t2,acia_status_tdre  wz
            if_nz       mov     t3,#1

:chk_rx
                        test    t1,acia_config_rie   wz
            if_z        jmp     #:apply
                        test    t2,acia_status_rdrf  wz
            if_nz       mov     t3,#1
                        test    t2,acia_status_ovrn  wz
            if_nz       mov     t3,#1

:apply
                        cmp     t3,#0                wz
            if_z        jmp     #:release
                        andn    outa,bus_int            ' drive low
                        or      dira,bus_int
                        or      t2,acia_status_irq
                        jmp     #:wrirq
:release
                        andn    dira,bus_int            ' float (open collector)
                        andn    t2,acia_status_irq
:wrirq
                        and     t2,data_active_mask
                        wrlong  t2,acia_status_addr
sync_irq_ret            ret

'
' Constants
'
bus_wait                long    WAIT_PIN
bus_int                 long    INT_PIN

bus_rd                  long    RD_PIN
bus_wr                  long    WR_PIN

bus_a0                  long    A0_PIN

port_active_mask        long    WAIT_PIN | M1_PIN | PORT_MASK
data_active_mask        long    DATA_PINS << DATA_BASE

acia_status_initial     long    ( SR_TDRE ) << DATA_BASE  ' master reset and start() status

acia_config_reset       long    ( CR_RESET ) << DATA_BASE
acia_config_rie         long    ( CR_RIE ) << DATA_BASE
acia_config_rts1        long    ( CR_TID_RTS1 ) << DATA_BASE

acia_config_tie         long    ( CR_TIE_RTS0 ) << DATA_BASE
acia_config_tx_mask     long    ( CR_TIX_MASK ) << DATA_BASE

acia_status_irq         long    ( SR_IRQ ) << DATA_BASE
acia_status_tdre        long    ( SR_TDRE ) << DATA_BASE
acia_status_rdrf        long    ( SR_RDRF ) << DATA_BASE
acia_status_ovrn        long    ( SR_OVRN ) << DATA_BASE

'
' Uninitialized data

acia_base_addr          res     1
acia_config_addr        res     1
acia_status_addr        res     1

rxbuff                  res     1
txbuff                  res     1

t1                      res     1
t2                      res     1
t3                      res     1

bus                     res     1
pollcnt                 res     1

                        fit


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
