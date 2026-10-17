'' Framebuffer VGA for the UX Module.
'' Same PLL, porches, and VCFG as VJET_vUXM_vga.spin.
'' Scans a finished 256x80 bitmap. Each stored line is shown six times.
'' Two bits per pixel. Four colours in each group of 16 pixels.
'' A set stripe bit shows the colour $55 lower on the dark lines of that band.
'' The dark lines follow the even and odd pairs of the 2021 picture.
'' PixelClocks is 4 and FrameClocks is 16.
'' 256 source pixels fill the same 1024 PLL clocks.
'' The cog never waits on a render cog. It swaps buffers at the back porch.
''
'' ctrl is eight longs: go, front, done, stripe0, stripe1, stripe2, fixup, blend.
'' This cog writes front and reads done. The renderer owns fixup and blend.
'' pix1 follows pix0. pal1 follows pal0. The byte stride is FB_BYTES and PAL_BYTES.

CON

  FB_W = 256
  FB_H = 80
  FB_BYTES = FB_W * FB_H / 4
  PAL_BYTES = FB_H * 64

VAR

  long cogNumber


PUB set_lines(n) : ok
'' Select a shorter store before start. The default is FB_H.
'' Line n is black and stays in the buffer. The scan is still 480 lines.
'' The second buffer begins (n + 1) * 64 bytes after the first.
'' At line n the next palette read stays on line n.

  lineLimit := n
  frameBytes := (n + 1) << 6
  paletteBytes := (n + 1) << 6
  return 1


PUB start(pinGroup, framePtr, palPtr, ctrlPtr, statusLong) | pixelClock

'' Start the framebuffer VGA cog.
'' framePtr is the first bitmap. The second bitmap is framePtr + frameBytes.
'' palPtr is the first palette table. The second is palPtr + paletteBytes.
'' ctrlPtr is the eight-long control block. This cog writes front and reads done.
'' set_lines selects a shorter store. The default scan is FB_H lines.

  stop
  if(chipver == 1)

    pinGroup := ((pinGroup <# 3) #> 0)
    directionState := ($FF << (8 * pinGroup))
    videoState := (%0_01_1_0_0_000_00000000000_000_0_11111111 | (pinGroup << 9))

    ' Demo PLL. NCO 10 MHz, VCO/4. VCO is 160 MHz.
    pixelClock := constant(20_000_000 / 2)
    frequencyState := 1

    repeat 32
      pixelClock <<= 1
      frequencyState <-= 1
      if(pixelClock => clkfreq)
        pixelClock -= clkfreq
        frequencyState += 1

    syncIndicatorAddress := statusLong
    frameStore := framePtr
    palStore := palPtr
    ctrlStore := ctrlPtr
    cogNumber := cognew(@initialization, 0)
    result or= ++cogNumber


PUB stop

  if(cogNumber)
    cogstop(-1 + cogNumber~)


DAT

                        org     0

initialization          mov     vcfg,           videoState
                        mov     frqa,           frequencyState
                        movi    ctra,           #%0_00001_101

                        or      dira,           directionState

                        mov     pixbase,        frameStore
                        mov     palbase,        palStore
                        mov     front_ptr,      ctrlStore
                        add     front_ptr,      #4
                        mov     done_ptr,       ctrlStore
                        add     done_ptr,       #8
                        mov     shown,          #0
                        mov     docopy,         #0

loop                    mov     tilesCounter,   #0

tilesDisplay            mov     d0,             tilesCounter
                        cmp     d0,             lineLimit wc
              if_nc     mov     d0,             lineLimit
                        shl     d0,             #6
                        mov     linePtr,        pixbase
                        add     linePtr,        d0
                        mov     palLine,        palbase
                        add     palLine,        d0
                        mov     pfptr,          palLine
              if_c      add     pfptr,          #64

                        mov     tileCounter,    #6
                        mov     ptr,            linePtr
                        test    tilesCounter,   #1 wc
              if_c      jmp     #oddopen
                        call    #loadsrc
                        jmp     #showbright

oddopen                 mov     docopy,         #1
                        call    #builddark
                        jmp     #showcopy

showtop                 mov     ptr,            linePtr
                        mov     d0,             tileCounter
                        sub     d0,             #1
                        shr     d0,             #1
                        xor     d0,             tilesCounter
                        shr     d0,             #1 wc
              if_c      jmp     #darktop
                        cmp     tileCounter,    #1 wz
              if_e      jmp     #showpref
                        jmp     #showbright

darktop                 tjnz    docopy,         #showcopy
                        jmp     #showdark

afterline               mov     vscl,           invisibleScale
                        waitvid HSyncColors,    syncPixels
                        mov     docopy,         #0
                        djnz    tileCounter,    #showtop

                        add     tilesCounter,   #1
                        cmp     tilesCounter,   #80         wc,wz
              if_b      jmp     #tilesDisplay

                        mov     counter,        #11
                        wrlong  FPorchStatus,   syncIndicatorAddress

frontPorch              mov     vscl,           blankPixels
                        waitvid HSyncColors,    #0
                        mov     vscl,           invisibleScale
                        waitvid HSyncColors,    syncPixels
                        djnz    counter,        #frontPorch

                        mov     counter,        #2
                        wrlong  VSyncStatus,    syncIndicatorAddress

verticalSync            mov     vscl,           blankPixels
                        waitvid VSyncColors,    #0
                        mov     vscl,           invisibleScale
                        waitvid VSyncColors,    syncPixels
                        djnz    counter,        #verticalSync

                        mov     counter,        #31
                        wrlong  BPorchStatus,   syncIndicatorAddress

backPorch               mov     vscl,           blankPixels
                        waitvid HSyncColors,    #0

                        tjnz    flipped,        #:noswap
                        mov     flipped,        #1
                        rdlong  d0,             done_ptr
                        cmp     d0,             shown           wz
              if_e      jmp     #:noswap
                        mov     shown,          d0
                        rdlong  d0,             front_ptr
                        xor     d0,             #1              wz
                        wrlong  d0,             front_ptr
                        mov     pixbase,        frameStore
                        mov     palbase,        palStore
              if_nz     add     pixbase,        frameBytes
              if_nz     add     palbase,        paletteBytes
:noswap                 mov     vscl,           invisibleScale
                        waitvid HSyncColors,    syncPixels
                        djnz    counter,        #backPorch

                        mov     flipped,        #0
                        jmp     #loop


'' Bright lines read src. Dark lines read drk.
'' Window 1 rebuilds drk from src. Ten instructions, no Hub read.
showbright              mov     vscl,           visibleWide
                        mov     palette,        src0
                        or      palette,        HVSyncColors
                        movs    ldpal,          #src1
                        jmp     #showenter

showdark                mov     vscl,           visibleWide
                        mov     palette,        drk0
                        or      palette,        HVSyncColors
                        movs    ldpal,          #drk1

showenter               rdlong  pix,            ptr
                        add     ptr,            #4
                        mov     p1,             pix
                        shr     p1,             #8
                        movs    bssrc,          #src0
                        movd    bddrk,          #drk0
                        movs    bddrk,          #src0
                        movd    bsub,           #drk0
                        mov     chunks,         #16

tilelp                  waitvid palette,        pix
bssrc                   mov     d0,             0-0
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
bddrk                   mov     0-0,            0-0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
bsub                    sub     0-0,            d0
                        waitvid palette,        p1
                        mov     p2,             p1
                        shr     p2,             #8
ldpal                   mov     nextpal,        0-0
                        or      nextpal,        HVSyncColors
                        add     ldpal,          #1
                        add     bssrc,          #1
                        add     bddrk,          bothinc
                        add     bsub,           destinc
                        waitvid palette,        p2
                        mov     p3,             p2
                        shr     p3,             #8
                        rdlong  nextpix,        ptr
                        add     ptr,            #4
                        waitvid palette,        p3
                        mov     pix,            nextpix
                        mov     p1,             pix
                        shr     p1,             #8
                        mov     palette,        nextpal
                        djnz    chunks,         #tilelp
                        jmp     #afterline


'' Last bright line of an even band. Load pfptr into nxt and drk.
'' tilesDisplay leaves pfptr on the next line, or on this line at the tail.
showpref                mov     vscl,           visibleWide
                        mov     palette,        src0
                        or      palette,        HVSyncColors
                        movs    :ldp,           #src1
                        movd    :prd,           #nxt0
                        movs    :cps,           #nxt0
                        movd    :cps,           #drk0
                        rdlong  pix,            ptr
                        add     ptr,            #4
                        mov     p1,             pix
                        shr     p1,             #8
                        mov     chunks,         #16

:tilep                  waitvid palette,        pix
:prd                    rdlong  0-0,            pfptr
                        add     pfptr,          #4
:cps                    mov     0-0,            0-0
                        add     :prd,           destinc
                        add     :cps,           bothinc
                        waitvid palette,        p1
                        mov     p2,             p1
                        shr     p2,             #8
:ldp                    mov     nextpal,        0-0
                        or      nextpal,        HVSyncColors
                        add     :ldp,           #1
                        waitvid palette,        p2
                        mov     p3,             p2
                        shr     p3,             #8
                        rdlong  nextpix,        ptr
                        add     ptr,            #4
                        waitvid palette,        p3
                        mov     pix,            nextpix
                        mov     p1,             pix
                        shr     p1,             #8
                        mov     palette,        nextpal
                        djnz    chunks,         #:tilep
                        jmp     #afterline


'' First dark line of an odd band. drk is already dark. Copy nxt into src.
showcopy                mov     vscl,           visibleWide
                        mov     palette,        drk0
                        or      palette,        HVSyncColors
                        movs    :ldc,           #drk1
                        movs    :cmc,           #nxt0
                        movd    :cmc,           #src0
                        rdlong  pix,            ptr
                        add     ptr,            #4
                        mov     p1,             pix
                        shr     p1,             #8
                        mov     chunks,         #16

:tilec                  waitvid palette,        pix
:cmc                    mov     0-0,            0-0
                        add     :cmc,           bothinc
                        waitvid palette,        p1
                        mov     p2,             p1
                        shr     p2,             #8
:ldc                    mov     nextpal,        0-0
                        or      nextpal,        HVSyncColors
                        add     :ldc,           #1
                        waitvid palette,        p2
                        mov     p3,             p2
                        shr     p3,             #8
                        rdlong  nextpix,        ptr
                        add     ptr,            #4
                        waitvid palette,        p3
                        mov     pix,            nextpix
                        mov     p1,             pix
                        shr     p1,             #8
                        mov     palette,        nextpal
                        djnz    chunks,         #:tilec
                        jmp     #afterline


loadsrc                 movd    :lr,            #src0
                        mov     d0,             palLine
                        mov     chunks,         #16
:lr                     rdlong  0-0,            d0
                        add     d0,             #4
                        add     :lr,            destinc
                        djnz    chunks,         #:lr
loadsrc_ret             ret


'' drk already holds the bright bytes. Subtract $55 from each flagged byte.
builddark
                        mov     d0,             drk0
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk0,           d0
                        mov     d0,             drk1
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk1,           d0
                        mov     d0,             drk2
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk2,           d0
                        mov     d0,             drk3
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk3,           d0
                        mov     d0,             drk4
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk4,           d0
                        mov     d0,             drk5
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk5,           d0
                        mov     d0,             drk6
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk6,           d0
                        mov     d0,             drk7
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk7,           d0
                        mov     d0,             drk8
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk8,           d0
                        mov     d0,             drk9
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk9,           d0
                        mov     d0,             drk10
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk10,           d0
                        mov     d0,             drk11
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk11,           d0
                        mov     d0,             drk12
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk12,           d0
                        mov     d0,             drk13
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk13,           d0
                        mov     d0,             drk14
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk14,           d0
                        mov     d0,             drk15
                        and     d0,             flagpat
                        mov     d1,             d0
                        shl     d1,             #2
                        add     d1,             d0
                        mov     d0,             d1
                        shl     d0,             #4
                        add     d0,             d1
                        sub     drk15,           d0
builddark_ret           ret


invisibleScale          long    (12 << 12) + 256
visibleWide             long    (4 << 12) + 16
blankPixels             long    1024
syncPixels              long    $0F_FF_FF_F0
HSyncColors             long    $01_03_01_03
VSyncColors             long    $00_02_00_02
HVSyncColors            long    $03_03_03_03
flagpat                 long    $01010101
bothinc                 long    513
destinc                 long    512

FPorchStatus            long    %001 << 16 + 240
VSyncStatus             long    %011 << 16
BPorchStatus            long    %101 << 16

frameBytes              long    FB_BYTES
paletteBytes            long    PAL_BYTES
lineLimit               long    FB_H

directionState          long    0
videoState              long    0
frequencyState          long    0
syncIndicatorAddress    long    0
frameStore              long    0
palStore                long    0
ctrlStore               long    0

pixbase                 res     1
palbase                 res     1
front_ptr               res     1
done_ptr                res     1
shown                   res     1
flipped                 res     1
linePtr                 res     1
palLine                 res     1
ptr                     res     1
palette                 res     1
nextpal                 res     1
pix                     res     1
nextpix                 res     1
p1                      res     1
p2                      res     1
p3                      res     1
tilesCounter            res     1
tileCounter             res     1
counter                 res     1
chunks                  res     1
d0                      res     1
d1                      res     1
pfptr                   res     1
docopy                  res     1
src0                    res     1
src1                    res     1
src2                    res     1
src3                    res     1
src4                    res     1
src5                    res     1
src6                    res     1
src7                    res     1
src8                    res     1
src9                    res     1
src10                   res     1
src11                   res     1
src12                   res     1
src13                   res     1
src14                   res     1
src15                   res     1
drk0                    res     1
drk1                    res     1
drk2                    res     1
drk3                    res     1
drk4                    res     1
drk5                    res     1
drk6                    res     1
drk7                    res     1
drk8                    res     1
drk9                    res     1
drk10                   res     1
drk11                   res     1
drk12                   res     1
drk13                   res     1
drk14                   res     1
drk15                   res     1
nxt0                    res     1
nxt1                    res     1
nxt2                    res     1
nxt3                    res     1
nxt4                    res     1
nxt5                    res     1
nxt6                    res     1
nxt7                    res     1
nxt8                    res     1
nxt9                    res     1
nxt10                   res     1
nxt11                   res     1
nxt12                   res     1
nxt13                   res     1
nxt14                   res     1
nxt15                   res     1

                        fit     496
