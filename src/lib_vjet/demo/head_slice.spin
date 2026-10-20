'' Beam-chase program head. Compile a top in this directory.
'' That top defines SCENE_TRIANGLES, SCENE_GRAPH, SCENE_PROBE,
'' SCENE_CARD, or SCENE_STRESS.
'' WITH_ACIA, WITH_FTDI, and WITH_SPIN_COG add those cogs.
'' The display list is under scene/. The library objects stay in the parent directory.
'' Derived from the 2021 vjet_test demo, (C)2021 IRQsome Software.
'' (C)2026 feilipu.
CON

  _clkmode      = XTAL1 + PLL16X
  _xinfreq      = 7_372_800

#ifdef SCENE_TRIANGLES
  DLIST_SIZE = 900
#elseifdef SCENE_GRAPH
  DLIST_SIZE = 500
#elseifdef SCENE_PROBE
  DLIST_SIZE = 160
#elseifdef SCENE_CARD
  DLIST_SIZE = 400
#elseifdef SCENE_STRESS
  DLIST_SIZE = 500
#else
#error Define SCENE_TRIANGLES, SCENE_GRAPH, SCENE_PROBE, SCENE_CARD, or SCENE_STRESS before this file.
  DLIST_SIZE = 900
#endif

  WIDTH = render#WIDTH
  HEIGHT = render#NUM_LINES


OBJ
vga: "VJET_vUXM_vga.spin"
render: "VJET_vUXM_rendering.spin"
gl: "VJET_v01_displaylist.spin"
#ifndef SCENE_PROBE
font : "hexfont.spin"
#endif
#ifdef WITH_ACIA
acia : "acia_rc2014.spin"
#endif
#ifdef WITH_FTDI
term : "terminal_ftdi.spin"
#endif


VAR

long framecount,vga_status,dlist_ptr
long dlist1[DLIST_SIZE],dlist2[DLIST_SIZE]
long linebuffers[(WIDTH*render#LINE_BUFFERS)/4]
#ifdef WITH_SPIN_COG
long spinStack[32]
#endif


PUB main | i,j,x,j2

#ifdef WITH_FTDI
term.start(115200)
#endif
vga.start(16/8,@linebuffers,@vga_status)

dlist_ptr:=$8080
x:=false
render.start(0,3,@linebuffers,@dlist_ptr,@vga_status,@x)
render.start(1,3,@linebuffers,@dlist_ptr,@vga_status,@x)
render.start(2,3,@linebuffers,@dlist_ptr,@vga_status,@x)
x:=true

#ifdef WITH_ACIA
acia.start(acia#PORT_80)
outa[acia#RESET_PIN_NUM]~
dira[acia#RESET_PIN_NUM]~~
waitcnt(clkfreq/1000 + cnt)
dira[acia#RESET_PIN_NUM]~
#endif

#ifdef WITH_SPIN_COG
if cognew(spinLoop, @spinStack) < 0
  repeat
#endif

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


#ifdef SCENE_TRIANGLES
#include "scene/scene_triangles.spin"
#elseifdef SCENE_GRAPH
#include "scene/scene_graph.spin"
#elseifdef SCENE_PROBE
#include "scene/scene_probe.spin"
#elseifdef SCENE_CARD
#include "scene/scene_card.spin"
PRI draw
  drawScene
#elseifdef SCENE_STRESS
#include "scene/scene_stress.spin"
#else
#error Define SCENE_TRIANGLES, SCENE_GRAPH, SCENE_PROBE, SCENE_CARD, or SCENE_STRESS before this file.
#endif


#ifdef WITH_SPIN_COG
PRI spinLoop | n

repeat
  n += long[@framecount]
#endif


PUB Vblank

repeat while vga_status & $01_00_00
repeat until vga_status & $01_00_00
