'' Test card. Included by src/ux_module_vjet.spin.
'' The circle turns clockwise. A later shape covers an earlier shape.
'' (C)2026 feilipu.

CON

  CARD_X        = 128                                   ' circle centre, pixels
  CARD_Y        = 120
  CARD_R        = 84                                    ' circle radius, pixels


PRI drawScene | i, a, sx, cx
{{Grey field, grid, pillars, then the circle. A later shape covers an earlier one.}}

  gl.set_clip (0, render#NUM_LINES << 16, 0, render#WIDTH << 16)
  gl.box (0, 0, render#WIDTH, render#NUM_LINES, $5757)
  gl.box (0, 8, render#WIDTH, 10, $FFFF)
  gl.box (0, 20, render#WIDTH, 22, $FFFF)
  gl.box (0, 214, render#WIDTH, 216, $FFFF)
  gl.box (0, 226, render#WIDTH, 228, $FFFF)
  gl.box (64, 0, 66, 34, $FFFF)
  gl.box (192, 0, 194, 34, $FFFF)
  gl.box (64, 206, 66, render#NUM_LINES, $FFFF)
  gl.box (192, 206, 194, render#NUM_LINES, $FFFF)
  gl.box (8, 0, 24, 60, $3333)
  gl.box (8, 60, 24, 120, $0F0F)
  gl.box (8, 120, 24, 180, $CFCF)
  gl.box (8, 180, 24, render#NUM_LINES, $A3A3)
  gl.box (232, 0, 248, 60, $E3E3)
  gl.box (232, 60, 248, 120, $0F0F)
  gl.box (232, 120, 248, 180, $9393)
  gl.box (232, 180, 248, render#NUM_LINES, $AFAF)

  a := (framecount << 2) & $1FFF
  sx := sin(a)
  cx := sin((a + 2048) & $1FFF)
  drawCap(sx, cx)
  quadRect(-24, -68, 24, -56, $0303, sx, cx)
  repeat i from 0 to 5
    bandQuad(-30, -12, i, i + 1, 6, barColour(i), sx, cx)
  bandQuad(-12, -2, 0, 1, 1, $0303, sx, cx)
  bandQuad(-2, 18, 0, 1, 1, $ABAB, sx, cx)
  drawBase(sx, cx)
  drawRed(sx, cx)


PRI drawCap(sx, cx) | a, b, c, d
{{White top of the circle. Vertices run clockwise from the apex.}}

  a := edgeX(-80)
  b := edgeX(-70)
  c := edgeX(-48)
  d := edgeX(-30)
  putVertex(0, 0, -CARD_R, sx, cx)
  putVertex(1, a, -80, sx, cx)
  putVertex(2, b, -70, sx, cx)
  putVertex(3, c, -48, sx, cx)
  putVertex(4, d, -30, sx, cx)
  putVertex(5, -d, -30, sx, cx)
  putVertex(6, -c, -48, sx, cx)
  putVertex(7, -b, -70, sx, cx)
  putVertex(8, -a, -80, sx, cx)
  gl.polygon(@polyXY, 9, $FFFF, 0)


PRI drawBase(sx, cx) | a, b, c, d
{{Yellow bottom of the circle. Vertices run clockwise.}}

  a := edgeX(18)
  b := edgeX(48)
  c := edgeX(68)
  d := edgeX(80)
  putVertex(0, -a, 18, sx, cx)
  putVertex(1, a, 18, sx, cx)
  putVertex(2, b, 48, sx, cx)
  putVertex(3, c, 68, sx, cx)
  putVertex(4, d, 80, sx, cx)
  putVertex(5, 0, CARD_R, sx, cx)
  putVertex(6, -d, 80, sx, cx)
  putVertex(7, -c, 68, sx, cx)
  putVertex(8, -b, 48, sx, cx)
  gl.polygon(@polyXY, 9, $F3F3, 0)


PRI drawRed(sx, cx)
{{Red block on the yellow bottom. The apex stays on the circle.}}

  putVertex(0, -16, 52, sx, cx)
  putVertex(1, 16, 52, sx, cx)
  putVertex(2, 12, 78, sx, cx)
  putVertex(3, 0, CARD_R, sx, cx)
  putVertex(4, -12, 78, sx, cx)
  gl.polygon(@polyXY, 5, $C3C3, 0)


PRI bandQuad(y0, y1, n0, n1, parts, colour, sx, cx) | x0, x1, s0, s1
{{One slice of a horizontal band. n0 and n1 are the fraction across the chord.}}

  x0 := edgeX(y0)
  x1 := edgeX(y1)
  s0 := x0 << 1
  s1 := x1 << 1
  putVertex(0, -x0 + (s0 * n0) / parts, y0, sx, cx)
  putVertex(1, -x0 + (s0 * n1) / parts, y0, sx, cx)
  putVertex(2, -x1 + (s1 * n1) / parts, y1, sx, cx)
  putVertex(3, -x1 + (s1 * n0) / parts, y1, sx, cx)
  gl.polygon(@polyXY, 4, colour, 0)


PRI quadRect(x0, y0, x1, y1, colour, sx, cx)
{{Axis-aligned rectangle in circle pixels, then rotated.}}

  putVertex(0, x0, y0, sx, cx)
  putVertex(1, x1, y0, sx, cx)
  putVertex(2, x1, y1, sx, cx)
  putVertex(3, x0, y1, sx, cx)
  gl.polygon(@polyXY, 4, colour, 0)


PRI putVertex(i, lx, ly, sx, cx)
{{Store one rotated vertex. Positive angle turns the card clockwise.}}

  polyXY[i * 2] := (CARD_X << 16) + ((cx * lx) - (sx * ly))
  polyXY[(i * 2) + 1] := (CARD_Y << 16) + ((sx * lx) + (cx * ly))


PRI edgeX(ly) : x | n
{{Half-width of the circle at local y. y is positive down.}}

  n := (CARD_R * CARD_R) - (ly * ly)
  if n < 1
    return 0
  x := isqrt(n)


PRI isqrt(n) : r | bit

  r := 0
  bit := $80
  repeat 8
    r |= bit
    if (r * r) > n
      r &= !bit
    bit >>= 1


PRI barColour(i) : c

  case i
    0: c := $F3F3
    1: c := $3F3F
    2: c := $3333
    3: c := $CFCF
    4: c := $C3C3
    5: c := $0F0F
    other: c := $FFFF


PRI sin(angle) : s
{{Hub ROM sine. 0 to 8191 is one turn. Result is -65535 to 65535.}}

  s := angle
  if angle & $800
    s := -s
  s |= $E000 >> 1
  s <<= 1
  s := word[s]
  if angle & $1000
    s := -s
