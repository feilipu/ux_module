''
'' UX Module RC2014 Bus Interface
''
'' ACIA emulation
''
'' Bus wait from 569cd07 (waitpne then waitpeq wr, no Hub between).
'' After /WAIT: wait_pin_high (samples req_master). Hub mailbox is 11 longs.
'' last_rdr in cog RAM. sync_irq composes status on a status read.
'' Spin still pulses DIRA[25] (RIE/TIE). It does not RMW acia_status.
'' No XON/XOFF. PUMP_LIMIT, readZ80 ftdiNeed, hostXmodem.
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

                                    '11 contiguous longs
  long  rx_head                     '#0   index into rx_buffer
  long  rx_tail                     '#4
  long  tx_head                     '#8
  long  tx_tail                     '#12
  long  acia_base                   '#16  ACIA base address (allowing for multiple instances)
  long  acia_config                 '#20  ACIA configuration byte stored shifted by DATA_BASE
  long  acia_status                 '#24  ACIA status byte stored shifted by DATA_BASE
  long  buffer_ptr                  '#28
  long  tdre_hold                   '#32  Spin 0/1; PASM keeps TDRE clear while nonzero
  long  req_master                  '#36  CTRL+ALT+DEL: full 6850 reset including tdre_hold
  long  req_parse_idle              '#40  CR_RESET: Cog 0 must set PARSE_IDLE
  byte  rx_buffer[BUFFER_LENGTH]    '#44
  byte  tx_buffer[BUFFER_LENGTH]    '#44 + BUFFER_LENGTH


PUB start(base) : okay
{{Starts RC2014 acia bus driver in a new cog
      okay - returns false if no cog is available.}}

  stop
  longfill(@rx_head, 0, 4)                                ' These are indexes to bytes in the buffer, not pointers
  acia_base := base
  acia_config := constant (( CR_TID_RTS0 | CR_8N1 | CR_DIV_64 ) << DATA_BASE )
  acia_status := constant ( SR_TDRE << DATA_BASE )        ' Initially ready to receive bytes from the Z80
  buffer_ptr := @rx_buffer                                ' Record the origin address of the Rx and Tx buffers
  tdre_hold := 0
  req_master := 0
  req_parse_idle := 0
  okay := cog := cognew(@entry,@rx_head) + 1


PUB stop
{{Stops acia driver - frees a cog}}

  if cog
      cogstop(cog~ - 1)
      longfill(@rx_head, 0, 11)


PUB txString( pStringPtr )
{{Print a zero-terminated string to terminal.
 pStrPtr - Pointer to null terminated string to print.}}

  repeat strsize( pStringPtr)
    tx(byte[pStringPtr++])


PUB tx(txbyte)
{{Sends byte. Waits for room unless a FIFO reset is in progress.
  Aborts (drops the byte) on req_parse_idle or req_master so CR_RESET cannot tear indexes.}}

  repeat
    if req_parse_idle or req_master
      return
    if (tx_tail - tx_head) & BUFFER_MASK <> 1
      quit
    if ( tx_tail <> tx_head ) and not ( acia_config & constant ( CR_TID_RTS1 << DATA_BASE ) )
      if acia_config & constant ( CR_RIE << DATA_BASE )
        dira[ INT_PIN_NUM ]~~
        dira[ INT_PIN_NUM ]~

  if req_parse_idle or req_master
    return
  tx_buffer[tx_head] := txbyte
  if req_parse_idle or req_master
    return
  tx_head := ++tx_head & BUFFER_MASK

  if not ( acia_config & constant ( CR_TID_RTS1 << DATA_BASE ) )
    if acia_config & constant ( CR_RIE << DATA_BASE )
      dira[ INT_PIN_NUM ]~~
      dira[ INT_PIN_NUM ]~


PUB txCheck : truefalse
{{Check and return true if space in transmit buffer; return immediately.
  Returns: t|f}}

  truefalse := tx_tail <> ((tx_head + 1) & BUFFER_MASK )


PUB rx : rxbyte
{{Receive single-byte character. Waits until a character is present.
  Aborts with 0 on req_parse_idle or req_master. Does not write TDRE.}}

  repeat
    if req_parse_idle or req_master
      rxbyte := 0
      return
    if rxCount > 0
      quit

  if req_parse_idle or req_master
    rxbyte := 0
    return
  rxbyte := rx_buffer[rx_tail]
  if req_parse_idle or req_master
    return
  rx_tail := ++rx_tail & BUFFER_MASK


PUB rxCount : count
{{Get count of characters in receive buffer. Manages receive flow control.
  Returns: number of characters waiting in receive buffer.}}

  count := rx_head - rx_tail
  count -= BUFFER_LENGTH * (count < 0)

  if not tdre_hold and ( count < constant ( BUFFER_LENGTH-1 ) )
    if acia_config & constant ( CR_TIE_RTS0 << DATA_BASE )
      dira[ INT_PIN_NUM ]~~
      dira[ INT_PIN_NUM ]~


PUB rxCheck : truefalse
{{Check if character received; return immediately.
  Returns: t|f}}

  truefalse := rx_tail <> rx_head



PUB txSpace : count
  count := (tx_tail - tx_head - 1) & BUFFER_MASK

PUB rxPeek : rxbyte
  rxbyte := rx_buffer[rx_tail]

PUB tdreHold
{{Ask PASM to keep TDRE clear so the Z80 stops writing TDR.}}

  tdre_hold := 1


PUB tdreAllow
{{Allow PASM to set TDRE when the RX FIFO has room.}}

  tdre_hold := 0

PUB masterReset
{{CTRL+ALT+DEL: 6850 master reset including tdre_hold and config $03.
  Sets req_master so wait_pin_high can abort a wedged /RD or /WR rise.
  Does not wait for PASM: Z80 is in reset, so waitpeq has no match.}}

  tx_tail := tx_head := 0
  rx_tail := rx_head := 0
  tdre_hold := 0
  acia_config := constant ( CR_RESET << DATA_BASE )
  if cog
    req_master := 1
    req_parse_idle := 1
  else
    acia_status := constant ( SR_TDRE << DATA_BASE )

PUB takeParseIdle : truefalse
{{True once after a Z80 CR_RESET. Caller sets PARSE_IDLE. Does not clear tdre_hold.}}

  truefalse := req_parse_idle
  if truefalse
    req_parse_idle := 0


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

                        add     t1,#4                   ' tdre_hold #32
                        mov     tdre_hold_addr,t1
                        add     t1,#4                   ' req_master #36
                        mov     req_master_addr,t1
                        add     t1,#4                   ' req_parse_idle #40
                        mov     req_parse_idle_addr,t1
                        mov     last_rdr,#0
                        mov     cog_rts_hold,#0

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
                        testn   bus_rd,ina           wz ' capture port data again, test for /RD pin low
            if_nz       jmp     #transmit_data

                        testn   bus_wr,ina           wz ' capture port data again, test for /WR pin low
            if_nz       jmp     #receive_data

                        jmp     #wait                   ' then go back and wait for next address chance

receive_command
                        or      outa,bus_wait           ' set /WAIT line high to continue
                        mov     bus,ina                 ' capture the command byte (stored shifted by DATA_BASE)
                        mov     wait_mask,bus_wr
                        call    #wait_pin_high          ' /WR high
                        and     bus,data_active_mask    ' mask received command byte
                        wrlong  bus,acia_config_addr
                        mov     t2,bus
                        and     t2,acia_config_tx_mask
                        xor     t2,acia_config_rts1 wz
                        mov     cog_rts_hold,#0
            if_z        mov     cog_rts_hold,#1         ' exact CR_TID_RTS1: do not consume RDR
                        xor     bus,acia_config_reset wz' master reset if we've received the RESET command
            if_nz       jmp     #wait

                        mov     t2,#1                   ' flag first so Spin tx/rx abort before indexes move
                        wrlong  t2,req_parse_idle_addr
                        mov     t1,par                  ' zero both FIFOs
                        mov     t2,#0
                        wrlong  t2,t1                   ' rx_head
                        add     t1,#4
                        wrlong  t2,t1                   ' rx_tail
                        add     t1,#4
                        wrlong  t2,t1                   ' tx_head
                        add     t1,#4
                        wrlong  t2,t1                   ' tx_tail
                        mov     last_rdr,#0
                        wrlong  acia_status_initial,acia_status_addr  ' TDRE, RDRF clear
                        jmp     #wait                   ' keep tdre_hold

transmit_status
                        rdlong  t1,acia_config_addr     ' get the command byte
                        xor     t1,acia_config_reset wz ' RESET command: RomWBW probe wants status 0
            if_z        jmp     #:null
                        call    #sync_irq               ' after /WAIT; FIFO + tdre_hold + /RTS
                        rdlong  bus,acia_status_addr
                        jmp     #:put
:null                   mov     bus,#0
:put                    and     bus,data_active_mask    ' mask transmitted status byte
                        or      outa,bus                ' transmit the status byte (stored shifted by DATA_BASE)
                        or      dira,data_active_mask   ' set data bus lines to active (output)
                        nop                             ' wait for data bus lines to settle before releasing /WAIT
                        nop
                        nop
                        nop
                        or      outa,bus_wait           ' set /WAIT line high to continue
                        mov     wait_mask,bus_rd
                        call    #wait_pin_high          ' /RD high
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
                        mov     wait_mask,bus_wr
                        call    #wait_pin_high          ' /WR high
                        shr     bus,#DATA_BASE          ' shift data so that the LSB corresponds with D0

                        mov     t1,t2                   ' next head
                        add     t1,#1
                        and     t1,#BUFFER_MASK
                        cmp     t1,t3                wz
            if_e        jmp     #wait                   ' full: drop the write; OVRN is a receiver bit

                        add     t2,rxbuff               ' create the pointer to the head of rx_buffer to write
                        wrbyte  bus,t2                  ' write the byte (in bus) to address in t2
                        sub     t2,rxbuff               ' recover value (result is rx_head)

                        add     t2,#1                   ' increment the rx_head count
                        and     t2,#BUFFER_MASK         ' and check for range (if > #BUFFER_MASK then rollover)
                        wrlong  t2,par                  ' write the rx_head value back to par (rx_head)
                        jmp     #wait                   ' TDRE from sync_irq on the next status read


transmit_data                                           ' check for tx_head <> tx_tail
                        mov     t1,par                  ' get address of rx_head assign it to t1
                        add     t1,#8                   ' increment t1 by 8 bytes. Result is address of tx_head
                        rdlong  t2,t1                   ' copy value of tx_head into t2
                        add     t1,#4                   ' increment t1 by 4 bytes. Result is address of tx_tail
                        rdlong  t3,t1                   ' copy value of tx_tail into t3
                        mov     wait_mask,t3            ' original tail (empty if t2 == this)

                        add     t3,txbuff               ' add address of txbuff to value of tx_tail
                        rdbyte  bus,t3                  ' read byte from the tail of the tx_buffer into bus
                        sub     t3,txbuff               ' subtract address of bus (result is tx_tail)
                        cmp     t2,wait_mask         wz ' empty: last byte, do not use the stale cell
            if_e        jmp     #:hold
                        cmp     cog_rts_hold,#0      wz
            if_nz       jmp     #:hold                  ' /RTS high: last byte, keep FIFO
                        mov     last_rdr,bus
                        jmp     #:drv
:hold                   mov     bus,last_rdr
:drv

                        shl     bus,#DATA_BASE          ' shift data so that the LSB corresponds with DATA_BASE
                        or      outa,bus                ' write byte to Parallel FIFO
                        or      dira,data_active_mask   ' set data bus lines to active (output)
                                                        ' wait for data bus lines to settle before releasing /WAIT

                        add     t3,#1                   ' increment t3 by 1 byte (same as tx_tail + 1)
                        and     t3,#BUFFER_MASK         ' and check for range (if > #BUFFER_MASK then rollover)
                        cmp     t2,wait_mask         wz ' empty at entry: do not skip a later byte
            if_e        mov     t3,wait_mask
                        cmp     cog_rts_hold,#0      wz
            if_nz       mov     t3,wait_mask            ' /RTS high: do not move tail
                        wrlong  t3,t1                   ' write long value of t3 into address tx_tail

                        or      outa,bus_wait           ' clear /WAIT line high to continue
                        mov     wait_mask,bus_rd
                        call    #wait_pin_high          ' /RD high
                        andn    dira,data_active_mask   ' clear data bus lines to inactive (input)
                        andn    outa,data_active_mask   ' ensure data bus pins are cleared to zero
                        jmp     #wait                   ' RDRF from sync_irq on the next status read

' Wait until (ina & wait_mask) is nonzero (pin high).
' After /WAIT release only. Do not call on the match path.
' Sample req_master here so a wedged rise can abort. Do not waitpeq.
wait_pin_high
:loop                   rdlong  t1,req_master_addr
                        cmp     t1,#0                wz
            if_nz       jmp     #do_master_reset
                        test    wait_mask,ina        wz
            if_z        jmp     #:loop
wait_pin_high_ret       ret

do_master_reset                                         ' panic / wedged rise. Keep tdre_hold (Spin panic sets it).
                        andn    dira,data_active_mask   ' float data if we aborted a drive
                        andn    outa,data_active_mask
                        or      outa,bus_wait
                        mov     t2,#1                   ' parser idle; Spin tx/rx abort
                        wrlong  t2,req_parse_idle_addr
                        wrlong  acia_config_reset,acia_config_addr  ' $03 so TIE is off
                        mov     cog_rts_hold,#0
                        mov     t1,par
                        mov     t2,#0
                        wrlong  t2,t1                   ' rx_head
                        add     t1,#4
                        wrlong  t2,t1                   ' rx_tail
                        add     t1,#4
                        wrlong  t2,t1                   ' tx_head
                        add     t1,#4
                        wrlong  t2,t1                   ' tx_tail
                        mov     last_rdr,#0
                        wrlong  acia_status_initial,acia_status_addr
                        wrlong  t2,req_master_addr
                        jmp     #wait

' Compose RDRF/TDRE/IRQ after /WAIT. Do not call between waitpne and waitpeq wr.
' RDRF from TX FIFO and /RTS. TDRE from RX room and tdre_hold.
sync_irq
                        rdlong  bus,req_master_addr
                        cmp     bus,#0               wz
            if_nz       jmp     #do_master_reset

                        rdlong  t1,acia_config_addr
                        rdlong  t2,acia_status_addr
                        andn    t2,acia_status_rdrf
                        andn    t2,acia_status_tdre
                        andn    t2,acia_status_irq      ' recompute; keep OVRN

                        mov     t3,par
                        add     t3,#8
                        rdlong  bus,t3                  ' tx_head
                        add     t3,#4
                        rdlong  t3,t3                   ' tx_tail
                        cmp     bus,t3               wz
            if_e        jmp     #:tdre                  ' empty: RDRF stays clear
                        mov     bus,t1
                        and     bus,acia_config_tx_mask
                        xor     bus,acia_config_rts1 wz
            if_nz       or      t2,acia_status_rdrf     ' not /RTS high

:tdre                   rdlong  bus,tdre_hold_addr
                        cmp     bus,#0               wz
            if_nz       jmp     #:irq                   ' hold: TDRE stays clear
                        mov     t3,par
                        rdlong  bus,t3                  ' rx_head
                        add     t3,#4
                        rdlong  t3,t3                   ' rx_tail
                        add     bus,#1
                        and     bus,#BUFFER_MASK
                        cmp     bus,t3               wz
            if_ne       or      t2,acia_status_tdre     ' not full

:irq                    mov     t3,#0
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
                        andn    outa,bus_int
                        or      dira,bus_int
                        or      t2,acia_status_irq
                        jmp     #:wrirq
:release
                        andn    dira,bus_int
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
acia_status_ovrn        long    ( SR_OVRN ) << DATA_BASE

'
' Uninitialized data

acia_base_addr          res     1
acia_config_addr        res     1
acia_status_addr        res     1
tdre_hold_addr          res     1
req_master_addr         res     1
req_parse_idle_addr     res     1

rxbuff                  res     1
txbuff                  res     1

t1                      res     1
t2                      res     1
t3                      res     1

bus                     res     1
wait_mask               res     1
last_rdr                res     1
cog_rts_hold            res     1

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
