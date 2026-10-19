'' Framebuffer program head. Compile a top in this directory.
'' That top defines SCENE_TRIANGLES, SCENE_PROBE, or SCENE_CUBE.
'' The display list is under scene/. The library objects stay in the parent directory.
'' The VGA cog scans a finished bitmap. A late frame repeats the last bitmap.
'' (C)2026 feilipu.
CON

  _clkmode      = XTAL1 + PLL16X
  _xinfreq      = 7_372_800

  DLIST_SIZE = 300

  WIDTH = render#WIDTH
  HEIGHT = render#NUM_LINES


OBJ
vga: "VJET_vUXM_vga_fb.spin"
render: "VJET_vUXM_rendering_fb.spin"
gl: "VJET_v01_displaylist.spin"
#ifndef SCENE_PROBE
font : "hexfont.spin"
#endif


VAR

long framecount, vga_status, dlist_ptr, boot
long go, front, done, stripe0, stripe1, stripe2, fixup, blend
long dlist1[DLIST_SIZE], dlist2[DLIST_SIZE]
long pix0[render#FB_LONGS]
long pix1[render#FB_LONGS]
long pal0[render#PAL_LONGS]
long pal1[render#PAL_LONGS]
long scratch[render#SCRATCH_LONGS]


#ifdef SCENE_CUBE
PUB main | ms
#else
PUB main
#endif

  longfill(@pix0, 0, render#FB_LONGS)
  longfill(@pix1, 0, render#FB_LONGS)
  longfill(@pal0, 0, render#PAL_LONGS)
  longfill(@pal1, 0, render#PAL_LONGS)
  longfill(@go, 0, 8)
#ifdef SCENE_PROBE
  blend := 1
#endif

  vga.start(16 / 8, @pix0, @pal0, @go, @vga_status)

  boot := 0
  render.start(0, 3, @scratch, @dlist_ptr, @pix0, @pal0, @go, @boot)
  render.start(1, 3, @scratch, @dlist_ptr, @pix0, @pal0, @go, @boot)
  render.start(2, 3, @scratch, @dlist_ptr, @pix0, @pal0, @go, @boot)

  gl.start(@dlist1, constant(DLIST_SIZE * 4))
#ifdef SCENE_CUBE
  ms := \draw
#else
  \draw
#endif
  gl.done
  dlist_ptr := @dlist1
  go := 1
  boot := 1

  repeat
    repeat until done == go
    framecount++
    if go & 1
      gl.start(@dlist2, constant(DLIST_SIZE * 4))
#ifdef SCENE_CUBE
      ms := \draw
#else
      \draw
#endif
      gl.done
      dlist_ptr := @dlist2
    else
      gl.start(@dlist1, constant(DLIST_SIZE * 4))
#ifdef SCENE_CUBE
      ms := \draw
#else
      \draw
#endif
      gl.done
      dlist_ptr := @dlist1
    go++


#ifdef SCENE_TRIANGLES
#define SCENE_FB 1
#include "scene/scene_triangles.spin"
#elseifdef SCENE_PROBE
#include "scene/scene_probe.spin"
#elseifdef SCENE_CUBE
#include "scene/scene_cube.spin"
#else
#error Define SCENE_TRIANGLES, SCENE_PROBE, or SCENE_CUBE before this file.
#endif
