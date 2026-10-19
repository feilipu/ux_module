'' Spinning triangles and one text shape. The beam-chase head and the bring-up include this file.
'' Beam chase and the framebuffer use this same picture.
'' Derived from the 2021 vjet_test demo, (C)2021 IRQsome Software.
'' (C)2026 feilipu.

#ifdef SCENE_FB
PRI draw
#else
PRI draw | cx,cy
#endif

gl.set_clip(0,HEIGHT<<16,0,WIDTH<<16)

gl.triangle(constant((WIDTH/2)<<16),constant(-HEIGHT<<16),constant(-WIDTH<<16),constant(HEIGHT<<16),constant(2*WIDTH<<16),constant(HEIGHT<<16),$ECEC)

gl.triangle(208<<16 + sin(0000+framecount<<5)*75,90<<16 + sin(2048+framecount<<5)*75,{
           }208<<16 + sin(2730+framecount<<5)*75,90<<16 + sin(4778+framecount<<5)*75,{
           }208<<16 + sin(5460+framecount<<5)*75,90<<16 + sin(7508+framecount<<5)*75, $0055)

gl.triangle(192<<16 + sin(0000+framecount<<5)*80,90<<16 + sin(2048+framecount<<5)*80,{
           }192<<16 + sin(2730+framecount<<5)*80,90<<16 + sin(4778+framecount<<5)*80,{
           }192<<16 + sin(5460+framecount<<5)*80,90<<16 + sin(7508+framecount<<5)*80, $5555)

gl.triangle(176<<16 + sin(0000+framecount<<5)*85,90<<16 + sin(2048+framecount<<5)*85,{
           }176<<16 + sin(2730+framecount<<5)*85,90<<16 + sin(4778+framecount<<5)*85,{
           }176<<16 + sin(5460+framecount<<5)*85,90<<16 + sin(7508+framecount<<5)*85, $55AA)

gl.triangle(160<<16 + sin(0000+framecount<<5)*90,90<<16 + sin(2048+framecount<<5)*90,{
           }160<<16 + sin(2730+framecount<<5)*90,90<<16 + sin(4778+framecount<<5)*90,{
           }160<<16 + sin(5460+framecount<<5)*90,90<<16 + sin(7508+framecount<<5)*90, $AAAA)


gl.triangle(128<<16 + sin(0000-framecount<<4)*500,90<<16 + sin(2048-framecount<<4)*500,{
           }128<<16 + sin(0100-framecount<<4)*500,90<<16 + sin(2148-framecount<<4)*500,{
           }128<<16                              ,90<<16                              , $C0C0)
gl.triangle(128<<16 + sin(0100-framecount<<4)*500,90<<16 + sin(2148-framecount<<4)*500,{
           }128<<16 + sin(0200-framecount<<4)*500,90<<16 + sin(2248-framecount<<4)*500,{
           }128<<16                              ,90<<16                              , $D0D0)
gl.triangle(128<<16 + sin(0200-framecount<<4)*500,90<<16 + sin(2248-framecount<<4)*500,{
           }128<<16 + sin(0300-framecount<<4)*500,90<<16 + sin(2348-framecount<<4)*500,{
           }128<<16                              ,90<<16                              , $F0F0)
gl.triangle(128<<16 + sin(0300-framecount<<4)*500,90<<16 + sin(2348-framecount<<4)*500,{
           }128<<16 + sin(0400-framecount<<4)*500,90<<16 + sin(2448-framecount<<4)*500,{
           }128<<16                              ,90<<16                              , $7474)
gl.triangle(128<<16 + sin(0400-framecount<<4)*500,90<<16 + sin(2448-framecount<<4)*500,{
           }128<<16 + sin(0500-framecount<<4)*500,90<<16 + sin(2548-framecount<<4)*500,{
           }128<<16                              ,90<<16                              , $3C3C)
gl.triangle(128<<16 + sin(0500-framecount<<4)*500,90<<16 + sin(2548-framecount<<4)*500,{
           }128<<16 + sin(0600-framecount<<4)*500,90<<16 + sin(2648-framecount<<4)*500,{
           }128<<16                              ,90<<16                              , $4848)


gl.triangle(144<<16 + sin(0000+framecount<<5)*95,90<<16 + sin(2048+framecount<<5)*95,{
           }144<<16 + sin(2730+framecount<<5)*95,90<<16 + sin(4778+framecount<<5)*95,{
           }144<<16 + sin(5460+framecount<<5)*95,90<<16 + sin(7508+framecount<<5)*95, $AAFF)

gl.triangle(128<<16 + sin(0000+framecount<<5)*100,90<<16 + sin(2048+framecount<<5)*100,{
           }128<<16 + sin(2730+framecount<<5)*100,90<<16 + sin(4778+framecount<<5)*100,{
           }128<<16 + sin(5460+framecount<<5)*100,90<<16 + sin(7508+framecount<<5)*100, $FFFF)

gl.text_centered(WIDTH>>1,192 + sin(0000+framecount<<6)~>12,0,2,string(" WOOO! SPINNING TRIANGLES!"),font.get,$FFFF)

#ifdef SCENE_FB
PUB sin(angle) : s
#else
PUB sin(angle) : s | c,z
#endif
              'angle: 0..8192 = 360deg
  s := angle
  if angle & $800
    s := -s
  s |= $E000>>1
  s <<= 1
  s := word[s]
  if angle & $1000
    s := -s                    ' return sin = -$FFFF..+$FFFF
