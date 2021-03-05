CON

  _clkmode      = XTAL1 + PLL16X
  _xinfreq      = 7_372_800

  DLIST_SIZE = 900

  WIDTH = 256
  HEIGHT = 240
  
OBJ
vga: "VJET_vUXM_vga.spin"
render: "VJET_vUXM_rendering.spin"
gl: "VJET_v01_displaylist.spin"
font : "hexfont.spin"


VAR

long framecount,vga_status,dlist_ptr
long dlist1[DLIST_SIZE],dlist2[DLIST_SIZE] 
long linebuffers[(256*8)/4]                

PUB main | i,j,x,j2

vga.start(16/8,@linebuffers,@vga_status)



dlist_ptr:=$8080
x:=false
render.start(0,3,@linebuffers,@dlist_ptr,@vga_status,@x)
render.start(1,3,@linebuffers,@dlist_ptr,@vga_status,@x)
render.start(2,3,@linebuffers,@dlist_ptr,@vga_status,@x)
x:=true
  
repeat
  Vblank
  if framecount&1
    dlist_ptr:=@dlist1
    gl.start(@dlist2,constant(DLIST_SIZE*4))
  else
    dlist_ptr:=@dlist2
    gl.start(@dlist1,constant(DLIST_SIZE*4))

  \draw
  gl.done
  framecount++


PRI draw | cx,cy

gl.set_clip(0,HEIGHT<<16,0,WIDTH<<16)


gl.triangle(192<<16 + sin(0000+framecount<<5)*80,90<<16 + sin(2048+framecount<<5)*80,{
           }192<<16 + sin(2730+framecount<<5)*80,90<<16 + sin(4778+framecount<<5)*80,{
           }192<<16 + sin(5460+framecount<<5)*80,90<<16 + sin(7508+framecount<<5)*80, $5555)

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


gl.triangle(128<<16 + sin(0000+framecount<<5)*100,90<<16 + sin(2048+framecount<<5)*100,{
           }128<<16 + sin(2730+framecount<<5)*100,90<<16 + sin(4778+framecount<<5)*100,{
           }128<<16 + sin(5460+framecount<<5)*100,90<<16 + sin(7508+framecount<<5)*100, $FFFF)       

gl.text_centered(WIDTH>>1,200,0,2,string(" WOOO! SPINNING TRIANGLES!"),font.get,$FFFF)
   
PUB sin(angle) : s | c,z
              'angle: 0..8192 = 360deg
  s := angle
  if angle & $800
    s := -s
  s |= $E000>>1
  s <<= 1
  s := word[s]
  if angle & $1000
    s := -s                    ' return sin = -$FFFF..+$FFFF

PUB Vblank

repeat while vga_status&$01_00_00
repeat until vga_status&$01_00_00
