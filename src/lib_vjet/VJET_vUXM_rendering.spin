'' VECTORJET for UX Module (based on v1.0)
'' Special version, don't re-use if you don't know what you're doing
'' (C)2021 IRQsome Software
'' Rendering Cog code 

CON

  WIDTH = 256   
  NUM_LINES = 240
  LINE_BUFFERS = 8             '' Hub slots; must match VGA tile wrap (line & 7)
  SPAN_MAX = 24                '' records kept for one scan line
'' One box, point, line, polygon, or text shape uses one record.
'' A shape after these 24 records on that line is skipped.

  Last_Scanline = NUM_LINES-1 ''final scanline for a frame

  Sfield = 0
  DField = 9


'' Display list format - shape header  (8 bytes)
'' WORD pointer to next shape or null
'' BYTE renderer sync line
'' BYTE shape type
'' WORD start scanline
'' WORD end scanline

'' Shape type 1 header - trapezoid stack (16 bytes)
'' LONG current left edge     '' top fixup writes these
'' LONG current right edge    '' scan lines recompute from the initial edges
'' LONG initial left edge
'' LONG initial right edge

'' One trapezoid  (12 bytes)
'' WORD height
'' WORD colors
'' LONG left slope
'' LONG right slope

'' Shape type 2 header - box (8 bytes)
'' WORD left edge
'' WORD right edge
'' WORD colors
'' WORD unused 

'' Shape type 3 header - text (12 bytes)
'' BYTE padding
'' BYTE scale: bits 0..4 : Y scale (log2), bits 5..6 X scale
'' WORD font pointer
'' WORD string pointer
'' WORD colors
'' WORD left x
'' WORD unused                
 
#1
SHP_TRAPSTACK         ' Shape type 1 header - trapezoid stack (16 bytes)
SHP_BOX               ' Shape type 2 header - box (8 bytes)
SHP_TEXT              ' Shape type 3 header - text (12 bytes)


VAR
  long rendcog[8]
  long rendcount

PUB start(cognum,totalcogs,scanbuffer,dlistPtrAdr,videoSync,readyptr)
'' Start one rendering cog. Call once per cog with cognum 0..totalcogs-1.
'' Copies the five DAT parameters then cognew. Wait so the hub image is taken
'' before the next start() overwrites those longs.
  longmove(@cognumber,@cognum,5)
  result := cognew(@Entry, readyptr)
  if result => 0
    if rendcount < 8
      rendcog[rendcount++] := result
  repeat 10000
  return result => 0

PUB stop | i
'' Stop every rendering cog this object started.
  repeat i from 0 to rendcount-1
    cogstop(rendcog[i])
  rendcount := 0

PUB Return_Address ''used to get address where assembly code is so we can re-purpose space
    return(@Entry)


DAT
        org
Entry
cognumber               long -1 ''which COG this rendering COG is
total_cogs              long -1 ''how many rendering COGs there are on total
scanlines               long -1 ''scanline buffer address
dlist_ptr_adr           long -1 
request_scanline        long -1 ''next scanline to render                                                                                        

''Note: Init code gets reuses as variables, thus the labels
a0      mov a0, Par  ''read parameter
d0      rdbyte currentscanline, a0 wz''is ready?
d1 if_z jmp #d0 'if not, repeat
  

'        rdlong Tiles_Adr, tile_adr ''read address of where tiles are at

''Main loop for renderer
new_frame
''wait until we hit scanline 0 so we can start with a fresh frame
:waitloop
        rdword currentrequest, request_scanline wz
if_nz   jmp #:waitloop

        mov currentscanline, cognumber ''reset current scanline for COG
        mov span_ready,#0

        rdword dlist_base, dlist_ptr_adr  '' read adress of display list
        'wrword dlist_base, dlist_in_use
        '{
'' fixup shapes clipped by top edge of screen (negative ystart)
        mov init_share,cognumber ' we only handle every Nth fixup
        mov dlist_next,dlist_base
        jmp #:nextshape        
        
:shapeloop
        mov dlist_ptr,dlist_next
        rdword dlist_next,dlist_ptr
        add dlist_ptr,#4

        rdword poly_top,dlist_ptr ' get start line
        shl poly_top,#16 ' sign extend
        cmps poly_top,#0 wc,wz ' negative start?
if_ae   jmp #:nextshape
        sar poly_top,#16 'continue sign extend
        sub init_share,#1 wc ' should this cog handle this line?
if_nc   jmp #:nextshape
        mov init_share,#0
           
        sub dlist_ptr,#2
        mov poly_syncptr,dlist_ptr
        add dlist_ptr,#1
       
        rdbyte shape_type,dlist_ptr               
        add dlist_ptr,#5

        cmp shape_type,#SHP_TRAPSTACK wz ' other shape types don't need fixup
if_ne   jmp #:nextshape_sync


        ' read initial edges
        mov poly_edgebuf,dlist_ptr
        add dlist_ptr,#8
        rdlong poly_left,dlist_ptr
        add dlist_ptr,#4
        rdlong poly_right,dlist_ptr
        add dlist_ptr,#4

        neg init_lines,poly_top

        ' iterate through trapezoids above Y0
        ' and premultiply
        
:traplp rdword trap_lines,dlist_ptr

        add dlist_ptr,#4 ' skip over colors 
        
        rdlong v1,dlist_ptr 'get left slope
        add dlist_ptr,#4
        mov v2,trap_lines
        max v2,init_lines
        call #newmult
        adds poly_left,vRes        

        
        rdlong v1,dlist_ptr 'get right slope
        add dlist_ptr,#4
        mov v2,trap_lines
        max v2,init_lines
        call #newmult
        adds poly_right,vRes  

        sub init_lines,trap_lines wc
if_nc   jmp #:traplp
            

        ' write back edges
        wrlong poly_left,poly_edgebuf
        add poly_edgebuf,#4
        wrlong poly_right,poly_edgebuf
:nextshape_sync
        ' write sync
        wrbyte zero,poly_syncptr
:nextshape
        tjnz dlist_next,#:shapeloop             
        '}

'' ==================================
'' ACTUAL LINE RENDERING STARTS HERE!
'' ==================================                 
setup_line
        tjnz span_ready,#:paint
        mov prep_line,currentscanline
        jmpret span_ret,#:build_spans
:paint
        mov span_ready,#0
        mov display_base,scanlines
        mov d0,currentscanline
        and d0,#7
        shl d0,#8
        add display_base,d0

        ' Fill first. A full-width first span supplies that colour.
        mov span_color,black
        mov span_i,#0
        tjz span_count,#:fill
        call #load_rec
        tjnz rec_text,#:fill
        tjnz poly_left,#:fill
        cmp poly_right,#WIDTH wz
if_ne   jmp #:fill
        mov d0,poly_color
        mov span_color,d0
        shl d0,#8
        or span_color,d0
        mov d0,span_color
        shl d0,#16
        or span_color,d0
        mov span_i,#1
:fill
        mov pixel_ptr,display_base
        mov pixel_iter,#WIDTH/4
:fillp  wrlong span_color,pixel_ptr
        add pixel_ptr,#4
        djnz pixel_iter,#:fillp

:sloop  cmp span_i,span_count wc
if_ae   jmp #:scanline_finished
        call #load_rec
        tjnz rec_text,#:textshape
        shl poly_left,#16
        shl poly_right,#16
        call #draw_span
:textdone
        add span_i,#1
        jmp #:sloop

' Build prep_line into cog records. No pixel writes.
' A text shape stores its list address among the spans.
' Enter with jmpret span_ret. Return with jmp span_ret.
:build_spans
        mov currentscanline_haxx,prep_line
        add currentscanline_haxx,#1
        shl currentscanline_haxx,#16
        test prep_line,#1 wc
        muxc coloroffset,#1
        mov span_count,#0
        mov dlist_next,dlist_base
        jmp #:nextshape

:shapeloop
        mov dlist_ptr,dlist_next
        rdword dlist_next,dlist_ptr

        add dlist_ptr,#4
        rdlong poly_top,dlist_ptr ' poly_bottom in top half. yes it's confusing
        cmp poly_top,currentscanline_haxx wc
if_b    jmp #:nextshape

        mov poly_bottom,poly_top
        shl poly_top,#16
        cmps poly_top,currentscanline_haxx wc
if_ae   jmp #:nextshape
        sar poly_top,#16
        sar poly_bottom,#16

        sub dlist_ptr,#2

        ' Each cog owns every third line.
        ' Rebuild both edges from the initial edges and the slopes.
        ' Do not wait for another render cog. Do not write the edges back.
        add dlist_ptr,#1
        rdbyte shape_type,dlist_ptr
        add dlist_ptr,#5 ' move dlist ptr to start of shape data

        cmp shape_type,#SHP_TRAPSTACK+1 wc
if_ae   jmp #:othershapes

        add dlist_ptr,#8 ' skip the current edges
        rdlong poly_left,dlist_ptr
        add dlist_ptr,#4
        rdlong poly_right,dlist_ptr
        add dlist_ptr,#4
        mov trap_lines,prep_line
        sub trap_lines,poly_top

:traplp rdword d0,dlist_ptr wz
if_z    jmp #:nextshape
        cmp trap_lines,d0 wc
if_b    jmp #:thistrap
        add dlist_ptr,#4
        rdlong v1,dlist_ptr
        mov v2,d0
        call #satmul
        adds poly_left,vRes
        add dlist_ptr,#4
        rdlong v1,dlist_ptr
        mov v2,d0
        call #satmul
        adds poly_right,vRes
        sub trap_lines,d0
        add dlist_ptr,#4
        jmp #:traplp

:thistrap
        add dlist_ptr,coloroffset ' 2 or 3
        rdbyte poly_color,dlist_ptr
        sub dlist_ptr,coloroffset
        add dlist_ptr,#4
        rdlong v1,dlist_ptr
        mov v2,trap_lines
        tjz v2,#:leftready
        call #satmul
        adds poly_left,vRes
:leftready
        add dlist_ptr,#4
        rdlong v1,dlist_ptr
        mov v2,trap_lines
        tjz v2,#:rightready
        call #satmul
        adds poly_right,vRes
:rightready
        call #store_span
        jmp #:nextshape

:nextshape_sync

 
:nextshape
        tjnz dlist_next,#:shapeloop
        jmp span_ret
        '}        
        
        'uncomment to enable diagonal line that aids in debugging
        {          
        mov d0,currentscanline
        and d0,#255
        add d0,display_base
        wrbyte white,d0
        '} 

''scanline rendering is finished, wait until next linebuffer is available
:scanline_finished
'' Record the next line while this cog waits.
'' The slot write stays behind the same 7-line lead.
        mov prep_line,currentscanline
        add prep_line,total_cogs
        cmp prep_line,#Last_Scanline wc,wz
if_a    jmp #:linewait
        jmpret span_ret,#:build_spans
:linewait
        rdword currentrequest, request_scanline wz
        cmp currentscanline,#16 wc
if_z_and_nc jmp #new_frame
        mov d0,currentscanline
        add d0,total_cogs
        sub d0,#LINE_BUFFERS
        cmps currentrequest,d0 wz,wc
if_be   jmp #:linewait

:scanlinedone
        add currentscanline, total_cogs
        mov span_ready,#1
        cmp currentscanline,#Last_Scanline wc,wz
if_be   jmp #setup_line
        jmp #new_frame


'' handle other shapes... 
:othershapes
        cmp shape_type,#SHP_TEXT wz ' text?
if_e    call #store_text
if_e    jmp #:nextshape
        cmp shape_type,#SHP_BOX wz
if_ne   jmp #:nextshape
:boxshape
        '' BOX DRAWING
        ' get stuff from display list
        rdword poly_left,dlist_ptr
        add dlist_ptr,#2
        shl poly_left,#16
        rdword poly_right,dlist_ptr
        shl poly_right,#16        
        add dlist_ptr,coloroffset ' 2 or 3
        rdbyte poly_color,dlist_ptr
        'sub dlist_ptr,coloroffset '' no further dlist reads, don't need to fix ptr

        call #store_span
        jmp #:nextshape
 

:textshape
        '' TEXT DRAWING
        ' get stuff from display list and precalc
        add dlist_ptr,#1
        
        rdbyte text_scale,dlist_ptr
        add dlist_ptr,#1
        mov text_y,currentscanline

        rdword fontptr,dlist_ptr
        add dlist_ptr,#2
        
        sub text_y,poly_top 
         
        rdword strptr,dlist_ptr

        shr text_y,text_scale 
                    
        add dlist_ptr,coloroffset ' 2 or 3
        rdbyte poly_color,dlist_ptr
        sub dlist_ptr,coloroffset
        add dlist_ptr,#2+2

       
        and text_y,#%111
        '' setup pixel width (1,2, or 4)
        mov text_pxwidth,#1
        test text_scale,#%01_00000 wc
        test text_scale,#%10_00000 wz
if_nz_and_c  jmp #:textdone ' illegal

        ' prepare color
        ' put poly_color into all 4 bytes of span_color
        mov d0,poly_color  
        mov span_color,d0
        shl d0,#8
        or  span_color,d0
        mov d0,span_color
        shl d0,#16
        or  span_color,d0
       
        rdword poly_left,dlist_ptr
        shl poly_left,#16 ' sign extend
        sar poly_left,#16

if_c    shl text_pxwidth,#1
if_nz   shl text_pxwidth,#2
if_c    andn poly_left,#%01 ' force alignment
if_nz   andn poly_left,#%10
        muxc :thewr1,opc_bit0
        muxnz :thewr1,opc_bit1
        mov :thewr2,:thewr1
        mov text_pxperchr,text_pxwidth ' calc width per character (8+1)*pxwidth
        shl text_pxwidth,#3
        add text_pxperchr,text_pxwidth
        shr text_pxwidth,#3

:chrloop
        rdbyte d0,strptr wz
        cmps poly_left,#WIDTH wc
if_z_or_nc jmp #:textdone
        add strptr,#1
        cmps poly_left,#0 wc,wz
if_b    jmp #:chrdone

        ' get font byte
        sub d0,#32
        shl d0,#1
        add d0,fontptr
        rdword d0,d0
        add d0,text_y
        rdbyte d0,d0
        
        mov pixel_ptr,display_base
        add pixel_ptr,poly_left
        
:tplp
        shr d0,#1 wc,wz
:thewr1
if_c    wrbyte span_color,pixel_ptr
        add pixel_ptr,text_pxwidth
        shr d0,#1 wc,wz
:thewr2
if_c    wrbyte span_color,pixel_ptr
        add pixel_ptr,text_pxwidth
if_nz   jmp #:tplp
:chrdone
        add poly_left,text_pxperchr

        jmp #:chrloop


store_span
        mov d0,poly_right
        sar d0,#16
        maxs d0,#WIDTH
        mov d1,poly_left
        sar d1,#16
        mins d1,#0
        cmps d0,d1 wc,wz
if_be   jmp store_span_ret
        cmp span_count,#SPAN_MAX wc
if_ae   jmp store_span_ret
        shl d1,#9
        or d1,d0
        shl d1,#8
        or d1,poly_color
        mov span_ptr,span_count
        add span_ptr,#span_buf
        movd :stash,span_ptr
        add span_count,#1
:stash  mov span_ptr,d1
store_span_ret
        ret

store_text
        cmp span_count,#SPAN_MAX wc
if_ae   jmp store_text_ret
        mov d0,dlist_ptr
        or d0,text_bit
        mov span_ptr,span_count
        add span_ptr,#span_buf
        movd :stashtext,span_ptr
        add span_count,#1
:stashtext mov span_ptr,d0
store_text_ret
        ret

load_rec
        mov span_ptr,span_i
        add span_ptr,#span_buf
        movs :ldrec,span_ptr
        mov d0,#0
:ldrec  mov d0,0-0
        mov rec_text,#0
        shl d0,#1 wc
if_c    mov rec_text,#1
        shr d0,#1
        tjnz rec_text,#:astext
        mov poly_color,d0
        and poly_color,#$FF
        shr d0,#8
        mov poly_right,d0
        and poly_right,#$1FF
        shr d0,#9
        mov poly_left,d0
        jmp load_rec_ret
:astext mov dlist_ptr,d0
        mov poly_top,d0
        sub poly_top,#4
        rdword poly_top,poly_top
        shl poly_top,#16
        sar poly_top,#16
load_rec_ret
        ret

draw_span
        ' range check edges
        
        mov span_right,poly_right         
        sar span_right,#16
        maxs span_right,#WIDTH
        mov span_left,poly_left
        sar span_left,#16
        mins span_left,#0 

        mov span_length,span_right
        cmps span_length,span_left wc,wz,wr
if_be   jmp draw_span_ret ' return if span length/width =< 0   


        ' debug draw
        {
        add span_left,display_base
        wrbyte red,span_left
        add span_right,display_base
        sub span_right,#1
        wrbyte green,span_right

        add span_left,#1
        cmpsub span_length,#2

        tjz span_length,draw_span_ret
:aaaaaaa
        wrbyte span_color,span_left
        add span_left,#1
        djnz span_length,#:aaaaaaa
        jmp draw_span_ret
        '}

        '{
        ' draw span
        add span_left,display_base
        
        ' super edge case: super short span
        cmp span_length,#6 wc,wz ' optimal threshold here seems to be 6, oddly enough (6 is the minimum for correct execution)
if_be  jmp #:shortspan

        ' prepare color
        ' put poly_color into all 4 bytes of span_color
        mov d0,poly_color  
        mov span_color,d0
        shl d0,#8
        or  span_color,d0
        mov d0,span_color
        shl d0,#16
        or  span_color,d0

        ' handle left edge cases

        test span_left,#%11 wc,wz
if_z    jmp #:leftaligned

        test span_left,#%01 wz
if_nz   wrbyte span_color,span_left
if_nz   add span_left,#1
if_nz   sub span_length,#1


if_c    wrword span_color,span_left
if_c    add span_left,#2
if_c    sub span_length,#2
:leftaligned


        ' handle right edge cases
        test span_length,#%11 wc,wz
if_z    jmp #:rightaligned
        
        mov d0,span_left
        add d0,span_length
        
        test span_length,#%01 wz
if_nz   sub d0,#1 
if_nz   wrbyte span_color,d0

if_z_eq_c sub d0,#2
if_z_eq_c wrword span_color,d0

:rightaligned
        ' draw longs
        shr span_length,#2 wz
if_z    jmp draw_span_ret

:spnlp
        wrlong span_color,span_left
        add span_left,#4
        djnz span_length,#:spnlp
        jmp draw_span_ret        

:shortspan
        tjz span_length,draw_span_ret
:sspnlp
        wrbyte poly_color,span_left
        add span_left,#1
        djnz span_length,#:sspnlp
        '}
  
draw_span_ret
              ret
        
'' See: https://forums.parallax.com/discussion/160804/slightly-faster-integer-multiplication-in-pasm
newmult       ' setup
              mov       vRes, #0      ' Primary accumulator (and final result)
              abs       v1,v1  wc
              muxnc     zero,#1 nr,wz ' C to Z
              mov       tmp1, v1      ' Both my secondary accumulator,
              shl       tmp1, #16     ' and the lower 16 bits of v1.
              'mov       tmp2, v2      ' This is the upper 16 bits of v2,
              'shr       tmp2, #16     ' which will sum into my 2nd accumulator.
              mov       tmp2,#0 'haxx
              mov       muli, #16        ' Instead of 4 instructions 32x, do 6 instructions 16x.          
:loop         ' v1_hi_lo * v2_lo
              shr       v2, #1 wc     ' get the low bit of v2          
        if_c  add       vRes, v1      ' (conditionally) sum v1 into my 1st accumulator
              shl       v1, #1        ' bit align v1 for the next pass 
              ' v1_lo * v2_hi
              shl       tmp1, #1 wc   ' get the high bit of v1_lo, *AND* shift my 2nd accumulator
       ' if_c  add       tmp1, tmp2    ' (conditionally) add v2_hi into the 2nd accumulator
              ' repeat 16x
              djnz      muli, #:loop     ' I can't think of a way to early exit this
              ' finalize
              shl       tmp1, #16     ' align my 2nd accumulator
              add       vRes, tmp1    ' and add its contribution
              negz      vRes,vRes          
newmult_ret   ret

' vRes = v1 * v2. v2 is a line count from 0 to 65535.
' Each add saturates, as repeated ADDS does.
' v1 stays. v2 becomes 0.
satmul        mov       vRes,#0
              mov       tmp1,v1
              mov       muli,#16
:sm           shr       v2,#1 wc
        if_c  adds      vRes,tmp1
              adds      tmp1,tmp1
              djnz      muli,#:sm
satmul_ret    ret


''===========
''DATA STUFF
''===========
Dfield_1  long 1<<Dfield

opc_bit0 long 1<<26
opc_bit1 long 2<<26

con8080   long $8080                                             

{
junkcolor long $05_05
junkslope long $0001_8431
junkslope2 long $0000_8431 
}

coloroffset long 2 'toggles between 2 and 3
text_bit     long $80000000 ' text record: list address in bits 15..0

white long $FF * $01010101
black long $03 * $01010101
red   long $CC * $01010101
green long $4C * $01010101

zero long 0

tmp1 res 1
tmp2 res 1
muli res 1
v1 res 1
v2 res 1
vRes res 1

init_share res 1

init_lines res 1
text_y 'alias
trap_lines res 1
pixel_iter res 1

text_pxwidth ' alias
slope_left res 1
text_pxperchr 'alias
slope_right res 1

pixel_ptr   res 1
pixel_ptr_stride res 1

dlist_base res 1
dlist_ptr  res 1
dlist_next res 1               

currentrequest res 1

currentscanline res      1 ''current scanline that TV driver is rendering
currentscanline_haxx res 1 ' speed hack  
tile_line     res        1
display_base res         1


span_left     res 1
span_right    res 1
span_length   res 1
span_color    res 1
shape_type    res 1
poly_top      res 1
poly_bottom   res 1
poly_left     res 1
poly_right    res 1
poly_color    res 1
poly_edgebuf  res 1
poly_syncptr  res 1

text_scale    res 1
fontptr       res 1
strptr        res 1

prep_line     res 1
span_ready    res 1
span_count    res 1
span_i        res 1
span_ptr      res 1
span_ret      res 1
rec_text      res 1
span_buf      res SPAN_MAX

'kak res 1

fit  496

{{
+------------------------------------------------------------------------------------------------------------------------------+
|                                    TERMS OF USE: Parallax Object Exchange License                                            |                                                            
+------------------------------------------------------------------------------------------------------------------------------|
|Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    | 
|files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    |
|modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software|
|is furnished to do so, subject to the following conditions:                                                                   |
|                                                                                                                              |
|The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.|
|                                                                                                                              |
|THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          |
|WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         |
|COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   |
|ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         |
+------------------------------------------------------------------------------------------------------------------------------+
}}
