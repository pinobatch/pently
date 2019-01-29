.include "nes.inc"
.include "global.inc"
.include "mbyt.inc"

LETTERNAME_TILE = $B0
UNMUTE_TILE = $BC
MUTE_TILE = $BE
BLANK_TILE = $DE
LDIGIT_TILE = $E0
RDIGIT_TILE = $F0
PULSE_WAVE_TILE = $D0
TRIANGLE_WAVE_TILE = $D6
NOISE_WAVE_TILE = $D8

.segment "ZEROPAGE"
present_arg: .res 1
present_jmp: .res 1
present_funcptr: .res 2
debughex: .res 2

.segment "CODE"

.proc bg_init
  lda #$4C
  sta present_jmp

  ; Load the palette.
  lda #$80
  sta PPUCTRL
  ldx #$3F
  stx PPUADDR
  ldx #$01
  stx PPUADDR
palloop:
  lda initial_palette-1,x
  sta PPUDATA
  inx
  cpx #32
  bcc palloop

  ; Clear the screen
  lda #BLANK_TILE
  ldy #0
  ldx #$20
  jsr ppu_clear_nt

  ; Set the document area to the other attribute
  lda #$23
  sta PPUADDR
  lda #$C8
  sta PPUADDR
  lda #$55
  ldy #40
attrloop:
  sta PPUDATA
  dey
  bne attrloop

  ; Clear CHR used by dynamic tiles
  sty PPUADDR
  sty PPUADDR
  ldx #$0B
  tya
clrvramloop:
  sta PPUDATA
  iny
  bne clrvramloop
  dex
  bne clrvramloop

  ; Load CHR data for static tiles
  ; $0B00: tiles $B0-$FF
  lday #coltiles_ch1
  ldx #80
  jsr load_1bit_tiles

  lday #$1000
  sta PPUADDR
  sty PPUADDR
spritechrloop:
  lda sprites_chr,y
  sta PPUDATA
  iny
  bne spritechrloop
  lda #$FF
spriteclearloop:
  sta PPUDATA
  iny
  bne spriteclearloop


  ; load hex for debugging
  lday #$1F00
  sta PPUADDR
  sty PPUADDR
  lday #coltiles_ch1+8*64
  ldx #16
  jsr load_1bit_tiles

  ; Load the bottom bar
  lday #$2300
  sta PPUADDR
  sty PPUADDR
bottombarloop:
  sty PPUDATA
  iny
  cpy #64
  bcc bottombarloop

  ; Clear the top bar
  lda #$20
  sta PPUADDR
  lda #$00
  sta PPUADDR
  ldy #$80
topbarloop:
  sta PPUDATA
  dey
  bne topbarloop

  jsr load_ui_text

  ; After load_ui_text, the line img is clear.
  ; Report the status of the mouse.
  lday #msg_nomouse
  bit mouse_port
  bmi write_mtxt
yes_mouse:
  ldx #0
copymtxtloop:
  lda msg_mouse,x
  beq mtxtdone
  cmp #2
  beq is2
  bcs mtxthave
  and mouse_port  ; 1: Write port (0)
  clc
  adc #'1'
  bcc mtxthave
is2:
  lda #'0'  ; 2: Write mask (1 for NES 7-pin, 2 for Famicom DA15)
  ora mouse_mask
mtxthave:
  sta $0180,x
  inx
  bpl copymtxtloop
mtxtdone:
  sta $0180,x
  lday #$0180
write_mtxt:
  ldx #0
  jsr vwfPuts
  lda #16
  jsr invertTiles
  lday #$0100
  jsr copyLineImg

  ; After a VWF line copy, the VRAM direction is down.
  ; Take advantage of this to draw the scrollbar.
  lday #$209E
  sta PPUADDR
  sty PPUADDR
  lda #$DC
  sta PPUDATA
  lda #$DF
  ldy #18
scrollbarloop:
  sta PPUDATA
  dey
  bne scrollbarloop
  lda #$DD
  sta PPUDATA

  ; Defer the rest of the rendering
  lda #DIRTY_SCROLL|DIRTY_TOP_BAR|DIRTY_RATE_LINE
  sta dirty_areas
  lsr present_funcptr+1
  rts
.endproc

;;
; Loads uitxt into VRAM
.proc load_ui_text
uitxtptr = $00
  lday #uitxt
  stay uitxtptr
nextline:
  jsr clearLineImg
nextcmd:
  ldy #0
  lda (uitxtptr),y
  cmp #$FF
  beq done
  
  ; $00-$7F: X position of following nul-terminated C string
  cmp #$80
  bcc not_copy

  ; $80-$9F: Write this line to plane 0 starting here
  ; $C0-$DF: Write this line to plane 1 starting here
  pha
  lda #16
  jsr invertTiles
  ldy #0
  pla
  cmp #$C0
  bcc :+
  ldy #8
:
  jsr copyLineImg
  inc uitxtptr
  bne nextline
  inc uitxtptr+1
  jmp nextline
not_copy:
  tax
  inc uitxtptr
  bne :+
  inc uitxtptr+1
:
  jsr vwfPuts0
  inc uitxtptr
  bne :+
  inc uitxtptr+1
:
  jmp nextcmd
done:
  rts
.endproc  

;;
; Copies a large block of 1-bit tiles to video memory.
; AY: src address
; X: number of tiles
.proc load_1bit_tiles
srcaddr = $00
tilesleft = $03
  stay srcaddr
  stx tilesleft
  ldy #0
tileloop:
  ldx #8
byteloop:
  lda (srcaddr),y
  sta PPUDATA
  iny
  dex
  bne byteloop
  cpy #0
  bne :+
  inc srcaddr+1
:
  ldx #8
  lda #0
clrloop:
  sta PPUDATA
  dex
  bne clrloop
  dec tilesleft
  bne tileloop
  rts
.endproc

.proc scroll_to_cursor
  lda cursor_y
  bmi yscroll_unchanged  ; don't affect top bar
  sec
  sbc doc_yscroll
  bcc scroll_up
  cmp #2
  bcc scroll_up
  cmp #SCREEN_HT - 2
  bcc yscroll_unchanged
  ; Need scroll down
  lda #<(3 - SCREEN_HT)
have_neg_scroll_offset:
  clc
  adc cursor_y
  bcs not_before_start
  lda #0
not_before_start:
  cmp #MAX_ROWS_PER_SOUND - SCREEN_HT
  bcc have_new_yscroll
  lda #MAX_ROWS_PER_SOUND - SCREEN_HT
have_new_yscroll:
  cmp doc_yscroll
  beq yscroll_unchanged
  sta doc_yscroll
  lda #DIRTY_SCROLL
  ora dirty_areas
  sta dirty_areas
yscroll_unchanged:
  rts
scroll_up:
  lda #<-2
  bne have_neg_scroll_offset
.endproc

; Dynamic updates ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc present
  lda nmis
:
  cmp nmis
  beq :-
  lda #>OAM
  sta OAM_DMA
  bit present_funcptr+1
  bpl :+
  jsr present_jmp
:
  ldx #0
  stx present_funcptr+1
  lda #$80
  sta PPUCTRL
  lda #$23
  sta PPUADDR
  lda #$4E
  sta PPUADDR
  .repeat 2, I
    lda debughex+I
    lsr a
    lsr a
    lsr a
    lsr a
    ora #$E0
    sta PPUDATA
    lda debughex+I
    ora #$F0
    sta PPUDATA
  .endrepeat
  ldy #224
  lda #VBLANK_NMI|BG_0000|OBJ_1000|2
  sec
  jmp ppu_screen_on
.endproc

.proc prepare_top_bar
  ldx #95
  lda #$00
clrloop:
  sta $0100,x
  dex
  bpl clrloop

srcaddr = $08
sndleft = $09
dstaddr = $0A
ratefield = $0C
sndparams = $0D
  lda #NUM_SOUNDS
  sta sndleft
  lda #0
  sta srcaddr
  lday #$0102  ; start of first sound's dstaddr
  stay dstaddr
  lda #$98     ; first rate: space
  sta ratefield
sndloop:
  ldx srcaddr
  lda pently_sfx_table+2,x
  sta sndparams
  
  ; Top row: channel name
  and #$0C
  bne notpulse1  ; switch from 0, 8, C to 4, 8, C
  lda #$04
notpulse1:
  lsr a
  lsr a      ; C = 0
  tax        ; X=1: pulse, 2: tri, 3: noise
  ldy #32*0  ; top row
  jsr write_one_name
  
  ; Middle row: rate field
  ldy #32*1  ; middle row
  ldx #6
  jsr write_one_name
  .repeat 2
    iny
    lda ratefield
    inc ratefield
    sta (dstaddr),y
  .endrepeat

  ; Bottom row: Mute status
  ldy #32*2  ; bottom row
  lda sndparams
  and #$01
  asl a
  eor #MUTE_TILE
  sta (dstaddr),y
  iny
  ora #$01
  sta (dstaddr),y
  lda sndparams
  lsr a
  bcs no_write_muted
  iny
  ldx #4
  jsr write_one_name
no_write_muted:

  ; Move to next channel
  clc
  lda #7
  adc dstaddr
  sta dstaddr
  lda #4
  adc srcaddr
  sta srcaddr
  bcc :+
  inc srcaddr+1
:
  dec sndleft
  bne sndloop
  lday #copy_top_bar
  stay present_funcptr
  rts

write_one_name:
  clc
  lda chname_starts-1,x
chnameloop:
  sta (dstaddr),y
  iny
  adc #1
  cmp chname_starts,x
  bcc chnameloop
  rts

.pushseg
.segment "RODATA"
chname_starts:
  .byte $A0  ; 1 Pulse
  .byte $A3  ; 2 Triangle
  .byte $A8  ; 3 Noise
  .byte $AB  ; 4 muted
  .byte $AE  ; 5 muted end
  .byte $90  ; 6 rate:
  .byte $93  ; 7 rate: end
.popseg
.endproc

.proc copy_top_bar
  lda #$20
  sta PPUADDR
  sta PPUADDR
  lda #VBLANK_NMI
  sta PPUCTRL
  asl a  ; A = 0
  clc
loop:
  tax
  .repeat 4, I
    ldy $0100+I,x
    sty PPUDATA
  .endrepeat
  adc #4
  cmp #96
  bcc loop
  rts
.endproc

.proc prepare_rate_line
xpos = $0E
snd_num = $0D

  jsr clearLineImg
  lday #str_rate
  ldx #0
  jsr vwfPuts
  ldx #NUM_SOUNDS - 1
  stx snd_num
sndloop:
  lda snd_num
  asl a
  asl a
  tax
  asl a
  asl a
  sta xpos
  lda pently_sfx_table+2,x
  lsr a
  lsr a
  lsr a
  lsr a
  clc
  adc #1
  
  ; Draw tens digit if needed (always a '1')
  cmp #10
  bcc no_tens_digit
  sbc #10
  pha
  lda xpos
  ora #69
  tax
  lda #'1'
  jsr vwfPutTile
  pla
no_tens_digit:

  ; Draw ones digit
  tay
  lda xpos
  ora #74
  tax
  tya
  ora #'0'
  
  jsr vwfPutTile
  dec snd_num
  bpl sndloop
  
  lda #$09
  sta present_arg
  lday #copyLineImg_arg
  stay present_funcptr
  lda #16
  jmp invertTiles
.endproc

.proc copyLineImg_arg
  ldy #0
  lda present_arg
  bpl :+
  ldy #8
:
  jmp copyLineImg
.endproc

;;
; Translates sound effect pattern data into 6 columns of BG map data.
; @param X which sound (0-3)
; @param doc_yscroll where to start translating (0-44)
.proc prepare_column
  lda channel_right_sides,x
  sta present_arg
  lday #copy_column
  stay present_funcptr

srcptr = $08
pitchtimbrevec = $0A
octave = $0C
ysave = $0D
  txa
  asl a
  asl a
  tax
  lda doc_yscroll
  asl a
  adc pently_sfx_table,x
  sta srcptr
  ldy #0
  tya
  adc pently_sfx_table+1,x
  sta srcptr+1
  
  ; Find the routine responsible for extracting the pitch and timbre
  ; for the channel assigned to this effect
  lda pently_sfx_table+2,x
  and #$0C
  bne :+
  lda #$04
:
  lsr a
  tax
  lda pitchtimbre_routines-2,x
  sta pitchtimbrevec+0
  lda pitchtimbre_routines-1,x
  sta pitchtimbrevec+1
  ldx #0
rowloop:
  ; Draw volume
  lda (srcptr),y
  and #$0F
  cmp #10
  bcc :+
  sbc #10
:
  pha
  lda #BLANK_TILE
  bcc volbelowten
  lda #LDIGIT_TILE|1
volbelowten:
  sta $102,x
  pla
  ora #RDIGIT_TILE
  sta $103,x

  ; do we even have a pitch and timbre to be concerned about?
  lda (srcptr),y
  and #$0F
  beq is_silent_row
  jmp (pitchtimbrevec)
is_silent_row:
  iny
  iny
  lda #BLANK_TILE
  sta $100,x
  sta $101,x
  sta $104,x
  sta $105,x
next_row:
  txa
  clc
  adc #6
  tax
  cmp #6*SCREEN_HT
  bcc rowloop
  rts

pitchtimbre_pulse:
  lda (srcptr),y
  and #$C0
  asl a
  rol a
  rol a
  rol a
  ora #PULSE_WAVE_TILE
  sta $104,x
  ora #$01
  sta $105,x
tonal_pitch:
  iny
  lda #0
  sta octave
  lda (srcptr),y
  iny
  clc
  adc #9
  cmp #48
  bcc :+
  sbc #48
:
  rol octave
  cmp #24
  bcc :+
  sbc #24
:
  rol octave
  cmp #12
  bcc :+
  sbc #12
:
  rol octave
  asl octave

  sty ysave
  tay
  lda semitone_sharp,y
  ora octave
  sta $101,x
  tya
  ldy ysave
  ora #LETTERNAME_TILE
  sta $100,x
  jmp next_row

pitchtimbre_triangle:
  lda #TRIANGLE_WAVE_TILE
  sta $104,x
  ora #$01
  sta $105,x
  jmp tonal_pitch

pitchtimbre_noise:
  iny
  lda (srcptr),y
  and #$80
  beq :+
  lda #2
:
  ora #NOISE_WAVE_TILE
  sta $104,x
  ora #$01
  sta $105,x
  lda (srcptr),y
  iny
  sty ysave
  and #$0F
  tay
  lda noise_lefttile,y
  sta $100,x
  lda noise_righttile,y
  sta $101,x
  ldy ysave
  jmp next_row

.pushseg
.segment "RODATA"
channel_right_sides:
  .repeat 4, I
    .byte $87 + 7 * I
  .endrepeat
pitchtimbre_routines:
  .addr pitchtimbre_pulse, pitchtimbre_triangle, pitchtimbre_noise
semitone_sharp:  ; the base tile for each octave
  mbyt "C0C1C0C1C0 C0C1C0C1C0C1C0"

  ; D-8, D-7, D-6, D-5,
  ; D-4, G-3, D-3, A#2,
  ; F#2, D-2, G-1, D-1,
  ; G-0, D-0,-1-1,-2-2
noise_lefttile:
  mbyt "B2B2B2B2 B2B7B2BA B6B2B7B2 B7B2C2C4"
noise_righttile:
  mbyt "CFCECCCA C8C6C6C5 C5C4C2C2 C0C0C2C4"
.popseg
.endproc

.proc copy_column
  lda #VBLANK_NMI|VRAM_DOWN
  sta PPUCTRL
  lda #0
  sta PPUMASK
  ldx #5
  bit PPUSTATUS
  ldy present_arg
loop:
  lda #$20
  sta PPUADDR
  sty PPUADDR
  dey
  .repeat ::SCREEN_HT, I
    lda $0100+6*I,x
    sta PPUDATA
  .endrepeat
  dex
  bmi :+
  jmp loop
:
  rts
.endproc


.proc handle_dirty_scroll
  lda #DIRTY_SCROLL - 1
  ora dirty_areas
  sta dirty_areas
  ; fall through to prepare_something
.endproc

;;
; Finds a dirty area, prepares it, and marks it as no longer dirty.
.proc prepare_something

  ; First check the column the cursor is in
  lda cursor_x
  lsr a
  lsr a
  cmp #NUM_SOUNDS
  bcs not_in_any_col
  tax
  lda one_shl_x,x
  and dirty_areas
  bne found_one

not_in_any_col:
  ldx #0
loop:
  lda one_shl_x,x
  and dirty_areas
  bne found_one
  inx
  cpx #8
  bcc loop
  rts
found_one:

  eor dirty_areas
  sta dirty_areas
  txa
  asl a
  tay
  lda dirty_prepares+1,y
  pha
  lda dirty_prepares,y
  pha
unknown_dirty_prepare:
  rts

.pushseg
.segment "RODATA"
dirty_prepares:
  .repeat ::NUM_SOUNDS
    .addr prepare_column-1
  .endrepeat
  .addr handle_dirty_scroll-1, prepare_rate_line-1, prepare_top_bar-1
  .repeat 8 - (::NUM_SOUNDS + 3)
    .addr unknown_dirty_prepare-1
  .endrepeat
.popseg  
.endproc


.segment "RODATA"
initial_palette:
  mbyt   "101616 FF381616 FF161616 FF161616"
  mbyt "FF001020 FF161616 FF161616 FF161616"

sprites_chr:
  .incbin "obj/nes/sprites.chr"
coltiles_ch1:
  .incbin "obj/nes/coltiles.ch1"
uitxt:
  ; Bottom bar ($00-$3F)
  .byte 16, "A+move: change value",0
  .byte $80
  ; mouse status goes in $C1
  .byte 16, "B+",$84,$85,": insert/delete row",0
  .byte $82
  .byte 0, "B+",$86,$87,": copy   B+A: play",0
  .byte $83
  
  ; Export menu
  .byte 0, "Display This Sound as Hex", 0
  .byte $84
  .byte 0, "Export ASM to .sav File", 0
  .byte $85

  ; Top bar rate line ($90-$9F; filled in later)
  ; Top bar channel names ($A0-$AD)
  .byte 0, "Pulse",0
  .byte 24,"Triangle",0
  .byte 64,"Noise",0
  .byte 88,"muted",0
  .byte $8A
  
  ; Sprites messages at $10, $14, $18
  .byte 6, "Copy", 0
  .byte 35, "Insert", 0
  .byte 66, "Delete", 0
  .byte $D1

  .byte $FF
str_rate:
  .byte "rate:",0
msg_mouse:
  .byte "Mouse port ",1," mask ",2,0
msg_nomouse:
  .byte "No mouse connected",0
one_shl_x:
  .repeat 8, I
    .byte 1 << I
  .endrepeat

