'' Stress picture for the eight-line renderer.
'' Polygons, scaled text, clip, lines, points, and stacked spans.
'' (C)2026 feilipu.

VAR

  long polyXY[16]


PRI draw | i, a, cx

  gl.set_clip(0, HEIGHT << 16, 0, WIDTH << 16)

  ' Tall field trap. The apex sits above line 0.
  gl.triangle(constant((WIDTH / 2) << 16), constant(-HEIGHT << 16), {
             }constant(-WIDTH << 16), constant(HEIGHT << 16), {
             }constant((2 * WIDTH) << 16), constant(HEIGHT << 16), $ECEC)

  ' Twelve bars share lines 96..144. That stack is one record each.
  repeat i from 0 to 11
    gl.box(12 + (i * 20), 96, 22 + (i * 20), 144, barcol(i))

  a := (framecount << 3) & $1FFF
  ngon(128, 70, 48, 8, a, $55AA)
  ngon(64, 180, 36, 6, (0 - a) & $1FFF, $AAFF)

  cx := 40 + ((sin(framecount << 4) * 20) ~> 16)
  gl.triangle(cx << 16, (-20) << 16, (cx - 2) << 16, 250 << 16, (cx + 2) << 16, 250 << 16, $C0C0)

  cx := 200 + ((sin(framecount << 5) * 8) ~> 16)
  gl.triangle(10 << 16, cx << 16, 246 << 16, (cx - 2) << 16, 246 << 16, (cx + 2) << 16, $3C3C)

  gl.triangle(80 << 16, (-30) << 16, 50 << 16, 50 << 16, 110 << 16, 50 << 16, $F0F0)
  gl.triangle(200 << 16, 200 << 16, 170 << 16, 260 << 16, 230 << 16, 260 << 16, $7474)
  gl.triangle((-20) << 16, 80 << 16, 20 << 16, 140 << 16, 40 << 16, 90 << 16, $4848)
  gl.triangle(240 << 16, 90 << 16, 270 << 16, 80 << 16, 236 << 16, 140 << 16, $D0D0)

  gl.triangle(30 << 16, 100 << 16, 20 << 16, 130 << 16, 50 << 16, 130 << 16, $F0F2)
  gl.triangle(90 << 16, 104 << 16, 70 << 16, 136 << 16, 110 << 16, 136 << 16, $66BB)
  gl.triangle(150 << 16, 108 << 16, 130 << 16, 140 << 16, 170 << 16, 140 << 16, $0055)
  gl.triangle(210 << 16, 100 << 16, 190 << 16, 132 << 16, 230 << 16, 132 << 16, $80C0)

  gl.line(16 << 16, 220 << 16, 120 << 16, 160 << 16, $FFFF)
  gl.line(16 << 16, 230 << 16, 120 << 16, 230 << 16, $FFFF)
  gl.line_triangle(210 << 16, 40 << 16, 240 << 16, 90 << 16, 180 << 16, 90 << 16, $FFFF)

  repeat i from 0 to 7
    gl.point(16 + (i * 12), 48 + ((sin((framecount << 5) + (i << 9)) * 12) ~> 16), $FFFF)

  repeat i from 0 to 5
    gl.box(200 + (i * 8), 12, 205 + (i * 8), 17, $5555)

  ' xscale 0 is a byte store. xscale 1 is a word. xscale 2 is a long.
  gl.text(8, 4, 0, 0, string("X0 BYTE"), font.get, $FFFF)
  gl.text(8, 16, 1, 0, string("X1 WORD"), font.get, $FFFF)
  gl.text(160, 4, 2, 0, string("X2"), font.get, $C0C0)
  gl.text_centered(WIDTH >> 1, 178, 0, 1, string("Y1 TALL"), font.get, $FFFF)
  gl.text(0 - ((framecount >> 1) // 80), 88, 0, 0, string("SCROLL CLIP"), font.get, $FFFF)


PRI ngon(cx, cy, r, n, a0, colour) | i, astep, ang

  astep := 8192 / n
  repeat i from 0 to n - 1
    ang := (a0 + (i * astep)) & $1FFF
    polyXY[i * 2] := (cx << 16) + (sin(ang + 2048) * r)
    polyXY[(i * 2) + 1] := (cy << 16) + (sin(ang) * r)
  gl.polygon(@polyXY, n, colour, 0)


PRI barcol(i) : c

  case i
    0:  c := $0055
    1:  c := $5555
    2:  c := $55AA
    3:  c := $AAAA
    4:  c := $AAFF
    5:  c := $FFFF
    6:  c := $1818
    7:  c := $C0C0
    8:  c := $66BB
    9:  c := $F0F2
    10: c := $7474
    other: c := $80C0


PUB sin(angle) : s

  s := angle
  if angle & $800
    s := -s
  s |= $E000 >> 1
  s <<= 1
  s := word[s]
  if angle & $1000
    s := -s
