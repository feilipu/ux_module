''***************************************
''*  User Experience Module             *
''*  Designed for RC2014                *
''*  Author: Phillip Stevens            *
''*  Copyright (c) 2020                 *
''*  See end of file for licence        *
''***************************************

CON

  _clkmode      = XTAL1 + PLL16X
  _xinfreq      = 7_372_800

CON

  ' import some constants from the ACIA Emulation

  PORT_00       = acia#PORT_00
  PORT_40       = acia#PORT_40
  PORT_80       = acia#PORT_80
  PORT_C0       = acia#PORT_C0

  DATA_BASE     = acia#DATA_BASE

CON

  ' set these constants based on the Propeller VGA hardware
  VGA_BASE_PIN  = 16  ' VGA pins 16-23

  ' set these constants based on the Propeller PS/2 hardware
  KBD_DATA_PIN  = 27  ' KEYBOARD data pin
  KBD_CLK_PIN   = 26  ' KEYBOARD clock pin

  ' import some constants from the Propeller Window Manager
  VGACOLS       = wmf#VGACOLS
  VGAROWS       = wmf#VGAROWS


VAR

' -----------------------------------------------------------------------------
' DECLARED VARIABLES, ARRAYS, ETC.   
' -----------------------------------------------------------------------------

  byte  gVgaRows, gVgaCols ' convenient globals to store number of columns and rows

  byte  gStrBuff1[64]      ' some string buffers
  byte  gStrBuff2[64]

  ' these data structures contains two cursors in the format [x,y,mode]
  ' these are passed to the VGA driver, so it can render them over the text in the display
  ' like "hardware" cursors, that don't disturb the graphics under them. We can use them
  ' to show where the text cursor and mouse cursor is
  ' The data structure is 6 contiguous bytes which we pass to the VGA driver ultimately
  
  byte  gTextCursX, gTextCursY, gTextCursMode        ' text cursor 0 [x0,y0,mode0] 
  byte  gMouseCursX, gMouseCursY, gMouseCursMode     ' mouse cursor 1 [x1,y1,mode1] (unused but required for VGA driver)

  long  gVideoBufferPtr                              ' holds the address of the video buffer passed back from the VGA driver 


OBJ

      term            : "terminal_ftdi"
      kbd             : "keyboard_ps2"
      wmf             : "wmf_terminal_vga"
      i2c             : "i2c"
      acia            : "acia_rc2014"


PUB start | i

  'start the serial terminal
  term.start (115200)
  term.str (string("UX Module Initialising...",$0D))

  'start the ACIA interface
  acia.start (DATA_BASE)

  'start i2c
  i2c.Init (26, 25)

  'create the GUI
   CreateAppGUI

  ' MAIN EVENT LOOP - this is where you put all your code in an infinite loop...  
   repeat

     
    ' main code goes here................
 
    ' hello world just print some text to the "terminal" which will scroll for us automatically
     GetStringTerm (gStrBuff1, 64)   
    
    ' at this point, the loop will execute freely as fast as is can run this code, let's
    ' make a call to delay 10 ms just to slow things down, so you can see them...
'    wmf.DelayMilliSec ( 10 ) 

' end PUB ---------------------------------------------------------------------


PUB CreateAppGUI | retVal 
' This functions creates the entire user interface for the application and does any other
' static initialization you might want.
 
  ' text cursor starting position and as blinking underscore  
  gTextCursX     := 0                              
  gTextCursY     := 0                              
  gTextCursMode  := %110   

  ' set mouse cursor position as off
  gMouseCursX    := 0                             
  gMouseCursY    := 0                              
  gMouseCursMode := 0     

  'start the keyboard
  kbd.start (KBD_DATA_PIN, KBD_CLK_PIN)

  ' now start the VGA driver and terminal services 
  retVal := wmf.Init(VGA_BASE_PIN, @gTextCursX )

  ' rows encoded in upper 8-bits. columns in lower 8-bits of return value, redundant code really
  ' since we pull it in with a constant in the first CON section, but up to you! 
  gVgaRows := ( retVal & $0000FF00 ) >> 8
  gVgaCols := retVal & $000000FF

  ' VGA buffer encoded in upper 16-bits of return value
  gVideoBufferPtr := retVal >> 16 

  '---------------------------------------------------------------------------
  'setup screen colors
  '---------------------------------------------------------------------------
 
  ' the VGA driver VGA_HiRes_Text_*** only has 2 colors per character
  ' (one for foreground, one for background). However,each line/row on the screen
  ' can have its OWN set of 2 colors, thus as long as you design your interfaces

  ' "vertically" you can have more apparent colors, nonetheless, on any one row
  ' there are only two colors. The function call below fills the color table up
  ' for the specified foreground and background colors from the set of "themes"
  ' found in the PWM_Terminal_Services_*** driver. These are nothing more than
  ' some pre-computed color constants that look "good" and if you are color or
  ' artistically challenged will help you make your GUIs look clean and professional.
  wmf.ClearScreen( wmf#CTHEME_ATARI_C64_FG, wmf#CTHEME_ATARI_C64_BG )               

  ' return to caller
  return
   
' end PUB ---------------------------------------------------------------------    


CON
' -----------------------------------------------------------------------------
' USER TEXT INPUT FUNCTION(s)   
' -----------------------------------------------------------------------------

PUB GetStringTerm(pStringPtr, pMaxLength) | length, key
{{
DESCRIPTION: This simple function is a single line editor that allows user to enter keys from the keyboard
and then echos them to the screen, when the user hits <ENTER> | <RETURN> the function
exits and returns the string. The function has simple editing and allows <BACKSPACE> to
delete the last character, that's it! The function outputs to the terminal.

PARMS: pStringPTr - pointer to storage for input string.
       pMaxLength - maximum length of string buffer.

RETURNS: pointer to string, empty string if user entered nothing.

}}

  ' current length of string buffer
  length := 0  

  ' draw cursor
  repeat 

    ' draw cursor
    wmf.OutTerm( "_" )
    wmf.OutTerm( $08 )
  
    ' wait for keypress 
    repeat while (kbd.gotkey == FALSE)

    ' user entered a key process it

    ' get key from buffer
    key := kbd.key
     
    case key
       wmf#ASCII_LF, wmf#ASCII_CR: ' return    
        term.newLine

        ' null terminate string and return
        byte [pStringPtr][length] := wmf#ASCII_NULL

        gTextCursX := 0
        gTextCursY++
     
        return ( pStringPtr )
       wmf#ASCII_BS, wmf#ASCII_DEL, wmf#ASCII_LEFT: ' backspace (edit)

         if (length > 0)
           term.backspace

           ' move cursor back once to overwrite last character on screen
           gTextCursX--
           wmf.OutTerm ( wmf#ASCII_SPACE )
           wmf.OutTerm ( $08 )          
           wmf.OutTerm ( $08 )
           
           ' echo character
           wmf.OutTerm( wmf#ASCII_SPACE )
           wmf.OutTerm( $08 )
         
           ' decrement length
           length--
 
       other:    ' all other cases
         term.char (key)

         ' insert character into string 
         byte [pStringPtr][length] := key

         ' update length
         if (length < pMaxLength )
           gTextCursX++
           length++
         else
           term.moveLeft (1)
           gTextCursX--
           ' move cursor back once to overwrite last character on screen
           wmf.OutTerm ( $08 )          

         ' echo character
         wmf.OutTerm ( key )
     
' end PUB ----------------------------------------------------------------------


DAT

{{

┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}    
