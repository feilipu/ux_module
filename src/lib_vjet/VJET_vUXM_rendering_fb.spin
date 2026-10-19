'' VECTORJET framebuffer renderer.
'' Same display list and span fill as VJET_vUXM_rendering.spin.
'' Every third line is packed to 256 pixels, 2 bits each.
'' Sixteen colour longs per stored line. Each long is 16 pixels.
'' Other lines walk edges and are not stored. The VGA cog repeats each stored line.
'' The cog does not wait on the VGA line number.
'' Three cogs are required. Stripe 0 publishes done.
'' Derived from VJET_vUXM_rendering.spin, (C)2021 IRQsome Software.
'' (C)2026 feilipu.

CON

  WIDTH = 256
  NUM_LINES = 240
  STORED_LINES = 80 '' Demo arrays use this count. Do not shrink it for the bring-up.
  SCRATCH_LONGS = 3 * WIDTH / 4 '' One private 256-byte line per cog.

  FB_W = WIDTH
  PAL_PER_LINE = 16
  FB_LONGS = FB_W * STORED_LINES / 16
  PAL_LONGS = STORED_LINES * PAL_PER_LINE
  FB_BYTES = FB_LONGS * 4
  PAL_BYTES = PAL_LONGS * 4

  Last_Scanline = NUM_LINES-1 ''final scanline for a frame

  '' cmp d,#s wc,wz. Bits 31:18 plus the 9-bit source. OpenSpin opcode $21.
  CMP_MASK = ($3FFF << 18) | $1FF
  CMP_MARK = ($210F << 18) | $03400000 | Last_Scanline

  Sfield = 0
  DField = 9


'' Display list format - shape header  (8 bytes)
'' WORD pointer to next shape or null
'' BYTE renderer sync line
'' BYTE shape type
'' WORD start scanline
'' WORD end scanline

'' Shape type 1 header - trapezoid stack (16 bytes)
'' LONG current left edge
'' LONG current right edge 
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

'' Stored size includes the 8-byte header.
'' Flat triangle, one trapezoid: 36 bytes.
'' General triangle, two trapezoids: 48 bytes.
'' Box: 16 bytes. Text: 20 bytes.
'' Polygon: 24 bytes plus 12 bytes for each trapezoid.
'' Sloped line: 36 bytes. Horizontal line: 16 bytes.

#1
SHP_TRAPSTACK         ' Shape type 1 header - trapezoid stack (16 bytes)
SHP_BOX               ' Shape type 2 header - box (8 bytes)
SHP_TEXT              ' Shape type 3 header - text (12 bytes)


VAR
  long rendcog[8]
  long rendcount
  long scanAt

PUB set_lines(n) : ok | inst, i, lim, nlong
'' Select a shorter store before start. The default scans 240 logical lines.
'' The scan stops at logical line n * 3 - 1. Line n of the buffer stays clear.
'' The second buffer begins (n + 1) * 64 bytes after the first.
'' The first call finds the compare. A later call uses that index.

  lim := ((n * 3) - 1) & $1FF
  if scanAt == 0
    nlong := (@cog_image_end - @Entry) >> 2
    repeat i from 0 to nlong - 1
      inst := long[@Entry][i]
      if (inst & CMP_MASK) == CMP_MARK
        scanAt := i + 1
        quit
    if scanAt == 0
      return 0
  i := scanAt - 1
  inst := long[@Entry][i]
  long[@Entry][i] := (inst & !$1FF) | lim
  frameBytes := (n + 1) << 6
  paletteBytes := (n + 1) << 6
  return 1


PUB start(cognum,totalcogs,scanbuffer,dlistPtrAdr,framePtr,palPtr,ctrlPtr,readyptr)
'' Start one rendering cog. Call once per cog with cognum 0..totalcogs-1.
'' Copies the DAT parameters then cognew. Wait so the hub image is taken
'' before the next start() overwrites those longs.
'' ctrlPtr is go, front, done, stripe0, stripe1, stripe2, fixup, blend.
  longmove(@cognumber,@cognum,7)
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
frame_base              long -1
palette_base            long -1
ctrl_base               long -1

''Note: Init code gets reuses as variables, thus the labels
a0      mov a0, Par  ''read parameter
d0      rdbyte currentscanline, a0 wz''is ready?
d1 if_z jmp #d0 'if not, repeat

        mov go_ptr, ctrl_base
        mov front_ptr, ctrl_base
        add front_ptr, #4
        mov done_ptr, ctrl_base
        add done_ptr, #8
        mov stripe_ptr, ctrl_base
        add stripe_ptr, #12
        mov d0, cognumber
        shl d0, #2
        add stripe_ptr, d0
        mov stripe1_ptr, ctrl_base
        add stripe1_ptr, #16
        mov stripe2_ptr, ctrl_base
        add stripe2_ptr, #20
        mov expect, #1
        mov warm, #0
  

'        rdlong Tiles_Adr, tile_adr ''read address of where tiles are at

''Main loop for renderer
new_frame
        tjz warm, #:arrive
:block  rdlong d0, front_ptr
        cmp d0, filled wz
if_nz   jmp #:block
        rdlong d0, go_ptr
        cmp d0, expect wz
if_nz   jmp #:block
:arrive mov warm, #1
        rdlong d0, front_ptr wz
        mov filled, #1
if_nz   mov filled, #0
        mov frame_ptr, frame_base
        mov pal_ptr, palette_base
if_z    add frame_ptr, frameBytes
if_z    add pal_ptr, paletteBytes

        mov currentscanline, cognumber ''reset current scanline for COG

        rdword dlist_base, dlist_ptr_adr  '' read adress of display list
        'wrword dlist_base, dlist_in_use
'' Cog 0 advances every off-screen top to Y 0, then releases the others.
'' A second writer here replaces edges that another cog has already walked.
        tjnz cognumber,#:waitfix
'' Cog 0 walks every trap stack. A negative top moves to Y 0.
'' Cog 0 then writes expect at fixup. Cogs 1 and 2 wait for that long.
'' fixup shapes clipped by top edge of screen (negative ystart)
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
        mov d0,ctrl_base
        add d0,#24
        wrlong expect,d0
        jmp #setup_line

:waitfix mov d0,ctrl_base
        add d0,#24
        rdlong d1,d0
        cmp d1,expect wz
if_nz   jmp #:waitfix

'' ==================================
'' ACTUAL LINE RENDERING STARTS HERE!
'' ==================================                 
setup_line
        mov display_base,scanlines ' Private line for this cog. 256 bytes.
        mov d0,cognumber
        shl d0,#8
        add display_base,d0
        ' prepare speed hack
        mov currentscanline_haxx,currentscanline
        add currentscanline_haxx,#1
        shl currentscanline_haxx,#16
        
        mov pixel_ptr,display_base


        mov pixel_iter,#WIDTH/4
:loop   wrlong zero,pixel_ptr
        add pixel_ptr,#4
        djnz pixel_iter,#:loop

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

        'wait for shape sync
        cmp poly_top,currentscanline wz  ' is first line of shape? 
if_e    jmp #:synced ' not if first line
:syncloop
        rdbyte d0,dlist_ptr
        cmp d0,currentscanline wz
if_nz   jmp #:syncloop
        cmp poly_top,currentscanline wz  ' restore first-line test after the wait
:synced        
        mov poly_syncptr,dlist_ptr ' remember ptr to sync byte for later

        add dlist_ptr,#1        
        rdbyte shape_type,dlist_ptr
        add dlist_ptr,#5 ' move dlist ptr to start of shape data

        cmp shape_type,#SHP_TRAPSTACK+1 wc 
if_ae   jmp #:othershapes

        ' read edges
        mov poly_edgebuf,dlist_ptr
        mov trap_lines,currentscanline
if_e    add dlist_ptr,#8 ' if first line of shape, read starting edges 
        rdlong poly_left,dlist_ptr
        sub trap_lines,poly_top
        add dlist_ptr,#4
        rdlong poly_right,dlist_ptr
        add dlist_ptr,#4
if_ne   add dlist_ptr,#8 ' if first line of shape, fixup pointer

        ' find current trapezoid (slightly unrolled for speed)
:traplp rdword d0,dlist_ptr
        cmpsub trap_lines,d0 wc,wz
if_c    add dlist_ptr,#3*4
if_c    rdword d0,dlist_ptr
if_nc   jmp #:trapfound
        cmpsub trap_lines,d0 wc,wz
if_c    add dlist_ptr,#3*4
if_c    jmp #:traplp
:trapfound

        add dlist_ptr,#2 ' 2 or 3
        rdbyte poly_color,dlist_ptr
        call #apply_stripe
        sub dlist_ptr,#2
        add dlist_ptr,#2+2
        rdlong slope_left,dlist_ptr
        add dlist_ptr,#4
        rdlong slope_right,dlist_ptr


        call #draw_span

        ' write back edges

        adds poly_left,slope_left    
        wrlong poly_left,poly_edgebuf
        add poly_edgebuf,#4     
        adds poly_right,slope_right
        wrlong poly_right,poly_edgebuf
:nextshape_sync
        ' write sync
        mov d0,currentscanline
        add d0,#1
        cmp poly_bottom,d0 wz
if_e    neg d0,#1
        wrbyte d0,poly_syncptr

 
:nextshape
        tjnz dlist_next,#:shapeloop

''scanline rendering is finished. Pack it, then take the next stripe line.
:scanline_finished
        call #pack_line
        add currentscanline, total_cogs
        cmp currentscanline,#Last_Scanline wc,wz
if_be   jmp #setup_line
        jmp #:framedone

:framedone
        wrlong expect, stripe_ptr
        tjnz cognumber, #:next
:s1     rdlong d0, stripe1_ptr
        cmp d0, expect wz
if_nz   jmp #:s1
:s2     rdlong d0, stripe2_ptr
        cmp d0, expect wz
if_nz   jmp #:s2
        wrlong expect, done_ptr
:next   add expect, #1
        jmp #new_frame


'' handle other shapes... 
:othershapes
        cmp shape_type,#SHP_TEXT wz ' text?
if_e    jmp #:textshape
        cmp shape_type,#SHP_BOX wz
if_ne   jmp #:nextshape_sync
:boxshape
        '' BOX DRAWING
        ' get stuff from display list
        rdword poly_left,dlist_ptr
        add dlist_ptr,#2
        shl poly_left,#16
        rdword poly_right,dlist_ptr
        shl poly_right,#16        
        add dlist_ptr,#2 ' 2 or 3
        rdbyte poly_color,dlist_ptr
        call #apply_stripe
        'sub dlist_ptr,#2 '' no further dlist reads, don't need to fix ptr

        call #draw_span
        jmp #:nextshape_sync
 

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
                    
        add dlist_ptr,#2 ' 2 or 3
        rdbyte poly_color,dlist_ptr
        call #apply_stripe
        sub dlist_ptr,#2
        add dlist_ptr,#2+2

       
        and text_y,#%111
        '' setup pixel width (1,2, or 4)
        mov text_pxwidth,#1
        test text_scale,#%01_00000 wc
        test text_scale,#%10_00000 wz
if_nz_and_c  jmp #:nextshape_sync ' illegal

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
if_z_or_nc jmp #:nextshape_sync
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

'' Solid span. Bit 1 set jumps to the mix before this fill.
'' Six pixels or fewer use one byte write. A longer span writes longs.
'' The return is above the mix. A short solid span must not fall into it.
        add span_left,display_base
        test poly_color,#2 wz
if_nz   jmp #blend_span

'' A span of 6 pixels or fewer uses the byte loop. The long fill needs more than 6.
        cmp span_length,#6 wc,wz
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

draw_span_ret
              ret

'' Bit 1 selects this path. The count is the pixel width.
'' A count of 0 must not reach here. djnz of 0 walks Hub.
'' Mask both bytes with $FC. Average bits 7:6, 5:4, and 3:2.
'' $54 keeps the shifted bit of each pair. Add the two terms.
'' The add keeps a carry inside the pair. C still holds bit 0.
blend_span
        test poly_color,#1 wc
        and poly_color,#$FC
:blp    rdbyte d0,span_left
        and d0,#$FC
        mov span_right,d0
        xor span_right,poly_color
        shr span_right,#1
        and span_right,#$54
        and d0,poly_color
        add d0,span_right
        muxc d0,#1
        wrbyte d0,span_left
        add span_left,#1
        djnz span_length,#:blp
        jmp #draw_span_ret

'' Pack lines 0, 3, 6 ... 237. 80 stored lines. 16 groups of 16 pixels.
'' Each group has four colours. A fifth colour uses the nearest of those four.
'' strptr and init_share are free here.
pack_line
        mov shift,#0
        mov d0,currentscanline
:div3   cmpsub d0,#3 wc
if_nc   jmp #:got
        add shift,#1
        jmp #:div3
:got    tjnz d0,#pack_line_ret
        mov src,display_base
        mov d0,shift
        shl d0,#6
        mov dst,frame_ptr
        add dst,d0
        mov strptr,pal_ptr
        add strptr,d0
        mov init_share,#16
:grp    call #pack_group
        djnz init_share,#:grp
pack_line_ret
        ret

'' Sixteen samples. One pixel long and one palette long.
pack_group
        mov nfound,#0
        mov pal0,#0
        mov pal1,#0
        mov pal2,#0
        mov pal3,#0
        mov accum,#0
        mov shift,#0
        mov pixel_iter,#16
:pix    rdbyte pixbyte,src
        add src,#1
        call #find_color
        shl idx,shift
        or accum,idx
        add shift,#2
        djnz pixel_iter,#:pix
        wrlong accum,dst
        add dst,#4
        wrbyte pal0,strptr
        add strptr,#1
        wrbyte pal1,strptr
        add strptr,#1
        wrbyte pal2,strptr
        add strptr,#1
        wrbyte pal3,strptr
        add strptr,#1
pack_group_ret
        ret

'' poly_color is the low byte. The next list byte is the high byte.
'' Clear bits 1:0. If the high byte is that value minus $55, set bit 0.
'' Bit 0 marks the dark line. A low byte below $55 leaves the flag clear.
'' The VGA cog ORs $03, so bits 1:0 are not a visible colour.
'' If blend is set and the source bit 1 is set, set bit 1 for the mix.
apply_stripe
        mov span_color,poly_color
        mov d0,dlist_ptr
        add d0,#1
        rdbyte d1,d0
        mov d0,span_color
        and poly_color,#$FC
        sub d0,#85 wc
if_c    jmp #:bit1
        cmp d0,d1 wz
if_z    or poly_color,#1
:bit1   mov d0,ctrl_base
        add d0,#28
        rdlong d0,d0 wz
if_nz   test span_color,#2 wc
if_nz_and_c or poly_color,#2
apply_stripe_ret
        ret

'' Match pixbyte to pal0..pal3. A new colour fills the next free slot.
'' When all four slots are full, idx is the nearest slot.
'' The compare drops bits 1:0. movd stores the byte. movs stores black.
find_color
        movs :rd,#pal0
        mov idx,#0
:rd     mov d0,0-0
        cmp idx,nfound wz
if_e    jmp #:store
        cmp d0,pixbyte wz
if_z    jmp #find_color_ret
        add :rd,#1
        add idx,#1
        cmp idx,#4 wz
if_ne   jmp #:rd
        movs :nr,#pal0
        mov muli,#$100
        mov d1,#0
        mov idx,#0
:nr     mov d0,0-0
        and d0,#$FC
        mov span_color,pixbyte
        and span_color,#$FC
        sub d0,span_color
        abs d0,d0
        cmp d0,muli wc
if_b    mov muli,d0
if_b    mov d1,idx
        add :nr,#1
        add idx,#1
        cmp idx,#4 wz
if_ne   jmp #:nr
        mov idx,d1
        jmp #find_color_ret
:store  movd :wr,:rd
        add nfound,#1
:wr     mov 0-0,pixbyte
find_color_ret
        ret
        
'' See: https://forums.parallax.com/discussion/160804/slightly-faster-integer-multiplication-in-pasm
'' 16 by 16 multiply. The high half of v2 is 0, so only the low product is kept.
newmult
              mov       vRes,#0
              abs       v1,v1 wc
              muxnc     zero,#1 nr,wz
              mov       muli,#16
:loop         shr       v2,#1 wc
        if_c  add       vRes,v1
              shl       v1,#1
              djnz      muli,#:loop
              negz      vRes,vRes
newmult_ret   ret
           


''===========
''DATA STUFF
''===========
opc_bit0 long 1<<26
opc_bit1 long 2<<26

zero long 0

frameBytes long FB_BYTES
paletteBytes long PAL_BYTES
cog_image_end

muli res 1
v1 res 1
v2 res 1
vRes res 1

init_share res 1 '' pack_line counts 16 groups here. Do not remove this long.

init_lines res 1
text_y 'alias
trap_lines res 1
pixel_iter res 1

text_pxwidth ' alias
slope_left res 1
text_pxperchr 'alias
slope_right res 1

pixel_ptr   res 1

dlist_base res 1
dlist_ptr  res 1
dlist_next res 1               

currentscanline res      1 ''logical line this cog is packing
currentscanline_haxx res 1 ' speed hack
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

go_ptr        res 1
front_ptr     res 1
done_ptr      res 1
stripe_ptr    res 1
stripe1_ptr   res 1
stripe2_ptr   res 1
frame_ptr     res 1
pal_ptr       res 1
expect        res 1
warm          res 1
filled        res 1
src           res 1
dst           res 1
pixbyte       res 1
idx           res 1
nfound        res 1
pal0          res 1
pal1          res 1
pal2          res 1
pal3          res 1
accum         res 1
shift         res 1

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
