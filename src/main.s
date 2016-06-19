;
; Pently audio engine
; Player shell as self-contained NES executable
;
; Copyright 2012-2016 Damian Yerrick
; 
; Permission is hereby granted, free of charge, to any person
; obtaining a copy of this software and associated documentation
; files (the "Software"), to deal in the Software without
; restriction, including without limitation the rights to use, copy,
; modify, merge, publish, distribute, sublicense, and/or sell copies
; of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
; 
; The above copyright notice and this permission notice shall be
; included in all copies or substantial portions of the Software.
; 
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
; THE SOFTWARE.
;

.include "nes.inc"
.include "shell.inc"
.include "pently.inc"

.import ppu_clear_nt, ppu_clear_oam, ppu_screen_on, getTVSystem
.importzp NUM_SONGS
.exportzp cur_keys, new_keys, tvSystem, nmis

.segment "ZEROPAGE"
nmis:          .res 1
oam_used:      .res 1
cur_song:      .res 1

; Used by pads.s
cur_keys:  .res 2
new_keys:  .res 2

; Used by music engine
tvSystem:   .res 1


.segment "INESHDR"
  .byt "NES",$1A  ; magic signature
  .byt 1          ; PRG ROM size in 16384 byte units
  .byt 1          ; CHR ROM size in 8192 byte units
  .byt $00        ; mirroring type and mapper number lower nibble
  .byt $00        ; mapper number upper nibble

.segment "VECTORS"
.addr nmi, reset, irq

.segment "CODE"
;;
; This NMI handler is good enough for a simple "has NMI occurred?"
; vblank-detect loop.  But sometimes there are things that you always
; want to happen every frame, even if the game logic takes far longer
; than usual.  These might include music or a scroll split.  In these
; cases, you'll need to put more logic into the NMI handler.
.proc nmi
  inc nmis
  rti
.endproc

; A null IRQ handler that just does RTI is useful to add breakpoints
; that survive a recompile.  Set your debugging emulator to trap on
; reads of $FFFE, and then you can BRK $00 whenever you need to add
; a breakpoint.
;
; But sometimes you'll want a non-null IRQ handler.
; On NROM, the IRQ handler is mostly used for the DMC IRQ, which was
; designed for gapless playback of sampled sounds but can also be
; (ab)used as a crude timer for a scroll split (e.g. status bar).
.proc irq
  rti
.endproc

; 
.proc reset
  ; The very first thing to do when powering on is to put all sources
  ; of interrupts into a known state.
  sei             ; Disable interrupts
  ldx #$00
  stx PPUCTRL     ; Disable NMI and set VRAM increment to 32
  stx PPUMASK     ; Disable rendering
  stx $4010       ; Disable DMC IRQ
  dex             ; Subtracting 1 from $00 gives $FF, which is a
  txs             ; quick way to set the stack pointer to $01FF
  bit PPUSTATUS   ; Acknowledge stray vblank NMI across reset
  bit SNDCHN      ; Acknowledge DMC IRQ
  lda #$40
  sta P2          ; Disable APU Frame IRQ
  lda #$0F
  sta SNDCHN      ; Disable DMC playback, initialize other channels

vwait1:
  bit PPUSTATUS   ; It takes one full frame for the PPU to become
  bpl vwait1      ; stable.  Wait for the first frame's vblank.

  ; Turn off decimal mode for post-patent famiclones
  cld

  ; Clear OAM and the zero page here.
  ldx #0
  stx cur_song
  jsr ppu_clear_oam  ; clear out OAM from X to end and set X to 0
  jsr pently_init

vwait2:
  bit PPUSTATUS  ; After the second vblank, we know the PPU has
  bpl vwait2     ; fully stabilized.  After this use only NMI.
  
  jsr display_todo
  jsr getTVSystem
  sta tvSystem
  lda cur_song
  jsr pently_start_music

forever:
  lda #0
  sta oam_used

  lda #8
  tax
  lda cur_song
  asl a
  asl a
  asl a
  clc
  adc #27
  tay
  lda #0
  jsr draw_y_arrow_sprite

  jsr pently_get_beat_fraction
  clc
  adc #64
  tax
  ldy #219
  lda #0
  jsr draw_y_arrow_sprite
  
  ldx oam_used
  jsr ppu_clear_oam

  lda nmis
:
  cmp nmis
  beq :-

  lda #VBLANK_NMI
  sta PPUCTRL
  lda #$23
  sta PPUADDR
  lda #$62
  sta PPUADDR
  lda pently_row_beat_part
  beq :+
  lda #'.'^':'
:
  eor #':'
  sta PPUDATA
  lda pently_row_beat_part
  and #$0F
  ora #'0'
  sta PPUDATA
  lda #'/'
  sta PPUDATA
  lda pently_rows_per_beat
  and #$0F
  ora #'0'
  sta PPUDATA
  
  ldx #0
  stx OAMADDR
  lda #>OAM
  sta OAM_DMA
  ldy #0
  lda #VBLANK_NMI|BG_0000|OBJ_0000
  sec
  jsr ppu_screen_on

  jsr pently_update
  jsr read_pads
  lda cur_keys
  and #KEY_SELECT
  beq notFastForward
  jsr pently_update
  jsr pently_update
  jsr pently_update
notFastForward:
  
  lda new_keys
  and #KEY_DOWN
  beq notDown
  inc cur_song
  lda cur_song
  cmp #NUM_SONGS
  bcc notWrapDown
  lda #0
  sta cur_song
notWrapDown:
  jsr pently_start_music
notDown:

  lda new_keys
  and #KEY_UP
  beq notUp
  dec cur_song
  lda cur_song
  cmp #NUM_SONGS
  bcc notWrapUp
  lda #NUM_SONGS-1
  sta cur_song
notWrapUp:
  jsr pently_start_music
notUp:

  jmp forever
.endproc

.proc display_todo
  lda #VBLANK_NMI
  ldx #$00
  ldy #$3F
  sta PPUCTRL
  stx PPUMASK
  sty PPUADDR
  stx PPUADDR
copypal:
  lda main_palette,x
  sta PPUDATA
  inx
  cpx #32
  bcc copypal

  lda #$00
  tay
  ldx #$20
  jsr ppu_clear_nt

  lda #$20
  sta 1
  lda #$62
  sta 0
  lda #<tracknames_txt
  sta 2
  lda #>tracknames_txt
  sta 3
todo_rowloop:
  ldy 1
  sty PPUADDR
  ldy 0
  sty PPUADDR
  ldy #0
todo_charloop:
  lda (2),y
  beq todo_done
  cmp #$0A
  beq is_newline
  sta PPUDATA
  iny
  bne todo_charloop
is_newline:

  sec
  tya
  adc 2
  sta 2
  lda 3
  adc #0
  sta 3
  lda 0
  adc #32
  sta 0
  lda 1
  adc #0
  sta 1
  cmp #$23
  bcc todo_rowloop
  lda 0
  cmp #$E0
  bcc todo_rowloop
todo_done:
  rts
.endproc

;;
; @param Y vertical position
; @param X horizontal position
; @param A bit 7 on: draw left pointing
.proc draw_y_arrow_sprite
ypos = 0
tilepos = 1
flip = 2
xpos = 3

  stx xpos
  ldx oam_used
  sta OAM+2,x
  tya
  sec
  sbc #4
  sta OAM,x
  lda #'>'
  sta OAM+1,x
  lda xpos
  sta OAM+3,x
  txa
  clc
  adc #4
  sta oam_used
  rts
.endproc

.segment "RODATA"
tracknames_txt:
  .incbin "tracknames.txt"
  .byt 0

main_palette:
  .byt $0F,$00,$10,$30, $0F,$00,$10,$30, $0F,$00,$10,$30, $0F,$00,$10,$30
  .byt $0F,$00,$10,$30, $0F,$00,$10,$30, $0F,$00,$10,$30, $0F,$00,$10,$30

.segment "CHR"
  .incbin "obj/nes/bggfx.chr"
