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

  MAX_STRING  =   255

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

                                    '8 contiguous longs
  long  rx_head                     '#0   index into rx_buffer
  long  rx_tail                     '#4
  long  tx_head                     '#8
  long  tx_tail                     '#12
  long  acia_base                   '#16  ACIA base address (allowing for multiple instances)
  long  acia_config                 '#20  ACIA configuration byte stored shifted by DATA_BASE
  long  acia_status                 '#24  ACIA status byte stored shifted by DATA_BASE
  long  buffer_ptr                  '#28
  byte  rx_buffer[BUFFER_LENGTH]    '#32  transmit and receive buffers for ACIA emulation
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
{{Sends byte. Will wait for room in buffer.}}

  repeat until (tx_tail - tx_head) & BUFFER_MASK <>  1    ' Wait until buffer is not full, checking flow control via /RTS
    if ( tx_tail <> tx_head ) and not ( acia_config & constant ( CR_TID_RTS1 << DATA_BASE ) )
                                                          ' if buffer is not empty and /RTS was cleared by Z80, so we can proceed
      acia_status |= constant ( SR_RDRF << DATA_BASE  )   ' now a byte ready to transmit to Z80

      if acia_config & constant ( CR_RIE << DATA_BASE )   ' If the Receive Interrupt Enable (Z80 perspective) should be set
'       acia_status |= constant ( SR_IRQ << DATA_BASE )   ' Set the interrupt status byte (cleared in driver cog)
        dira[ INT_PIN_NUM ]~~                             ' Set the /INT pin to output to wake up the Z80 (minimum 136ns pulse = 1 RC2014 standard clock)
        dira[ INT_PIN_NUM ]~                              ' Clear /INT pin to input (measured pulse is 5,600ns)

  tx_buffer[tx_head] := txbyte
  tx_head := ++tx_head & BUFFER_MASK

  if not acia_config & constant ( CR_TID_RTS1 << DATA_BASE )
                                                          ' /RTS was cleared by Z80
    acia_status |= constant ( SR_RDRF << DATA_BASE  )     ' now a byte is ready to transmit to Z80

    if acia_config & constant ( CR_RIE << DATA_BASE )     ' If the Receive Interrupt Enable (Z80 perspective) should be set
'     acia_status |= constant ( SR_IRQ << DATA_BASE )     ' Set the interrupt status byte (cleared in driver cog)
      dira[ INT_PIN_NUM ]~~                               ' Set the /INT pin to output to wake up the Z80 (minimum 136ns pulse = 1 RC2014 standard clock)
      dira[ INT_PIN_NUM ]~                                ' Clear /INT pin to input (measured pulse is 5,600ns)


PUB txFlush

  '' Flush transmit buffer

  tx_tail := tx_head := 0


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
{{Get count of characters in receive buffer. Manages receive flow control.
  Returns: number of characters waiting in receive buffer.}}

  count := rx_head - rx_tail
  count -= BUFFER_LENGTH * (count < 0)

  if ( count < constant ( BUFFER_LENGTH-1 ) ) and not ( acia_status & constant ( SR_TDRE << DATA_BASE ) )
                                                          ' Enough space in receive buffer but Transmit Data Register Empty was cleared by interrupt
    acia_status |= constant ( SR_TDRE << DATA_BASE )      ' Set Transmit Data Register Empty

    if acia_config & constant ( CR_TIE_RTS0 << DATA_BASE )' If the Transmit Interrupt Enable (Z80 perspective) should be set
'     acia_status |= constant ( SR_IRQ << DATA_BASE )     ' Set the interrupt status byte (cleared in driver cog)
      dira[ INT_PIN_NUM ]~~                               ' Set the /INT pin to output to wake up the Z80 (minimum 136ns pulse = 1 RC2014 standard clock)
      dira[ INT_PIN_NUM ]~                                ' Clear /INT pin to input (measured pulse is 5,600ns)


PUB rxFlush
{{Flush receive buffer}}

  rx_tail := rx_head := 0


PUB rxCheck : truefalse
{{Check if character received; return immediately.
  Returns: t|f}}

  truefalse := rx_tail <> rx_head


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
                        rdlong  outa,acia_base_addr     ' configure the base address to compare with ina
                                                        ' including /M1 and /WAIT pin

                        waitpne outa,port_active_mask
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
                        rdlong  t1,acia_status_addr
                        andn    t1,acia_status_irq      ' clear the interrupt status bit, because we've handled data
                        and     t1,data_active_mask     ' mask to the status byte
                        wrlong  t1,acia_status_addr

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
            if_nz       jmp     #wait

                        wrlong  acia_status_initial,acia_status_addr  ' master reset status
                        jmp     #wait

transmit_status
                        rdlong  bus,acia_status_addr    ' get the status byte
                        and     bus,data_active_mask    ' mask transmitted status byte
                        rdlong  t1,acia_config_addr     ' get the command byte
                        xor     t1,acia_config_reset wz ' check whether RESET was the last issued command
            if_z        mov     bus,#0                  ' if we're in RESET, then return a NULL as status (for RomWBW)
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

receive_data
                        mov     t1,par                  ' assign value of rx_head to t1
                        rdlong  t2,t1                   ' copy value of rx_head into t2
                        add     t1,#4                   ' increment t1 by 4 bytes. Result is address of rx_tail
                        rdlong  t3,t1                   ' copy value of rx_tail into t3

                        or      outa,bus_wait           ' set /WAIT line high to continue
                        mov     bus,ina                 ' capture the data byte
                        waitpeq bus_wr,bus_wr           ' wait for /WR high
                        shr     bus,#DATA_BASE          ' shift data so that the LSB corresponds with D0

                        add     t2,rxbuff               ' create the pointer to the head of rx_buffer to write
                        wrbyte  bus,t2                  ' write the byte (in bus) to address in t2
                        sub     t2,rxbuff               ' recover value (result is rx_head)

                        add     t2,#1                   ' increment the rx_head count
                        and     t2,#BUFFER_MASK         ' and check for range (if > #BUFFER_MASK then rollover)
                        wrlong  t2,par                  ' write the rx_head value back to par (rx_head)

'                       rdlong  t1,acia_status_addr
'                       andn    t1,acia_status_irq      ' clear IRQ bit
'                       and     t1,data_active_mask     ' mask status byte
'                       wrlong  t1,acia_status_addr

                        add     t2,#1                   ' increment the rx_head count to check for buffer full
                        and     t2,#BUFFER_MASK         ' and check for range (if > #BUFFER_MASK then rollover)
                        cmp     t2,t3                wz ' compare rx_tail and rx_head
            if_e        jmp     #clear_tdre             ' receive buffer is full, so disable reception

                        rdlong  t1,acia_config_addr
                        test    t1,acia_config_tie   wz ' test whether the interrupt pin should be set
            if_nz       jmp     #set_interrupt          ' set the interrupt if needed
                        jmp     #wait                   ' receive byte done


transmit_data                                           ' check for tx_head <> tx_tail
                        mov     t1,par                  ' get address of rx_head assign it to t1
                        add     t1,#8                   ' increment t1 by 8 bytes. Result is address of tx_head
                        rdlong  t2,t1                   ' copy value of tx_head into t2
                        add     t1,#4                   ' increment t1 by 4 bytes. Result is address of tx_tail
                        rdlong  t3,t1                   ' copy value of tx_tail into t3

                        add     t3,txbuff               ' add address of txbuff to value of tx_tail
                        rdbyte  bus,t3                  ' read byte from the tail of the tx_buffer into bus
                        sub     t3,txbuff               ' subtract address of bus (result is tx_tail)

                        shl     bus,#DATA_BASE          ' shift data so that the LSB corresponds with DATA_BASE
                        or      outa,bus                ' write byte to Parallel FIFO
                        or      dira,data_active_mask   ' set data bus lines to active (output)
                                                        ' wait for data bus lines to settle before releasing /WAIT

                        add     t3,#1                   ' increment t3 by 1 byte (same as tx_tail + 1)
                        and     t3,#BUFFER_MASK         ' and check for range (if > #BUFFER_MASK then rollover)
                        wrlong  t3,t1                   ' write long value of t3 into address tx_tail

'                       rdlong  t1,acia_status_addr
'                       andn    t1,acia_status_irq      ' clear IRQ bit
'                       and     t1,data_active_mask     ' mask status byte
'                       wrlong  t1,acia_status_addr

                        or      outa,bus_wait           ' clear /WAIT line high to continue
                        waitpeq bus_rd,bus_rd           ' wait for /RD to raise
                        andn    dira,data_active_mask   ' clear data bus lines to inactive (input)
                        andn    outa,data_active_mask   ' ensure data bus pins are cleared to zero

                        cmp     t2,t3                wz ' compare tx_tail and tx_head
            if_e        jmp     #clear_rdrf             ' if buffer empty, clear RDRF

                        rdlong  t1,acia_config_addr
                        test    t1,acia_config_rts1  wz ' test whether /RTS is low
            if_nz       jmp     #clear_rdrf             ' clear data ready flag and return to wait

                        rdlong  t1,acia_config_addr
                        test    t1,acia_config_rie   wz ' test whether RIE is set and interrupt should be triggered
            if_z        jmp     #wait                   ' if not we're done

set_interrupt
                        or      dira,bus_int            ' set /INT pin to output for minimum 136ns (1 RC2014 clock)
                        rdlong  t1,acia_status_addr
                        or      t1,acia_status_irq      ' set the interrupt status bit
                        andn    dira,bus_int            ' clear /INT pin to input
                        wrlong  t1,acia_status_addr
                        jmp     #wait                   ' set interrupt done

clear_tdre
                        rdlong  t1,acia_status_addr
                        andn    t1,acia_status_tdre     ' clear TDRE bit
                        and     t1,data_active_mask     ' mask status byte
                        wrlong  t1,acia_status_addr
                        jmp     #wait                   ' transmit byte done

clear_rdrf
                        rdlong  t1,acia_status_addr
                        andn    t1,acia_status_rdrf     ' clear RDRF bit
                        and     t1,data_active_mask     ' mask status byte
                        wrlong  t1,acia_status_addr
                        jmp     #wait                   ' transmit byte done

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

acia_config_initial     long    ( CR_TID_RTS0 | CR_8N1 | CR_DIV_64 ) << DATA_BASE
acia_status_initial     long    ( SR_TDRE ) << DATA_BASE

acia_config_reset       long    ( CR_RESET ) << DATA_BASE
acia_config_rie         long    ( CR_RIE ) << DATA_BASE
acia_config_rts1        long    ( CR_TID_RTS1 ) << DATA_BASE

acia_config_tie         long    ( CR_TIE_RTS0 ) << DATA_BASE
acia_config_tx_mask     long    ( CR_TIX_MASK ) << DATA_BASE

acia_status_irq         long    ( SR_IRQ ) << DATA_BASE
acia_status_tdre        long    ( SR_TDRE ) << DATA_BASE
acia_status_rdrf        long    ( SR_RDRF ) << DATA_BASE

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
