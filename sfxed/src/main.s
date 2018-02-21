.include "nes.inc"
.include "global.inc"
.include "mbyt.inc"

OAM = $0200
INCLUDE_SAMPLE_DATA = 0
USE_MMC1 = 1

.segment "ZEROPAGE"
nmis: .res 1
tvSystem: .res 1
oam_used: .res 1
doc_yscroll: .res 1
cursor_x: .res 1  ; 0-2, 4-6, 8-10, 12-14
cursor_y: .res 1  ; -3 to -1: top 3 rows, 0 to max rows - 1: in sound
dirty_areas: .res 1
changed_things: .res 1

; controller
das_keys: .res 2
das_timer: .res 2
cur_keys: .res 2
new_keys: .res 2

.segment "BSS"
.align 256
psg_sound_data: .res NUM_SOUNDS * BYTES_PER_SOUND

; each entry is 4 bytes (data low, data high, rate/ch/mute, cached len)
pently_sfx_table: .res 4*8

.segment "INESHDR"
.if USE_MMC1
  INESMAPBYTE = $13  ; MMC1, battery
.else
  INESMAPBYTE = $01  ; NROM, H pad bridged, no battery
.endif
  .byte "NES",$1A,1,0,INESMAPBYTE,0

.segment "VECTORS"
  .addr nmi, reset, irq

.segment "CODE"
.proc nmi
  inc nmis
.endproc
.proc irq
  rti
.endproc

.proc reset
  sei
  ldx #$FF
  txs
  inx
  stx PPUCTRL
  stx PPUMASK
  bit PPUSTATUS

  ; wait for bottom of first frame
:
  bit PPUSTATUS
  bpl :-

  cld
  lda #$0F
  sta $4015
  lda #$40
  sta $4017
  
.if ::USE_MMC1
  inc $FFFD  ; reset MMC1
  txa
  ldx #5
:
  sta $E000  ; enable PRG RAM (MMC3B/C)
  dex
  bne :-
  ldx #5
:
  sta $A000  ; enable PRG RAM (SNROM)
  dex
  bne :-
  inx
  sta $8000  ; vertical mirroring
  stx $8000
  stx $8000  ; fixed $C000 (not that it matters)
  stx $8000
  sta $8000  ; 8K CHR
  tax
.else
  txa
.endif

  ; clear zero page and sound data
clrzploop:
  sta $00,x
  inx
  bne clrzploop
  lda #$C0
  sta debughex+0
  lda #$DE
  sta debughex+1

  ; load initial PSG sound table
  jsr load_psg_sound_table
  jsr pently_init
  
  jsr load_from_sram
  beq sram_is_valid
  ldx #0
  txa
clear_psg_sound_data:
  sta psg_sound_data+0,x
  sta psg_sound_data+256,x
  inx
  bne clear_psg_sound_data
  jsr load_psg_sound_table  ; again, to replace the bad mode values


sram_is_valid:

  ; Mice don't necessarily respond as mice until their sensitivity
  ; has been changed at least once.  Sending a clock while strobe is
  ; turned on cycles a mouse's sensitivity.  Fortunately, the mouse
  ; detection method I use cycles the mouse to medium sensitivity
  ; as part of the detection scheme.
  jsr detect_mouse

  ; Load some sound data to test (temporary)
.if ::INCLUDE_SAMPLE_DATA
  ldx #29
  sampleloop1:
    lda line_snd,x
    sta psg_sound_data+0,x
    dex
    bpl sampleloop1
  ldx #25
  sampleloop2:
    lda openhat_snd,x
    sta psg_sound_data+128,x
    dex
    bpl sampleloop2
  ldx #7
  sampleloop3:
    lda kick2_snd,x
    sta psg_sound_data+256,x
    dex
    bpl sampleloop3
.endif
  
  ; wait for bottom of second frame
:
  bit PPUSTATUS
  bpl :-

  ; And now the ppu should be warmed up and in vertical blanking.
  lda #VBLANK_NMI
  sta PPUCTRL
  jsr getTVSystem
  sta tvSystem
  jsr bg_init

  ldx #0
  stx cursor_y
  inx
  stx cursor_x
forever:
  ; NES mouse protocol requires reading pads before mouse...
  jsr read_pads
  jsr read_mouse_ex

  ; but some actions done with the mouse are done by simulating
  ; keypresses (mostly B) so handle mouse before pads
  jsr handle_mouse
  jsr handle_keys
  jsr check_changed_things
  lda #0
  sta oam_used
  jsr prepare_something
  jsr draw_cursor
  jsr draw_scrollthumb
  ldx oam_used
  jsr ppu_clear_oam
  jsr present
  jsr pently_update
  jmp forever
.endproc

;;
; @param X which sound to update (0 to NUM_SOUNDS - 1)
; @return A = new sound length, X unchanged,
; Y = channel X's offset into pently_sfx_table
.proc update_sound_length
srcdata = 0
maxfound = 2
  txa
  asl a
  asl a
  tay
  lda pently_sfx_table+0,y
  sta srcdata+0
  lda pently_sfx_table+1,y
  sta srcdata+1
  ldy #0
  sty maxfound
cmploop:
  lda (srcdata),y
  iny
  iny
  and #$0F
  beq row_is_silent
  sty maxfound
row_is_silent:
  cpy #BYTES_PER_SOUND
  bcc cmploop
  txa
  asl a
  asl a
  tay
  lda maxfound
  lsr a
  sta pently_sfx_table+3,y
  rts
.endproc

.proc play_all_sounds
cur_channel = $07
  ldx #NUM_SOUNDS-1
loop:
  txa
  asl a
  asl a
  tay
  lda pently_sfx_table+2,y
  lsr a
  bcc is_muted
  stx cur_channel
  jsr update_sound_length
  lda cur_channel
  jsr pently_start_sound
  ldx cur_channel
is_muted:
  dex
  bpl loop
  rts
.endproc

.proc check_changed_things
  lsr changed_things
  bcc notPlayRow
  ldy cursor_y
  bmi notPlayRow
  ldx cursor_x

datalo = $00
datahi = $01
channel = $02
effect_header = pently_sfx_table+4*NUM_SOUNDS
  jsr seek_to_xy
  lda datalo
  sta effect_header+0
  lda datahi
  sta effect_header+1
  lda channel
  ora #(10-1) << 4  ; channel x, rate 10
  sta effect_header+2
  lda #1
  sta effect_header+3
  lda #NUM_SOUNDS
  jsr pently_start_sound
notPlayRow:

  lda #0
  sta changed_things
  rts
.endproc

; Sprites ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc get_scrollthumb_y
  lda doc_yscroll
  lsr a
  lsr a
  adc #55
  sta 0
  lda doc_yscroll
  asl a
  adc 0
  rts
.endproc

SCROLLTHUMB_TOP_TILE = $03
SCROLLTHUMB_MIDDLE_TILE = $07
SCROLLTHUMB_BOTTOM_TILE = $0B
.proc draw_scrollthumb
  ; should be 45 pixels tall, or 6 sprites
  ; y = scroll * 2 + scroll / 4 + 55
  ldx oam_used
  jsr get_scrollthumb_y
  sta 0
  ldy #6

  ; Fill in most of the thumb
thumbloop:
  lda 0
  sta OAM,x
  clc
  adc #8
  sta 0
  lda #SCROLLTHUMB_MIDDLE_TILE
  sta OAM+1,x
  lda #$00
  sta OAM+2,x
  lda #240
  sta OAM+3,x
  txa
  axs #<-4
  dey
  bne thumbloop
  
  ; Finally change the tiles used for the top and bottom
  ldy oam_used
  stx oam_used
  lda #SCROLLTHUMB_TOP_TILE
  sta OAM+1,y
  lda #SCROLLTHUMB_BOTTOM_TILE
  sta OAM+21,y
  rts
.endproc

MOUSE_TOP_TILE = 0
MOUSE_BOTTOM_TILE = 4
DOWN_ARROW_TILE = 8
LEFT_ARROW_TILE = 12
BRACKETS_TILE = 15
.proc draw_cursor

  ; mouse: OAM+0-7
  ; brackets: OAM+8-15
  ldx oam_used
  lda mouse_x
  sta OAM+3,x
  sta OAM+7,x
  lda mouse_y
  cmp #208
  bcc :+
  lda #240-16
:
  adc #15
  sta OAM+0,x
  adc #8
  sta OAM+4,x
  lda #0
  sta OAM+1,x
  sta OAM+2,x
  sta OAM+6,x
  sta OAM+10,x
  lda #%01000000  ; Flip second piece of keyboard cursor
  sta OAM+14,x
  lda #MOUSE_TOP_TILE
  sta OAM+1,x
  lda #MOUSE_BOTTOM_TILE
  sta OAM+5,x
  lda #BRACKETS_TILE
  sta OAM+9,x
  sta OAM+13,x

  ; All but the X,Y position of the keyboard cursor are set.
  lda cursor_y
  bpl cursor_in_area
  ; -3 through -1: top bar elements
  and #$03
  asl a
  asl a
  asl a
  adc #15
  sta OAM+8,x
  sta OAM+12,x
  lda cursor_x
  and #$0C
  tay
  lda cursor_left,y
  sta OAM+11,x
  clc
  adc #56
  jmp have_right_x
cursor_in_area:
  sec
  sbc doc_yscroll
  cmp #SCREEN_HT
  bcc :+
  lda #30-6
:
  asl a
  asl a
  asl a
  adc #47
  sta OAM+8,x
  sta OAM+12,x
  ldy cursor_x
  lda cursor_left,y
  sta OAM+11,x
  lda cursor_left+1,y
  clc
  adc #8
have_right_x:
  sta OAM+15,x

  ; If A is held, draw arrows around cursor instead of mouse pointer
  lda cursor_y
  bmi y_not_offscreen
  sec
  sbc doc_yscroll
  cmp #20
  bcs not_arrows
y_not_offscreen:
  bit held_keys  ; bit 7: A held
  bmi arrows_around_cursor
  lda mouse_gesture
  cmp #GESTURE_CELLDRAG
  bne not_arrows

arrows_around_cursor:
  lda OAM+8,x
  sec
  sbc #8
  sta OAM+0,x
  clc
  adc #16
  sta OAM+4,x
  lda #LEFT_ARROW_TILE
  sta OAM+9,x
  sta OAM+13,x
  lda #DOWN_ARROW_TILE
  sta OAM+1,X
  sta OAM+5,x
  lda #$80
  sta OAM+2,x
  asl a
  sta OAM+6,x
  
  ; average left and right to make
  lda OAM+15,x
  clc
  adc OAM+11,x
  ror a
  sta OAM+3,x
  sta OAM+7,x
not_arrows:
  lda #16
  clc
  adc oam_used
  sta oam_used

  ; If B has a release action, and cursor_y is within the pattern,
  ; and cursor_x is within a different sound from gesture_x or
  ; cursor_y is in a different row from gesture_y, draw the copy
  ; indicator at the gesture start.
  bit action_release_keys
  bvc no_copy_indicator1
  ldy cursor_y
  bmi no_copy_indicator1
  cpy gesture_y
  bne draw_copy_indicator
  lda cursor_x
  eor gesture_x
  cmp #4
  bcs draw_copy_indicator
no_copy_indicator1:
  jmp no_copy_indicator

draw_copy_indicator:
cursx = 3
cursy = 0
curstile = 1
  ; X still points at the beginning of the cursor, putting the
  ; copy indicator at OAM+16-31.
  ; Find the horizontal position of the copy source marker
  ldy gesture_x
  lda cursor_left,y
  clc
  adc #17
  sta OAM+19,x
  adc #8
  sta OAM+23,x
  adc #8
  sta OAM+27,x
  adc #8
  sta OAM+31,x

  ; If cursor below gesture start, use insert; otherwise use delete.
  lda gesture_y
  cmp cursor_y
  ldy #$14
  bcc :+
  ldy #$18
:

  ; But if in a different column, use "Copy" instead.
  lda gesture_x
  eor cursor_x
  cmp #4
  bcc :+
  ldy #$10
  clc
:
  tya
  sta OAM+17,x
  adc #1
  sta OAM+21,x
  adc #1
  sta OAM+25,x
  adc #1
  sta OAM+29,x

  lda gesture_y
  sec
  sbc doc_yscroll
  bcs :+
  lda #0
:
  cmp #SCREEN_HT
  bcc :+
  lda #SCREEN_HT - 1
:
  asl a
  asl a
  asl a
  adc #47
  sta OAM+16,x
  sta OAM+20,x
  sta OAM+24,x
  sta OAM+28,x
  lda #0
  sta OAM+18,x
  sta OAM+22,x
  sta OAM+26,x
  sta OAM+30,x

  lda #16
  clc
  adc oam_used
  sta oam_used
no_copy_indicator:
  rts
.pushseg
.segment "RODATA"
cursor_left:
  .repeat ::NUM_SOUNDS,I
    .byte 7+56*I, 25+56*I, 39+56*I, 57+56*I
  .endrepeat
.popseg
.endproc

.proc load_psg_sound_table
  ldx #0
setupsndtableloop:
  lda psg_sound_table_load,x
  sta pently_sfx_table,x
  inx
  cpx #4 * (NUM_SOUNDS + 1)
  bcc setupsndtableloop
  rts
.endproc

.segment "RODATA"
psg_sound_table_load:
  ; 0: track 1
  .addr psg_sound_data+0
  .byte %00000001
  .byte 64
  ; 1: track 2
  .addr psg_sound_data+128
  .byte %00101100
  .byte 64
  ; 2: track 3
  .addr psg_sound_data+256
  .byte %01001000
  .byte 64
  ; 3: track 4
  .addr psg_sound_data+384
  .byte %10000000
  .byte 64
  ; 4: the row being edited
  .addr psg_sound_data+0
  .byte %10010000  ; rate: 10, channel: 0
  .byte 1

psg_sound_data_start_lo:
  .repeat NUM_SOUNDS, I
    .byte <(psg_sound_data + I * BYTES_PER_SOUND)
  .endrepeat
psg_sound_data_start_hi:
  .repeat NUM_SOUNDS, I
    .byte >(psg_sound_data + I * BYTES_PER_SOUND)
  .endrepeat

; Sample data with which to test, possibly to be removed before release
.if INCLUDE_SAMPLE_DATA
line_snd:
  .dbyt $4F27,$4E2A,$4D2C
  .dbyt $4C27,$4B29,$4A2C
  .dbyt $8927,$882A,$872C
  .dbyt $8627,$8529,$842C
  .dbyt $8327,$822A,$812C
openhat_snd:
  .dbyt $0703, $0683, $0503, $0583, $0403, $0483
  .dbyt $0303, $0383, $0203, $0283, $0203, $0283, $0103
kick2_snd:
  .dbyt $8F1F, $8F1B, $8F18, $8215
.endif
