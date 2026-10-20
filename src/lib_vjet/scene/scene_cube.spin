'' Eight vertices and twelve triangles. The beam-chase head includes this file.
'' RES draws the resident mesh. STR draws the same faces from a stream table.
'' Equal colour bytes stay solid on the eight-line scan.
'' (C)2026 feilipu.

CON

  HALF = 36
  CX = 128
  CY = 110


VAR

long sx[8], sy[8], sz[8]
long zc[12]
long stream[84]
byte order[12]
byte label[8]


PRI draw : ms | t0

  t0 := cnt
  project
  sort_faces
  gl.set_clip(0, HEIGHT << 16, 0, WIDTH << 16)
  if (framecount >> 6) & 1
    draw_stream
    bytemove(@label, string("STR "), 4)
  else
    draw_resident
    bytemove(@label, string("RES "), 4)
  ms := (cnt - t0) / (clkfreq / 1000)
  put_ms(ms)
  gl.text_centered(WIDTH >> 1, 200, 0, 2, @label, font.get, $FFFF)


'' Yaw follows the frame. Pitch stays near 30 degrees.
PRI project | i, a, s, c, ps, pc, x, y, z, xr, yr, zr

  a := framecount << 5
  s := sin(a)
  c := sin(a + $800)
  ps := sin($2AA)
  pc := sin($2AA + $800)
  repeat i from 0 to 7
    x := long[@vx][i]
    y := long[@vy][i]
    z := long[@vz][i]
    xr := (x * c - z * s) ~> 16
    zr := (x * s + z * c) ~> 16
    yr := (y * pc - zr * ps) ~> 16
    zr := (y * ps + zr * pc) ~> 16
    sx[i] := (CX + xr) << 16
    sy[i] := (CY - yr) << 16
    sz[i] := zr


PRI sort_faces | i, j, z, k, n

  repeat i from 0 to 11
    order[i] := i
    n := i * 3
    zc[i] := sz[byte[@fi][n]] + sz[byte[@fi][n + 1]] + sz[byte[@fi][n + 2]]
  repeat i from 1 to 11
    z := zc[i]
    k := order[i]
    j := i
    repeat while j > 0
      if zc[order[j - 1]] =< z
        quit
      order[j] := order[j - 1]
      j--
    order[j] := k


PRI draw_resident | i, n, a, b, c

  repeat i from 0 to 11
    n := order[i] * 3
    a := byte[@fi][n]
    b := byte[@fi][n + 1]
    c := byte[@fi][n + 2]
    gl.triangle(sx[a], sy[a], sx[b], sy[b], sx[c], sy[c], word[@fc][order[i]])


'' One record is six signed pixels and one colour. The wire size is 14 bytes.
PRI draw_stream | i, n, p, a, b, c

  repeat i from 0 to 11
    n := order[i] * 3
    p := i * 7
    a := byte[@fi][n]
    b := byte[@fi][n + 1]
    c := byte[@fi][n + 2]
    stream[p] := sx[a] ~> 16
    stream[p + 1] := sy[a] ~> 16
    stream[p + 2] := sx[b] ~> 16
    stream[p + 3] := sy[b] ~> 16
    stream[p + 4] := sx[c] ~> 16
    stream[p + 5] := sy[c] ~> 16
    stream[p + 6] := word[@fc][order[i]]
  repeat i from 0 to 11
    p := i * 7
    gl.triangle(stream[p] << 16, stream[p + 1] << 16, {
               } stream[p + 2] << 16, stream[p + 3] << 16, {
               } stream[p + 4] << 16, stream[p + 5] << 16, {
               } stream[p + 6])


PRI put_ms(ms) | p

  if ms > 999
    ms := 999
  p := @label + 4
  byte[p] := $30 + (ms / 100)
  byte[p + 1] := $30 + ((ms // 100) / 10)
  byte[p + 2] := $30 + (ms // 10)
  byte[p + 3] := 0


PUB sin(angle) : s

  s := angle
  if angle & $800
    s := -s
  s |= $E000 >> 1
  s <<= 1
  s := word[s]
  if angle & $1000
    s := -s


DAT

vx long -HALF,  HALF,  HALF, -HALF, -HALF,  HALF,  HALF, -HALF
vy long -HALF, -HALF,  HALF,  HALF, -HALF, -HALF,  HALF,  HALF
vz long -HALF, -HALF, -HALF, -HALF,  HALF,  HALF,  HALF,  HALF

fi byte 4, 5, 6,  4, 6, 7
    byte 1, 0, 3,  1, 3, 2
    byte 0, 4, 7,  0, 7, 3
    byte 5, 1, 2,  5, 2, 6
    byte 3, 7, 6,  3, 6, 2
    byte 0, 1, 5,  0, 5, 4

fc word $C0C0, $C0C0, $5555, $5555, $8080, $8080
    word $AAAA, $AAAA, $FFFF, $FFFF, $ECEC, $ECEC
