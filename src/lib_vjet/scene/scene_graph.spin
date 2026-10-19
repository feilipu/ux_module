'' Boxes, a price line, and labels. Included by the beam-chase head.
'' Derived from the 2021 graphtest demo, (C)2021 IRQsome Software.
'' (C)2026 feilipu.

PRI draw | i,j,cx,cy,cx2,cy2,col

gl.set_clip(0,HEIGHT<<16,0,WIDTH<<16)

repeat i from 0 to 4
  repeat j from 0 to 4
    if (i^j)&1
      col:= $5555
    else
      col:= $AAAA
    gl.box(cx:=08+i*40,cy:=20+j*40,cx+40,cy+40,col)

repeat i from @stockdata to @stockdata_end-16 step 8
  cx  := (10+long[i][0]*5)<<16
  cy  := (220-long[i][1]/200)<<16
  cx2 := (10+long[i][2]*5)<<16
  cy2 := (220-long[i][3]/200)<<16
  'gl.point(28+cx,215-cy,$C0C0)
  gl.line(cx,cy,cx2,cy2,$C0C0)

repeat i from @stockdata to @stockdata_end-8 step 8
  cx  := (10+long[i][0]*5)<<16
  cy  := (220-long[i][1]/200)<<16
  gl.point(cx~>16,cy~>16,$FFFF)

gl.text(20,10,0,0,string("STOCK PRICE HISTORY"),font.get,$FFFF)
gl.text(207,17,0,0,string("-400"),font.get,$FFFF)
gl.text(207,215,0,0,string("- 0"),font.get,$FFFF)
gl.text(5,225,0,0,string("JAN 21"),font.get,$FFFF)
gl.text(190,225,0,0,string("MAR 02"),font.get,$FFFF)

DAT

stockdata
long 0,round(43.029999*100.0)
long 1,round(65.010002*100.0)
long 4,round(76.790001*100.0)
long 5,round(147.979996*100.0)
long 6,round(347.510010*100.0)
long 7,round(193.600006*100.0)
long 8,round(325.000000*100.0)
long 11,round(225.000000*100.0)
long 12,round(90.000000*100.0)
long 13,round(92.410004*100.0)
long 14,round(53.500000*100.0)
long 15,round(63.770000*100.0)
long 18,round(60.000000*100.0)
long 19,round(50.310001*100.0)
long 20,round(51.200001*100.0)
long 21,round(51.099998*100.0)
long 22,round(52.400002*100.0)
long 26,round(49.509998*100.0)
long 27,round(45.939999*100.0)
long 28,round(40.689999*100.0)
long 29,round(40.590000*100.0)
long 32,round(46.000000*100.0)
long 33,round(44.970001*100.0)
long 34,round(91.709999*100.0)
long 35,round(108.730003*100.0)
long 36,round(101.739998*100.0)
long 39,round(120.400002*100.0)
stockdata_end
