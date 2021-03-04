'' VECTORJET for UX Module (based on v1.0)
'' Special version, don't re-use if you don't know what you're doing
'' (C)2021 IRQsome Software
'' VGA output code (based on work by Kwabena W. Agyeman)

{{                   

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Video Circuit:
//
//     0   1   2   3 Pin Group
//
//                     240OHM
// Pin 0,  8, 16, 24 ----R-------- Vertical Sync
//
//                     240OHM
// Pin 1,  9, 17, 25 ----R-------- Horizontal Sync
//
//                     470OHM
// Pin 2, 10, 18, 26 ----R-------- Blue Video
//                            |
//                     240OHM |
// Pin 3, 11, 19, 27 ----R-----
//
//                     470OHM
// Pin 4, 12, 20, 28 ----R-------- Green Video
//                            |
//                     240OHM |
// Pin 5, 13, 21, 29 ----R-----
//
//                     470OHM
// Pin 6, 14, 22, 30 ----R-------- Red Video
//                            |
//                     240OHM |
// Pin 7, 15, 23, 31 ----R-----
//
//                            5V
//                            |
//                            --- 5V
//
//                            --- Vertical Sync Ground
//                            |
//                           GND
//
//                            --- Hoirzontal Sync Ground
//                            |
//                           GND
//
//                            --- Blue Return
//                            |
//                           GND
//
//                            --- Green Return
//                            |
//                           GND
//
//                            --- Red Return
//                            |
//                           GND
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
}}

CON

  #$FC, Light_Grey, #$A8, Grey, #$54, Dark_Grey
  #$C0, Light_Red, #$80, Red, #$40, Dark_Red
  #$30, Light_Green, #$20, Green, #$10, Dark_Green
  #$0C, Light_Blue, #$08, Blue, #$04, Dark_Blue
  #$F0, Light_Orange, #$A0, Orange, #$50, Dark_Orange
  #$CC, Light_Purple, #$88, Purple, #$44, Dark_Purple
  #$3C, Light_Teal, #$28, Teal, #$14, Dark_Teal
  #$FF, White, #$00, Black

VAR

long cogNumber

PUB start(pinGroup,lineBuffers,statusLong) '' 7 Stack Longs

'' ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
'' // Starts up the PIX driver running on a cog.
'' //
'' // Returns true on success and false on failure.
'' //
'' // PinGroup - Pin group to use to drive the video circuit. Between 0 and 3.
'' ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  stop
  if(chipver == 1)

    pinGroup := ((pinGroup <# 3) #> 0)
    directionState := ($FF << (8 * pinGroup))
    videoState := ($30_00_00_FF | (pinGroup << 9))

    pinGroup := constant((20_000_000) / 2)
    frequencyState := 1

    repeat 32
      pinGroup <<= 1
      frequencyState <-= 1
      if(pinGroup => clkfreq)
        pinGroup -= clkfreq
        frequencyState += 1

    syncIndicatorAddress := statusLong
    cogNumber := cognew(@initialization, lineBuffers)
    result or= ++cogNumber

PUB stop '' 3 Stack Longs

'' ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
'' // Shuts down the PIX driver running on a cog.
'' ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  if(cogNumber)
    cogstop(-1 + cogNumber~)

DAT

' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
'                       PIX Driver
' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                        org     0

' //////////////////////Initialization/////////////////////////////////////////////////////////////////////////////////////////

initialization          mov     vcfg,           videoState                 ' Setup video hardware.
                        mov     frqa,           frequencyState             '
                        movi    ctra,           #%0_00001_101              '

' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
'                       Active Video
' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

loop                    mov     tilesCounter,   #0                         '

tilesDisplay
                        test    tilesCounter,   #7      wz
              if_z      mov     displayCounter, par                        ' Set/Reset tiles fill counter. 
                        mov     tileCounter,    #2                         ' Set/Reset tile fill counter.
                        
                        wrlong  tilesCounter,   syncIndicatorAddress

tileDisplay             mov     vscl,           visibleScale               ' Set/Reset the video scale.
                        mov     counter,        #256/4                     '

' //////////////////////Visible Video//////////////////////////////////////////////////////////////////////////////////////////

videoLoop               rdlong  buffer,         displayCounter             ' Download new pixels.
                        add     displayCounter, #4                         '

                        or      buffer,         HVSyncColors               ' Update display scanline.
                        waitvid buffer,         #%%3210                    '

                        djnz    counter,        #videoLoop                 ' Repeat.

' //////////////////////Invisible Video////////////////////////////////////////////////////////////////////////////////////////

                        mov     vscl,           invisibleScale             ' Set/Reset the video scale.

                        waitvid HSyncColors,    syncPixels                 ' Horizontal Sync.

' //////////////////////Repeat/////////////////////////////////////////////////////////////////////////////////////////////////

                        sub     displayCounter, #256                       ' Repeat line.
                        djnz    tileCounter,    #tileDisplay               '

                        add     displayCounter, #256                       ' Next line.
                        add     tilesCounter,   #1
                        cmp     tilesCounter,   #240    wc,wz
              if_b      jmp     #tilesDisplay                              '

' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
'                       Inactive Video
' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                        'add     refreshCounter, #1                         ' Update sync indicator.
                        'wrbyte refreshCounter, syncIndicatorAddress       '

' //////////////////////Front Porch////////////////////////////////////////////////////////////////////////////////////////////

                        mov     counter,        #11                        ' Set loop counter.
                        wrlong  FPorchStatus,   syncIndicatorAddress

frontPorch              mov     vscl,           blankPixels                ' Invisible lines.
                        waitvid HSyncColors,    #0                         '

                        mov     vscl,           invisibleScale             ' Horizontal Sync.
                        waitvid HSyncColors,    syncPixels                 '

                        djnz    counter,        #frontPorch                ' Repeat # times.

' //////////////////////Vertical Sync//////////////////////////////////////////////////////////////////////////////////////////

                        mov     counter,        #(2)                       ' Set loop counter.
                        wrlong  VSyncStatus,    syncIndicatorAddress

verticalSync            mov     vscl,           blankPixels                ' Invisible lines.
                        waitvid VSyncColors,    #0                         '

                        mov     vscl,           invisibleScale             ' Vertical Sync.
                        waitvid VSyncColors,    syncPixels                 '

                        djnz    counter,        #verticalSync              ' Repeat # times.

' //////////////////////Back Porch/////////////////////////////////////////////////////////////////////////////////////////////

                        mov     counter,        #31                        ' Set loop counter.
                        wrlong  BPorchStatus,   syncIndicatorAddress

backPorch               mov     vscl,           blankPixels                ' Invisible lines.
                        waitvid HSyncColors,    #0                         '

                        mov     vscl,           invisibleScale             ' Horizontal Sync.
                        waitvid HSyncColors,    syncPixels                 '

                        djnz    counter,        #backPorch                 ' Repeat # times.

' //////////////////////Update Display Settings////////////////////////////////////////////////////////////////////////////////

                        'rdbyte buffer,         displayIndicatorAddress wz ' Update display settings.
                        or      dira,           directionState             '

' //////////////////////Loop///////////////////////////////////////////////////////////////////////////////////////////////////

                        jmp     #loop                                      ' Loop.

' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
'                       Data
' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

invisibleScale          long    (12 << 12) + 256                           ' Scaling for inactive video.
visibleScale            long    (4 << 12) + 16                             ' Scaling for active video.
blankPixels             long    1024                                       ' Blank scanline pixel length.
syncPixels              long    $0F_FF_FF_F0                               ' F-porch, h-sync, and b-porch.
HSyncColors             long    $01_03_01_03                               ' Horizontal sync color mask.
VSyncColors             long    $00_02_00_02                               ' Vertical sync color mask.
HVSyncColors            long    $03_03_03_03                               ' Horizontal and vertical sync colors.

FPorchStatus            long    %001 << 16 + 240
VSyncStatus             long    %011 << 16
BPorchStatus            long    %101 << 16

' //////////////////////Configuration Settings/////////////////////////////////////////////////////////////////////////////////

directionState          long    0
videoState              long    0
frequencyState          long    0

' //////////////////////Addresses//////////////////////////////////////////////////////////////////////////////////////////////

syncIndicatorAddress    long    0

' //////////////////////Run Time Variables/////////////////////////////////////////////////////////////////////////////////////

counter                 res     1
buffer                  res     1

tileCounter             res     1
tilesCounter            res     1

displayCounter          res     1

' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

                        fit     496

DAT

' /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

{{

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                  TERMS OF USE: MIT License
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
// Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
}}