'' ===========================================================================
''
''  File: WMF_Terminal_VGA.spin
''
'' This file contains general "terminal services" for the VGA driver HiRes_Text_VGA.
'' This is a work in progress and over time as the version iterates more functionality
'' will be added. However, for now, the object contains the following general sets
'' of functionality:
''
'' 1. General VGA terminal / console functionality
'' 2. Direct screen rendering for printing characters, text, etc.
'' 3. Text parsing functionality to help with string processing.
'' 4. Numeric functions that print binary, hex, decimal numbers as we well as conversion methods
''   from and to.
''
'' Of course, one could separate all these into multiple objects, but in the quest for simplicity
'' I am going to keep all these methods within the same module since they are so tightly coupled,
'' need access to each other, and this is simply easier to deal with. You may want to seperate things
'' out later into multiple modules/objects and you are free to do so.
''
'' Much of the functionality in this object is very specific to the VGA driver it supports. This is
'' a necessary evil of graphics drivers. Each one has its various features, memory layout, functionality,
'' etc. and we must code for it specifically. Additionally, a lot of the methods are generic and process
'' strings, characters, and convert numbers.
''
''  Modification History
''
''  Author:     Andre' LaMothe
''  Copyright (c) Andre' LaMothe / Parallax Inc.
''  See end of file for terms of use
''  Version:    1.0
''  Date:       2/15/2011
''
''  Comments:
''
'' ===========================================================================

CON
' -----------------------------------------------------------------------------
' CONSTANTS, DEFINES, MACROS, ETC.
' -----------------------------------------------------------------------------

  ' import some constants from the VGA driver
  VGACOLS = vga#cols
  VGAROWS = vga#rows

  ' default screen colour themes
  CTHEME_DEFAULT_FG = CTHEME_AUTUMN_INV_FG
  CTHEME_DEFAULT_BG = CTHEME_AUTUMN_INV_BG

  ' 8 x 12 font - characters 0..127
  '
  ' Each long holds four scan lines of a single character. The longs are arranged into
  ' groups of 128 which represent all characters (0..127). There are three groups which
  ' each contain a vertical third of all characters. They are ordered top, middle, and
  ' bottom.
  '
  ' NOTE: MSB set inverts the character. i.e. $31 = a 1  $B1 = an inverted 1
  '
  '  char 0    =  left arrow
  '  char 1    =  right arrow
  '  char 2    =  up arrow
  '  char 3    =  down arrow
  '  char 4    =  empty circle bullet   (radio button)
  '  char 5    =  filled circle bullet (radio button)
  '  char 6    =  empty square bullet   (check box)
  '  char 7    =  filled square bullet (check box)
  '  char 8    =  right triangle bullet
  '  char 9    =  small bullet
  '  char 10   =  top left corner (but curved)
  '  char 11   =  top right corner (but curved)
  '  char 12   =  bottom left corner (but curved)
  '  char 13   =  bottom right corner (but curved)
  '  char 14   =  horizontal line
  '  char 15   =  vertical line
  '  char 16   =  top 'tee'
  '  char 17   =  bottom 'tee'
  '  char 18   =  left 'tee'
  '  char 19   =  right 'tee'
  '  char 20   =  cross point

  FONT_ASCII_TOPLT = 10 ' top left corner character
  FONT_ASCII_TOPRT = 11 ' top right corner character

  FONT_ASCII_BOTLT = 12 ' bottom left character
  FONT_ASCII_BOTRT = 13 ' bottom right character

  FONT_ASCII_HLINE = 14 ' horizontal line character
  FONT_ASCII_VLINE = 15 ' vertical line character

  FONT_ASCII_TOPT  = 16 ' top "t" character
  FONT_ASCII_BOTT  = 17 ' bottom "t" character

  FONT_ASCII_LTT   = 18 ' left "t" character
  FONT_ASCII_RTT   = 19 ' right "t" character
  FONT_ASCII_CROSS = 20 ' cross point character

  FONT_ASCII_DITHER = 24 ' dithered pattern for shadows
  FONT_ASCII_SPACE = 32  ' space

  NULL         = 0 ' NULL pointer

  ' these are general mutually exclusive flags for assigning certain properties
  ' to objects to alter their visual or functional behavior
  ATTR_NULL        = $00

  ' general graphical rendering attributes for controls and windows
  ATTR_DRAW_SHADOW    = $01
  ATTR_DRAW_SOLID     = $02
  ATTR_DRAW_DASH      = $04
  ATTR_DRAW_BORDER    = $08
  ATTR_DRAW_INVERSE   = $10
  ATTR_DRAW_NORMAL    = $00

  ' basic white on black theme  - DOS/CMD console terminal, white text on black background
  CTHEME_WHITENBLACK_F      = %%333
  CTHEME_WHITENBLACK_BG     = %%000

  CTHEME_WHITENBLACK_INV_FG = %%000
  CTHEME_WHITENBLACK_INV_BG = %%333

  ' basic black on white theme  - modern Windows/Linux/Mac OS window with black text on white background
  CTHEME_BLACKNWHITE_FG     = %%000
  CTHEME_BLACKNWHITE_BG     = %%333

  CTHEME_BLACKNWHITE_INV_FG = %%333
  CTHEME_BLACKNWHITE_INV_BG = %%000

  ' Atari/C64 theme  - this is white on dark blue like the old 8-bit systems
  CTHEME_ATARI_C64_FG       = %%333
  CTHEME_ATARI_C64_BG       = %%002

  CTHEME_ATARI_C64_INV_FG   = %%002
  CTHEME_ATARI_C64_INV_BG   = %%333

  ' Apple ][ / Terminal theme  - this theme is green text on a black background, reminiscient of old terminals and the Apple ][.
  CTHEME_APPLE2_FG          = %%030
  CTHEME_APPLE2_BG          = %%000

  CTHEME_APPLE2_INV_FG      = %%000
  CTHEME_APPLE2_INV_BG      = %%030

  ' wasp/yellow jacket theme  - black on yellow background
  CTHEME_WASP_FG            = %%000
  CTHEME_WASP_BG            = %%220

  CTHEME_WASP_INV_FG       = %%220
  CTHEME_WASP_INV_BG       = %%000

  ' autumn theme  - black on orange background
  CTHEME_AUTUMN_FG          = %%000
  CTHEME_AUTUMN_BG          = %%310

  CTHEME_AUTUMN_INV_FG      = %%310
  CTHEME_AUTUMN_INV_BG      = %%000

  ' creamsicle theme  - white on orange background
  CTHEME_CREAMSICLE_FG      = %%333
  CTHEME_CREAMSICLE_BG      = %%310

  CTHEME_CREAMSICLE_INV_FG  = %%310
  CTHEME_CREAMSICLE_INV_BG  = %%333

  ' purple orchid theme  - white on purple background
  CTHEME_ORCHID_FG          = %%333
  CTHEME_ORCHID_BG          = %%112

  CTHEME_ORCHID_INV_FG      = %%112
  CTHEME_ORCHID_INV_BG      = %%333

  ' gremlin theme  - green on gray background
  CTHEME_GREMLIN_FG         = %%030
  CTHEME_GREMLIN_BG         = %%111

  CTHEME_GREMLIN_INV_FG     = %%111
  CTHEME_GREMLIN_INV_BG     = %%030

  ' keyboard keycodes for ease of parser development

  KBD_ASCII_NULL   = $00 ' null character
  KBD_ASCII_TAB    = $09 ' horizontal tab
  KBD_ASCII_LF     = $0A ' line feed
  KBD_ASCII_CR     = $0D ' carriage return

  KBD_ASCII_SPACE  = $20 ' space
  KBD_ASCII_HASH   = $23 ' #
  KBD_ASCII_HEX    = $24 ' $ for hex
  KBD_ASCII_BIN    = $25 ' % for binary
  KBD_ASCII_COMMA  = $2C ' ,
  KBD_ASCII_PERIOD = $2E ' .

  KBD_ASCII_SEMI   = $3A ' ;
  KBD_ASCII_EQUALS = $3D ' =

  KBD_ASCII_LB     = $5B ' [
  KBD_ASCII_RB     = $5D ' ]

  KBD_ASCII_0      = 48
  KBD_ASCII_9      = 57
  KBD_ASCII_A      = 65
  KBD_ASCII_B      = 66
  KBD_ASCII_C      = 67
  KBD_ASCII_D      = 68
  KBD_ASCII_E      = 69
  KBD_ASCII_F      = 70
  KBD_ASCII_G      = 71
  KBD_ASCII_H      = 72
  KBD_ASCII_O      = 79
  KBD_ASCII_P      = 80
  KBD_ASCII_Z      = 90

  KBD_ASCII_LEFT   = $C0
  KBD_ASCII_RIGHT  = $C1
  KBD_ASCII_UP     = $C2
  KBD_ASCII_DOWN   = $C3
  KBD_ASCII_HOME   = $C4
  KBD_ASCII_END    = $C5
  KBD_ASCII_BS     = $C8 ' backspace
  KBD_ASCII_DEL    = $C9 ' delete
  KBD_ASCII_INS    = $CA ' insert
  KBD_ASCII_ESC    = $CB ' escape

  ' keyboard kecode modifier keys

  KBD_ASCII_SHIFT  = $100' eg. Ctrl-Alt-Delete = $6C9
  KBD_ASCII_CTRL   = $200
  KBD_ASCII_ALT    = $400
  KBD_ASCII_WIN    = $800

OBJ
  '---------------------------------------------------------------------------
  ' OBJECTS IMPORTED BY FRAMEWORK
  '---------------------------------------------------------------------------
  ' there are many VGA text drivers, but this is the simplest and cleanest, plus
  ' its developed by Parallax and is somewhat of a standard.

  vga           : "hires_text_vga"


VAR
  long  gVideoBuffer[VGACOLS * VGAROWS / 4]     ' video buffer - could be bytes, but longs allow more efficient scrolling
  long  gVideoBufferPtr                         ' pointer to video buffer
  long  gBackBufferPtr                          ' user can send a "back buffer" to hold screen space overwritten by menuing system
                                                ' this way application doensn't need to refresh screen when menu events occur
                                                ' however, in a really tight application, the user might not be able to spare
                                                ' even a small amount of memory, but, in most cases, menu items are approx 20 characters
                                                ' wide and there are 5-10 menu items, thus the buffer will cost 100-200 bytes

  word  gColors[VGAROWS]                        ' row colors
  long  gVsync                                  ' sync long - written to -1 by VGA driver after each screen refresh

  byte  gStrBuffer[VGACOLS]                     ' generic string buffer, long enough to hold the maximum screen row (128 char)

  ' console terminal variables
  long  gScreenCol, gScreenRow, gScreenNumCols, gScreenNumRows, gScreenAttr, gScreenColor, gScreenFlag, gScreenLasRow


CON
' -----------------------------------------------------------------------------
' INITIALIZATION ENTRY POINT FOR TERMINAL SERVICES DRIVER
' -----------------------------------------------------------------------------

PUB init( pVGABasePin, pTextCursXPtr ) | retVal
{{
DESCRIPTION: Initializes the VGA and Keyboard Drivers as well as basic terminal parameters

PARMS:

   pVGABasePin    - start of 8 consecutive pins where the VGA port is
   pTextCursXPtr  - pointer to start of 6 byte data structure that VGA driver interogates for "text" cursor
                    and "mouse" cursor. The selection of which is text and which is mouse is arbitrary since
                    the driver doesn't know the difference, but we will use the convention that the cursors
                    are text, mouse in that order.

RETURNS:  Returns the screen geometry in high WORD of 32-bit return value
          low byte  = number of character columns
          high byte = number of character rows
}}

  ' initialize any variables here...
  gVideoBufferPtr := @gVideoBuffer

  ' initial terminal settings
  gScreenCol       := 0
  gScreenRow       := 0
  gScreenNumCols   := VGACOLS
  gScreenNumRows   := VGAROWS
  gScreenFlag      := 0

  ' start the VGA driver, send VGA base pins, video buffer, color buffer, pointer to cursors, and vsync global
  vga.start(pVGABasePin, @gVideoBuffer, @gColors, pTextCursXPtr, @gVsync)

  ' ---------------------------------------------------------------------------
  ' setup screen colors
  ' ---------------------------------------------------------------------------

  ' the VGA driver vga_hires_text only has 2 colors per character
  ' (one for foreground, one for background). However,each line/row on the screen
  ' can have its OWN set of 2 colors, thus as long as you design your interfaces

  ' "vertically" you can have more apparent colors, nonetheless, on any one row
  ' there are only two colors. The function call below fills the color table up
  ' for the specified foreground and background colors from the set of "themes"
  ' These are nothing more than some pre-computed color constants that look
  ' "good" and if you are color or artistically challenged will help you make
  ' your GUIs look clean and professional.
  clearFrame( CTHEME_DEFAULT_FG, CTHEME_DEFAULT_BG )

  ' finally return the screen geometry in the format [video_buffer:16 | vga_colums:8 | vga_rows]
  retVal :=   (@gVideoBuffer << 16 ) | ( VGAROWS << 8 ) | VGACOLS

  return ( retVal )

' end PUB ----------------------------------------------------------------------


CON
' -----------------------------------------------------------------------------
' DIRECT FRAMEBUFFER METHODS FOR GENERAL RENDERING FOR CONSOLE AND CONTROLS
' -----------------------------------------------------------------------------

PUB printStr( pStrPtr, pCol, pRow, pInvFlag ) | strLen, vgaIndex, index
{{
DESCRIPTION: This method draws a string directly to the frame buffer avoiding the
terminal system.

PARMS:  pStrPtr  - Pointer to string to print, null terminated.
        pCol     - Column(x) position to print (0,0) upper left.
        pRow     - Row(y) position to print.
        pInvFlag - Renders character with inverse video colors; background swapped with foreground color.

RETURNS: Nothing.
}}

  if ( pRow < VGAROWS ) AND ( pCol < VGACOLS )
    strLen := strsize( pStrPtr )
    vgaIndex := pRow * VGACOLS + pCol
    bytemove( gVideoBufferPtr + vgaIndex, pStrPtr, strLen )

  if ( pInvFlag )
    repeat index from 1 to strLen
      byte[gVideoBufferPtr][vgaIndex] += 128
      ++vgaIndex

' end PUB ----------------------------------------------------------------------


PUB printChar( pChar, pCol, pRow, pInvFlag )
{{
DESCRIPTION: Draws a character directly to the frame buffer avoiding the terminal system.

PARMS:  pChar    - Character to print.
        pCol     - Column(x) position to print (0,0) upper left.
        pRow     - Row(y) position to print.
        pInvFlag - Renders character with inverse video colors; background swampped with foreground color.

RETURNS: Nothing.
}}

' prints a single character to the screen in "direct mode"
  if ( pRow < VGAROWS ) AND ( pCol < VGACOLS )
    ' check inverse video flag, if so, add 128 for inverse character set
    if (pInvFlag)
      pChar += 128

    byte[ gVideoBufferPtr ][pCol + (pRow * gScreenNumCols)] := pChar

' end PUB ----------------------------------------------------------------------


PUB clearFrame( pFGroundColor, pBGroundColor ) | colorWord
{{
DESCRIPTION: Clear the screen at the memory buffer level, very fast. However, doesn't
effect the terminal sub-system or cursor position, they are independant.

PARMS:  pFGroundColor - foreground color in RGB[2:2:2] format.
        pBGroundColor - background color in RGB[2:2:2] format.

RETURNS: Nothing.
}}

  ' build color word in proper format
  colorWord := pBGroundColor << 10 + pFGroundColor << 2

  ' clear the screen (long at a time, this is why video buffer needs to be on
  ' long boundary
  longfill( gVideoBufferPtr, $20202020, VGACOLS*VGAROWS/4 )

  ' clear color control buffer
  wordfill( @gColors, colorWord, VGAROWS )

' end PUB ----------------------------------------------------------------------


PUB setLineColor( pRow, pFGroundColor, pBGroundColor ) | colorWord
{{
DESCRIPTION: Sets the sent row to the given foreground and background color. The VGA
driver this framework is connected to vga_hires_text has only 2 colors per row, but
we can control those colors. We give color up for high resoloution.

PARMS:  pRow - the row to change the foreground and backgroundf color of.
        pFGroundColor - the foreground color in RGB[2:2:2] format.
        pBGroundColor - the background color in RGB[2:2:2] format.

RETURNS: Nothing.
}}

  if ( pRow < VGAROWS )
    colorWord := pBGroundColor << 10 + pFGroundColor << 2
    gColors[ pRow ] := colorWord

' end PUB ----------------------------------------------------------------------


PUB drawFrame( pCol, pRow, pWidth, pHeight, pTitlePtr, pAttr, pVgaPtr, pVgaWidth ) | index, index2, vgaIndex, rowCount, vgaStartIndex , pWidth_2
{{
DESCRIPTION: This method draws a rectangular "frame" at pCol, pRow directly to the graphics buffer
with size pWidth x pHeight. Also, if pTitlePtr is not null then a title is drawn above the frame in a
smaller frame, so it looks nice and clean.

PARMS:

  pCol       - The column to draw the frame at.
  pRow       - The row to draw the frame at.
  pWidth     - The overall width of frame.
  pHeight    - The height of the frame.
  pTitlePtr  - ASCIIZ String to print as title or null for no title.
  pAttr      - Rendering attributes such as shadow, etc. see CON section at top of program for all ATTR_* flags.
               Currently only ATTR_DRAW_SHADOW and ATTR_DRAW_INVERSE are implemented.
  pVgaPtr    - Pointer to VGA character graphics buffer.
  pVgaWidth  - Width of VGA screen in bytes, same as number of columns in screen; 40, 64, 80, 100, etc.


RETURNS: Nothing.
}}

  vgaStartIndex := pRow * pVgaWidth + pCol

  ' pre-compute this value since its used so much
  pWidth_2 := pWidth-2

  ' starting rendering index
  vgaIndex := vgaStartIndex

  ' clear the target rectangle
  repeat pHeight
    bytefill(@byte[pVgaPtr][vgaIndex],32,pWidth)
    vgaIndex += pVgaWidth

  ' reset to top left of box
  vgaIndex := vgaStartIndex

  ' draw top left corner, then horizontal line followed by rop right character
  byte[pVgaPtr][vgaIndex++] := FONT_ASCII_TOPLT
  bytefill(@byte[pVgaPtr][vgaIndex],FONT_ASCII_HLINE,pWidth_2)
  vgaIndex += pWidth_2
  byte[pVgaPtr][vgaIndex++] := FONT_ASCII_TOPRT

  ' move to next row (potentially title will go here)
  vgaIndex := vgaStartIndex + pVgaWidth

  ' test if there is a title, if so draw it
  if (pTitlePtr <> NULL AND strsize( pTitlePtr ) > 0)

    ' left vertical line, then title, then right vertical line
    byte[pVgaPtr][vgaIndex++] := FONT_ASCII_VLINE
    index := strsize( pTitlePtr )

    ' test if caller wants inverted title
    if ( pAttr & ATTR_DRAW_INVERSE )
      repeat index2 from 0 to index-1
        byte[pVgaPtr][vgaIndex+index2] := byte[pTitlePtr][index2]+128
    else
      bytemove( @byte[pVgaPtr][vgaIndex], pTitlePtr, index )

    vgaIndex += pWidth_2
    byte[pVgaPtr][vgaIndex++] := FONT_ASCII_VLINE

    ' move down to next row (optimize this *2 later)
    vgaIndex := vgaStartIndex + 2 * pVgaWidth

    ' if a title was inserted, then we need to draw the "tee" characters
    ' on the left and right to finish this off

    ' draw left "tee" horizontal line, then right "tee"
    byte[pVgaPtr][vgaIndex++] := FONT_ASCII_LTT
    bytefill(@byte[pVgaPtr][vgaIndex],FONT_ASCII_HLINE,pWidth_2)
    vgaIndex += pWidth_2
    byte[pVgaPtr][vgaIndex++] := FONT_ASCII_RTT

    ' adjust the row counter since we had this added title section
    rowCount := 3

    ' draw shadow on box?
    if (pAttr & ATTR_DRAW_SHADOW)
      byte[pVgaPtr][vgaIndex] := FONT_ASCII_DITHER

  else ' don't adjust row counter, draw the box as usual
    rowCount := 1

  ' taking row counter into consideration, move to next row and finish drawing
  ' left and right sides of box
  vgaIndex := vgaStartIndex + pVgaWidth * rowCount

  ' draw the sides and vertical characters
  repeat pHeight - rowCount - 1
    byte[pVgaPtr][vgaIndex++] := FONT_ASCII_VLINE              'vertical line char
    vgaIndex += pWidth_2
    byte[pVgaPtr][vgaIndex++] := FONT_ASCII_VLINE              'vertical line char

    ' draw shadw on box?
    if (pAttr & ATTR_DRAW_SHADOW)
      byte[pVgaPtr][vgaIndex] := FONT_ASCII_DITHER

    ' adjust current position for rendering, back to left side of next and final row
    vgaIndex -= pWidth
    vgaIndex += pVgaWidth

  'the above left vgaIndex pointing to the start of the last line

  ' draw the last line on the bottom of box which consists
  ' of the bottom left corner char, then the horizontal line char
  ' and finally the bottom right corner char

  byte[pVgaPtr][vgaIndex++] := FONT_ASCII_BOTLT
  bytefill(@byte[pVgaPtr][vgaIndex],FONT_ASCII_HLINE,pWidth_2)
  vgaIndex += pWidth_2
  byte[pVgaPtr][vgaIndex++] := FONT_ASCII_BOTRT

  ' finally shadow?
  if (pAttr & ATTR_DRAW_SHADOW)
    byte[pVgaPtr][vgaIndex]  := FONT_ASCII_DITHER
    vgaIndex += (pVgaWidth - pWidth + 2)
    bytefill(@byte[pVgaPtr][vgaIndex],FONT_ASCII_DITHER,pWidth-1)

' end PUB ----------------------------------------------------------------------


CON
' -----------------------------------------------------------------------------
' TEXT TERMINAL/SCREEN METHODS - THESE METHODS CAN BE CALLED MUCH LIKE THE
' OTHER TERMINAL DRIVERS FOR HIGH LEVEL PRINTING WITH "CONSOLE" EMULATION
' -----------------------------------------------------------------------------

PUB strScreen( pStringPtr )
{{
DESCRIPTION: Prints a string to the terminal.

PARMS: pStrPtr - Pointer to null terminated string to print.

RETURNS: Nothing.
}}

  ' Print a zero-terminated string to terminal
  repeat strsize( pStringPtr)
    outScreen(byte[pStringPtr++])

' end PUB ----------------------------------------------------------------------


PUB strScreenLn( pStringPtr )
{{
DESCRIPTION: Prints a string to the terminal and appends a newline.

PARMS: pStrPtr - Pointer to null terminated string to print.

RETURNS: Nothing.
}}

  ' Print a zero-terminated string to terminal and newline
  strScreen( pStringPtr )
  newLine

' end PUB ----------------------------------------------------------------------


PUB decScreen( pValue, pDigits) | divisor, dividend, zFlag, digit
{{
DESCRIPTION: Prints a decimal number to the screen.

PARMS:  pValue - the number to print.
        pDigits - the maximum number of digits to print.

RETURNS: Nothing.
}}

  ' check for 0
  if (pValue == 0)
    PrintScreen("0")
    return

  ' check for negative
  if (pValue < 0)
    pValue := -pValue
    PrintScreen("-")

  ' generate divisor
  divisor := 1

  repeat (pDigits-1)
    divisor *= 10

  ' pBase 10, only mode where leading 0's are not copied to string
  zFlag := 1

  repeat digit from 0 to (pDigits-1)
    ' print with pBase 10

    dividend := (pValue / divisor)

    if (dividend => 1)
      zFlag := 0

    if (zFlag == 0)
      PrintScreen( dividend + "0")

    pValue := pValue // divisor
    divisor /= 10


' end PUB ----------------------------------------------------------------------


PUB hexScreen(pValue, pDigits)
{{
DESCRIPTION: Prints the sent number in hex format.

PARMS:  pValue  - the number to print in hex format.
        pDigits - the number of hex digits to print.

RETURNS: Nothing.
}}

  ' shift the value into place
  pValue <<= (8 - pDigits) << 2

  repeat pDigits
    PrintScreen(lookupz((pValue <-= 4) & $F : "0".."9", "A".."F"))

' end PUB ----------------------------------------------------------------------


PUB binScreen(pValue, pDigits)
{{
DESCRIPTION: Prints the sent value in binary format with 0's and 1's.

PARMS:  pValue - the number to print in binary format.
        pDigits - the number binary digits to print.

RETURNS: Nothing.
}}

  ' shift the value into place
  pValue <<= 32 - pDigits

  repeat pDigits
    PrintScreen((pValue <-= 1) & 1 + "0")

' end PUB ----------------------------------------------------------------------


PUB newLine
{{
DESCRIPTION: Moves the terminal cursor home and outputs a carriage return.

PARMS: None.

RETURNS: Nothing.
}}

  ' reset terminal column
  gScreenCol := 0

  if (++gScreenRow => gScreenNumRows)
    --gScreenRow

    'scroll lines
    bytemove(gVideoBufferPtr, gVideoBufferPtr + gScreenNumCols, ( (gScreenNumRows-1) * gScreenNumCols ) )

   'clear new line
    bytefill(gVideoBufferPtr + ((gScreenNumRows-1) * gScreenNumCols), FONT_ASCII_SPACE, gScreenNumCols)

' end PUB ----------------------------------------------------------------------


PUB printScreen( pChar )
{{
DESCRIPTION: Prints the sent character to the terminal console with scrolling.

PARMS: pChar - character to print.

RETURNS: Nothing.
}}

  ' print a character at current cursor position
  byte[ gVideoBufferPtr ][ gScreenCol + (gScreenRow * gScreenNumCols)] := pChar

  ' check for scroll
  if (++gScreenCol == gScreenNumCols)
    newLine

' end PUB ----------------------------------------------------------------------


PUB outScreen( pChar )
{{
DESCRIPTION: Output a character to terminal, this is the primary interface from the client to the driver in "terminal mode"
direct mode access uses the register model and controls the engine from the low level

PARMS: pChar - character to print with the following extra controls:


     $00 = clear screen
     $01 = home
     $08 = backspace
     $09 = tab (8 spaces per)
     $0A = set X position (X follows)
     $0B = set Y position (Y follows)
     $0C = set color (color follows)
     $0D = return
     others = prints to the screen

     +128 to any other printable character, draw in inverse video

RETURNS: Nothing.
}}

  case gScreenFlag
    $00: case pChar
           $00: bytefill( gVideoBufferPtr, FONT_ASCII_SPACE, gScreenNumCols * gScreenNumRows)
                gScreenCol := gScreenRow := 0

           $01: gScreenCol := gScreenRow := 0

           $08: if gScreenCol
                  --gScreenCol

           $09: repeat
                  PrintScreen(" ")
                while gScreenCol & 7

           $0A..$0C: gScreenFlag := pChar
                     return

           $0D: newLine

           other: printScreen( pChar )

    $0A: gScreenCol := pChar // gScreenNumCols
    $0B: gScreenRow := pChar // gScreenNumRows
    $0C: gScreenFlag := pChar & 7

  gScreenFlag := 0

' end PUB ----------------------------------------------------------------------


PUB setColScreen( pCol )
{{
DESCRIPTION: Set terminal x column cursor position.

PARMS: pRow - row to set the cursor to.

RETURNS: Nothing.
}}

  gScreenCol := pCol // gScreenNumCols

' end PUB ----------------------------------------------------------------------


PUB setRowScreen( pRow )
{{
DESCRIPTION: Set terminal y row cursor position

PARMS: pRow - row to set the cursor to.

RETURNS: Nothing.
}}

  gScreenRow := pRow // gScreenNumRows

' end PUB ----------------------------------------------------------------------


PUB gotoXYScreen( pCol, pRow )
{{
DESCRIPTION: Sets the x column and y row position of terminal cursor.

PARMS: none.

RETURNS: Nothing.
}}


' set terminal x/column cursor position
  gScreenCol := pCol // gScreenNumCols

' set Terminal y/row cursor position
  gScreenRow := pRow // gScreenNumRows

' end PUB ----------------------------------------------------------------------


PUB getColScreen
' retrieve x column cursor position
{{
DESCRIPTION: Retrieve x terminal cursor position

PARMS: none.

RETURNS: x terminal cursor position.
}}
  return( gScreenCol )

' end PUB ----------------------------------------------------------------------


PUB getRowScreen
{{
DESCRIPTION: Retrieve y row terminal cursor position

PARMS: none.

RETURNS: y terminal cursor position.
}}

  return( gScreenRow )

' end PUB ----------------------------------------------------------------------

PUB clearScreen( pFGroundColor, pBGroundColor )
{{
DESCRIPTION: Clear the screen, and reset the cursors

PARMS:  pFGroundColor - foreground color in RGB[2:2:2] format.
        pBGroundColor - background color in RGB[2:2:2] format.

RETURNS: Nothing.
}}
  clearFrame( pFGroundColor, pBGroundColor )

  gScreenCol       := 0
  gScreenRow       := 0
  gScreenFlag      := 0


CON
' -----------------------------------------------------------------------------
' STRING AND NUMERIC CONVERSION METHODS
' -----------------------------------------------------------------------------

PUB strCpy( pDestStrPtr, pSourceStrPtr ) | strIndex
{{
DESCRIPTION: Copies the NULL terminated source string to the destination string
and null terminates the copy.

PARMS:  pDestStrPtr - destination string storage for string copy.
        pSrcStrPtr  - source string to copy, must be null terminated.

RETURNS: Number of bytes copied.
}}

' test if there is storage
  if ( pDestStrPtr == NULL)
    return (NULL)

  strIndex := 0

  repeat while (byte [ pSourceStrPtr ][ strIndex ] <> NULL)
  ' copy next byte
   byte [ pDestStrPtr ][ strIndex ] := byte [ pSourceStrPtr ][ strIndex ]
   ++strIndex

' null terminate
  byte [ pDestStrPtr ][ strIndex ] := NULL

' return number of bytes copied
  return ( strIndex )

' end PUB ----------------------------------------------------------------------


PUB strUpper( pStringPtr )
{{
DESCRIPTION: Converts the sent string to all uppercase.

PARMS: pStringPtr - NULL terminated ASCII string to convert.

RETURNS: pStringPtr converted to uppercase.
}}

  if ( pStringPtr <> NULL)
    repeat while (byte[ pStringPtr ] <> NULL)
      byte[ pStringPtr ] :=  ToUpper( byte[ pStringPtr ] )
      ++pStringPtr

  ' return string
  return ( pStringPtr )

' end PUB ----------------------------------------------------------------------


PUB toUpper( pChar )
{{
DESCRIPTION: Returns the uppercase of the sent character.

PARMS:  pChar - character to convert to uppercase.

RETURNS: The uppercase version of the character.
}}

  if ( pChar => $61 and pChar =< $7A)
    return( pChar - 32 )
  else
    return( pChar )

' end PUB ----------------------------------------------------------------------


PUB isInSet(pChar, pSetStringPtr)
{{
DESCRIPTION: Tests if sent character is in sent string.

PARMS:  pChar         - character to test for set inclusion.
        pSetStringPtr - string to test for character.

RETURNS: pChar if its in the string set, -1 otherwise. Note to self, maybe
later make this return the position of the 1st occurance, more useful?
}}

  repeat while (byte[ pSetStringPtr ] <> NULL)
    if ( pChar == byte[ pSetStringPtr++ ])
      return( pChar )

' not found
  return( -1 )

' end PUB ----------------------------------------------------------------------


PUB isSpace( pChar )
{{
DESCRIPTION: Tests if sent character is white space, cr, lf, space, or tab.

PARMS: pChar - character to test for white space.

RETURNS: pChar if its a white space character, -1 otherwise.
}}

  if ( (pChar == KBD_ASCII_SPACE) OR (pChar == KBD_ASCII_LF) OR (pChar == KBD_ASCII_CR) or (pChar == KBD_ASCII_TAB))
    return ( pChar )
  else
    return( -1 )

' end PUB ----------------------------------------------------------------------


PUB isNull( pChar )
{{
DESCRIPTION: Tests if sent character is NULL, 0.

PARMS: pChar - character to test.

RETURNS: 1 if pChar is NULL, -1 otherwise.
}}

  if ( ( pChar == NULL))
    return ( 1 )
  else
    return( -1 )

' end PUB ----------------------------------------------------------------------


PUB isDigit( pChar )
{{
DESCRIPTION: Tests if sent character is an ASCII number digit [0..9], returns integer [0..9]

PARMS: pChar - character to test.

RETURNS: pChar if its in the ASCII set [0..9], -1 otherwise.
}}

  if ( (pChar => KBD_ASCII_0) AND (pChar =< KBD_ASCII_9) )
    return ( pChar-KBD_ASCII_0 )
  else
    return(-1)

' end PUB ----------------------------------------------------------------------


PUB isAlpha( pChar )
{{
DESCRIPTION: Tests if sent character is in the set [a...zA...Z].
Useful for text processing and parsing.

PARMS: pChar - character to test.

RETURNS: pChar if the sent character is in the set [a...zA....Z] or -1 otherwise.
}}

' first convert to uppercase to simplify testing
  pChar := ToUpper( pChar )

  if ( (pChar => KBD_ASCII_A) AND (pChar =< KBD_ASCII_Z))
    return ( pChar )
  else
    return( -1 )

' end PUB ----------------------------------------------------------------------


PUB isPunc( pChar )
{{
DESCRIPTION: Tests if sent character is a punctuation symbol !@#$%^&*()--+={}[]|\;:'",<.>/?.
Helpful for parser and string processing in general.

PARMS: pChar - ASCII character to test if its in the set of punctuation characters.

RETURNS: pChar itself if its in the set, -1 if its not in the set.
}}

  pChar := ToUpper( pChar )

  if ( ((pChar => 33) AND (pChar =< 47)) OR ((pChar => 58) AND (pChar =< 64)) OR ((pChar => 91) AND (pChar =< 96)) OR ((pChar =>123) AND (pChar =< 126)) )
    return ( pChar )
  else
    return( -1 )

' end PUB ----------------------------------------------------------------------


PUB hexToDec( pChar )
{{
DESCRIPTION: Converts ASCII hex digit to decimal.

PARMS: ASCII hex digit ["0"..."9", "A..."F"|"a"..."f"]

RETURNS:
}}
  if ( (pChar => "0") and (pChar =< "9") )
    return (pChar - KBD_ASCII_0)
  elseif ( (pChar => "A") and (pChar =< "F") )
    return (pChar - "A" + 10)
  elseif ( (pChar => "a") and (pChar =< "f") )
    return (pChar - "a" + 10)
  else
    return ( 0 )

' end PUB ----------------------------------------------------------------------


PUB hexToASCII( pValue )
{{
DESCRIPTION: ' converts a number 0..15 to ASCII 0...9, A, B, C, D, E, F. There
should be a better way to do this with lookupz etc., note to self check that out.

PARMS:  pValue - The hex digit value to convert to ASCII digit.

RETURNS: The converted ASCII digit.

}}
{
  if (pValue > 9)
    return ( pValue + "A" - 10 )
  else
    return( pValue + "0" )
}
  return ( lookupz( (pValue & $F) : "0".."9", "A".."F") )


' end PUB ----------------------------------------------------------------------


PUB itoa( pNumber, pBase, pDigits, pStringPtr ) | divisor, digit, zflag, dividend
{{
DESCRIPTION: "C-like" method that converts pNumber to string; decimal, hex, or binary formats. Caller
should make sure that conversion will fit in string, otherwise method will overwrite
data.

PARMS:  pNumber - number to convert to ASCII string.
        pBase   - base for conversion; 2, 10, 16, for binary, decimal, and hex respectively.

RETURNS: Pointer back to the pStringPtr with the converted results.
}}

  ' clear result string
  bytefill( pStringPtr, " ", pDigits)

  ' check for negative
  if (pNumber < 0)
    pNumber := -pNumber
    byte [pStringPtr++] := "-"


  ' pBase 2 code --------------------------------------------------------------
  if (pBase == 2)
    ' print with pBase 2,  bit pNumber
    divisor := 1 << (pDigits-1) ' initialize bitmask

    repeat digit from 0 to (pDigits-1)
      ' print with pBase 2
      byte [pStringPtr++] := ((pNumber & divisor) >> ( (pDigits-1) - digit) + "0")
      divisor >>= 1

  ' pBase 10 code --------------------------------------------------------------
  elseif (pBase == 10)

    ' check for 0
    if (pNumber == 0)
      byte [pStringPtr++] := "0"
    else

      ' generate divisor
      divisor := 1
      repeat (pDigits-1)
        divisor *= 10

      ' pBase 10, only mode where leading 0's are not copied to string
      zflag~~

      repeat digit from 0 to (pDigits-1)
        ' print with pBase 10

        dividend := (pNumber / divisor)

        if (dividend => 1)
          zflag~

        if (zflag == 0)
          byte [pStringPtr++] := (dividend + "0")

        pNumber := pNumber // divisor
        divisor /= 10

  ' pBase 16 code --------------------------------------------------------------
  else
    divisor := $F << (4*(pDigits-1))

    repeat digit from 0 to (pDigits-1)
      ' print with pBase 16
      byte [pStringPtr++] := (HexToASCII ((pNumber & divisor) >> (( (pDigits-1) - digit)*4)))
      divisor >>= 4

   ' null terminate and return
   byte [pStringPtr] := 0

   return( pStringPtr )

  ' end PUB ----------------------------------------------------------------------


PUB atoi( pStringPtr, pLength ) | index, sum, ch, sign
{{
DESCRIPTION: "C-like" method that tries to convert the string to a number, supports binary %, hex $, decimal (default)
pStringPtr can be to a null terminated string, or the pLength can be overridden by sending the pLength shorter
than the null terminator, ignores white space

Eg. %001010110, $EF, 25

PARMS:  pStringPtr - NULL terminated string to attempt numerical conversion.
        pLength    - Maximum length to process of string, if less than length of pStringPtr processing stops early.

RETURNS: The value of the converted number or 0 if conversion couldn't be completed. Of course, the converted
number could be 0, so this is misleading. A better idea might be to use a very large integer, such as +-2 billion
however, if the user assigns this method to a byte then that would be lost as well. Thus, be smart when using
this method!
}}

' initialize vars
  index := 0
  sum   := 0
  sign  := 1

' consume white space
  repeat while (isSpace( byte[ pStringPtr ][index] ) <> -1)
    ++index

' is there a +/- sign?
  if (byte [pStringPtr][index] == "+")
  ' consume it
    ++index
  elseif (byte [pStringPtr][index] == "-")
  ' consume it
    ++index
    sign := -1

' try to determine number base
  if (byte [pStringPtr][index] == KBD_ASCII_HEX)
    ++index
    repeat while ( ( isDigit(ch := byte [pStringPtr][index]) <> -1) or ( isAlpha(ch := byte [pStringPtr][index]) <> -1) )
      ++index
      sum := (sum << 4) + HexToDec( ToUpper(ch) )
      if (index => pLength)
        return (sum*sign)

    return(sum*sign)
' // end if hex number
  elseif (byte [pStringPtr][index] == KBD_ASCII_BIN)
    ++index
    repeat while ( isDigit(ch := byte [pStringPtr][index++]) <> -1)
      sum := (sum << 1) + (ch - KBD_ASCII_0)
      if (index => pLength)
        return (sum*sign)

    return(sum*sign)
' // end if binary number
  else
  ' must be in default base 10, assume that
    repeat while ( isDigit(ch := byte [pStringPtr][index++]) <> -1)
      sum := (sum * 10) + (ch - KBD_ASCII_0)
      if (index => pLength)
        return (sum*sign)

    return(sum*sign)

' else, have no idea of number format!
  return( 0 )


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