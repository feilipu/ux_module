'' Framebuffer probe. Same cogs and stripe rule as demo/vjet_fb.spin.
'' The scene checks motion, crossings, and depth order.
'' No ACIA cog. No FTDI cog.
''
'' Each frame draws 1 box and 9 triangles.
'' The box stores 16 bytes. Each triangle is flat and stores 36 bytes.
'' The list stores 340 bytes. Each list is 1200 bytes.
''
'' blend is 1. Bit 1 of a colour asks for the 50 percent mix.
'' Glass colours are $55AA, $66BB, $AAFF, and $F0F2.
'' Solid colours are $1818, $C0C0, $7474, $80C0, $0055, and $4848.
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


VAR

long framecount, vga_status, dlist_ptr, boot
long go, front, done, stripe0, stripe1, stripe2, fixup, blend
long dlist1[DLIST_SIZE], dlist2[DLIST_SIZE]
long pix0[render#FB_LONGS]
long pix1[render#FB_LONGS]
long pal0[render#PAL_LONGS]
long pal1[render#PAL_LONGS]
long scratch[render#SCRATCH_LONGS]
long ox[4], oy[4], oz[4], oc[4]


PUB main

  longfill(@pix0, 0, render#FB_LONGS)
  longfill(@pix1, 0, render#FB_LONGS)
  longfill(@pal0, 0, render#PAL_LONGS)
  longfill(@pal1, 0, render#PAL_LONGS)
  longfill(@go, 0, 8)
  blend := 1

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


PRI draw | i, t

  gl.set_clip(0, HEIGHT << 16, 0, WIDTH << 16)
  gl.box(0, 0, WIDTH, HEIGHT, $1818)

  place_orbit

  i := 0
  repeat 4
    if oz[i] => 0
      quit
    tri(ox[i], oy[i], 16, 18, oc[i])
    i++

  t := bounce(150)
  tri((24 + t) << 16, 118 << 16, 26, 11, $55AA)

  t := bounce(150)
  tri(72 << 16, (30 + t) << 16, 14, 16, $C0C0)

  t := bounce(160)
  tri((16 + t) << 16, (200 - t) << 16, 16, 14, $66BB)

  t := bounce(110)
  tri((28 + t) << 16, (196 + (t ~> 3)) << 16, 18, 12, $AAFF)
  tri((210 - t) << 16, (214 - (t ~> 3)) << 16, 18, 12, $7474)

  t := bounce(36)
  tri((168 + t) << 16, 22 << 16, 12, 8, $80C0)

  repeat while i < 4
    tri(ox[i], oy[i], 16, 18, oc[i])
    i++


'' Four bodies on a shallow ellipse. z is the depth. Negative is far.
PRI place_orbit | i, a

  oc[0] := $0055
  oc[1] := $F0F2
  oc[2] := $AAFF
  oc[3] := $4848
  repeat i from 0 to 3
    a := (framecount << 4) + (i << 11)
    ox[i] := (128 << 16) + (sin(a + $800) * 70)
    oy[i] := (118 << 16) + (sin(a) * 10)
    oz[i] := sin(a)
  sort_orbit


PRI sort_orbit | i, j, zx, xx, yx, cx

  repeat i from 1 to 3
    zx := oz[i]
    xx := ox[i]
    yx := oy[i]
    cx := oc[i]
    j := i
    repeat while j > 0
      if oz[j - 1] =< zx
        quit
      oz[j] := oz[j - 1]
      ox[j] := ox[j - 1]
      oy[j] := oy[j - 1]
      oc[j] := oc[j - 1]
      j--
    oz[j] := zx
    ox[j] := xx
    oy[j] := yx
    oc[j] := cx


'' x and y are 16.16. hx and hy are pixels.
PRI tri(x, y, hx, hy, colour)

  gl.triangle(x, y - (hy << 16), x - (hx << 16), y + (hy << 16), x + (hx << 16), y + (hy << 16), colour)


PRI bounce(span) : t | n

  n := span << 1
  t := framecount // n
  if t => span
    t := n - t


PUB sin(angle) : s

  s := angle
  if angle & $800
    s := -s
  s |= $E000 >> 1
  s <<= 1
  s := word[s]
  if angle & $1000
    s := -s
