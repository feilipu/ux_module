'' Framebuffer triangle demo. Same scene as vjet_test.
'' The VGA cog scans a finished bitmap. A late frame repeats.
'' No ACIA cog. No FTDI cog. Load this only when the bench is free.
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
font : "hexfont.spin"


VAR

long framecount, vga_status, dlist_ptr, boot
long go, front, done, stripe0, stripe1, stripe2, fixup
long dlist1[DLIST_SIZE], dlist2[DLIST_SIZE]
long pix0[render#FB_LONGS]
long pix1[render#FB_LONGS]
long pal0[render#PAL_LONGS]
long pal1[render#PAL_LONGS]
long scratch[render#SCRATCH_LONGS]


PUB main

  longfill(@pix0, 0, render#FB_LONGS)
  longfill(@pix1, 0, render#FB_LONGS)
  longfill(@pal0, 0, render#PAL_LONGS)
  longfill(@pal1, 0, render#PAL_LONGS)
  longfill(@go, 0, 7)

  vga.start(16 / 8, @pix0, @pal0, @go, @vga_status)

  boot := 0
  render.start(0, 3, @scratch, @dlist_ptr, @pix0, @pal0, @go, @boot)
  render.start(1, 3, @scratch, @dlist_ptr, @pix0, @pal0, @go, @boot)
  render.start(2, 3, @scratch, @dlist_ptr, @pix0, @pal0, @go, @boot)

  gl.start(@dlist1, constant(DLIST_SIZE * 4))
  \draw
  gl.done
  dlist_ptr := @dlist1
  go := 1
  boot := 1

  repeat
    repeat until done == go
    framecount++
    if go & 1
      gl.start(@dlist2, constant(DLIST_SIZE * 4))
      \draw
      gl.done
      dlist_ptr := @dlist2
    else
      gl.start(@dlist1, constant(DLIST_SIZE * 4))
      \draw
      gl.done
      dlist_ptr := @dlist1
    go++


PRI draw

  gl.set_clip(0, HEIGHT << 16, 0, WIDTH << 16)

  gl.triangle(constant((WIDTH / 2) << 16), constant(-HEIGHT << 16), constant(-WIDTH << 16), constant(HEIGHT << 16), constant((2 * WIDTH) << 16), constant(HEIGHT << 16), $ECEC)

  gl.triangle(208 << 16 + sin(0000 + framecount << 5) * 75, 90 << 16 + sin(2048 + framecount << 5) * 75, {
             } 208 << 16 + sin(2730 + framecount << 5) * 75, 90 << 16 + sin(4778 + framecount << 5) * 75, {
             } 208 << 16 + sin(5460 + framecount << 5) * 75, 90 << 16 + sin(7508 + framecount << 5) * 75, $0055)

  gl.triangle(192 << 16 + sin(0000 + framecount << 5) * 80, 90 << 16 + sin(2048 + framecount << 5) * 80, {
             } 192 << 16 + sin(2730 + framecount << 5) * 80, 90 << 16 + sin(4778 + framecount << 5) * 80, {
             } 192 << 16 + sin(5460 + framecount << 5) * 80, 90 << 16 + sin(7508 + framecount << 5) * 80, $5555)

  gl.triangle(176 << 16 + sin(0000 + framecount << 5) * 85, 90 << 16 + sin(2048 + framecount << 5) * 85, {
             } 176 << 16 + sin(2730 + framecount << 5) * 85, 90 << 16 + sin(4778 + framecount << 5) * 85, {
             } 176 << 16 + sin(5460 + framecount << 5) * 85, 90 << 16 + sin(7508 + framecount << 5) * 85, $55AA)

  gl.triangle(160 << 16 + sin(0000 + framecount << 5) * 90, 90 << 16 + sin(2048 + framecount << 5) * 90, {
             } 160 << 16 + sin(2730 + framecount << 5) * 90, 90 << 16 + sin(4778 + framecount << 5) * 90, {
             } 160 << 16 + sin(5460 + framecount << 5) * 90, 90 << 16 + sin(7508 + framecount << 5) * 90, $AAAA)

  gl.triangle(128 << 16 + sin(0000 - framecount << 4) * 500, 90 << 16 + sin(2048 - framecount << 4) * 500, {
             } 128 << 16 + sin(0100 - framecount << 4) * 500, 90 << 16 + sin(2148 - framecount << 4) * 500, {
             } 128 << 16, 90 << 16, $C0C0)
  gl.triangle(128 << 16 + sin(0100 - framecount << 4) * 500, 90 << 16 + sin(2148 - framecount << 4) * 500, {
             } 128 << 16 + sin(0200 - framecount << 4) * 500, 90 << 16 + sin(2248 - framecount << 4) * 500, {
             } 128 << 16, 90 << 16, $D0D0)
  gl.triangle(128 << 16 + sin(0200 - framecount << 4) * 500, 90 << 16 + sin(2248 - framecount << 4) * 500, {
             } 128 << 16 + sin(0300 - framecount << 4) * 500, 90 << 16 + sin(2348 - framecount << 4) * 500, {
             } 128 << 16, 90 << 16, $F0F0)
  gl.triangle(128 << 16 + sin(0300 - framecount << 4) * 500, 90 << 16 + sin(2348 - framecount << 4) * 500, {
             } 128 << 16 + sin(0400 - framecount << 4) * 500, 90 << 16 + sin(2448 - framecount << 4) * 500, {
             } 128 << 16, 90 << 16, $7474)
  gl.triangle(128 << 16 + sin(0400 - framecount << 4) * 500, 90 << 16 + sin(2448 - framecount << 4) * 500, {
             } 128 << 16 + sin(0500 - framecount << 4) * 500, 90 << 16 + sin(2548 - framecount << 4) * 500, {
             } 128 << 16, 90 << 16, $3C3C)
  gl.triangle(128 << 16 + sin(0500 - framecount << 4) * 500, 90 << 16 + sin(2548 - framecount << 4) * 500, {
             } 128 << 16 + sin(0600 - framecount << 4) * 500, 90 << 16 + sin(2648 - framecount << 4) * 500, {
             } 128 << 16, 90 << 16, $4848)

  gl.triangle(144 << 16 + sin(0000 + framecount << 5) * 95, 90 << 16 + sin(2048 + framecount << 5) * 95, {
             } 144 << 16 + sin(2730 + framecount << 5) * 95, 90 << 16 + sin(4778 + framecount << 5) * 95, {
             } 144 << 16 + sin(5460 + framecount << 5) * 95, 90 << 16 + sin(7508 + framecount << 5) * 95, $AAFF)

  gl.triangle(128 << 16 + sin(0000 + framecount << 5) * 100, 90 << 16 + sin(2048 + framecount << 5) * 100, {
             } 128 << 16 + sin(2730 + framecount << 5) * 100, 90 << 16 + sin(4778 + framecount << 5) * 100, {
             } 128 << 16 + sin(5460 + framecount << 5) * 100, 90 << 16 + sin(7508 + framecount << 5) * 100, $FFFF)

  gl.text_centered(WIDTH >> 1, 192 + sin(0000 + framecount << 6) ~> 12, 0, 2, string(" WOOO! SPINNING TRIANGLES!"), font.get, $FFFF)


PUB sin(angle) : s
  s := angle
  if angle & $800
    s := -s
  s |= $E000 >> 1
  s <<= 1
  s := word[s]
  if angle & $1000
    s := -s
