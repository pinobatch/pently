;
; Pently audio engine
; Player shell as self-contained NES executable
;
; Copyright 2009-2017 Damian Yerrick
; 
; This software is provided 'as-is', without any express or implied
; warranty.  In no event will the authors be held liable for any damages
; arising from the use of this software.
; 
; Permission is granted to anyone to use this software for any purpose,
; including commercial applications, and to alter it and redistribute it
; freely, subject to the following restrictions:
; 
; 1. The origin of this software must not be misrepresented; you must not
;    claim that you wrote the original software. If you use this software
;    in a product, an acknowledgment in the product documentation would be
;    appreciated but is not required.
; 2. Altered source versions must be plainly marked as such, and must not be
;    misrepresented as being the original software.
; 3. This notice may not be removed or altered from any source distribution.
;

.include "nes.inc"
.include "shell.inc"
.include "pently.inc"

.import getTVSystem
.importzp NUM_SONGS

; Size diagnostics
.import periodTableHi, periodTableLo
PERIOD_SIZE = (periodTableHi - periodTableLo) * 2
PENTLY_SIZE = PENTLYMUSIC_SIZE + PENTLYSOUND_SIZE + PERIOD_SIZE

.segment "ZEROPAGE"
nmis:          .res 1
oam_used:      .res 1
cur_song:      .res 1
is_fast_forward:.res 1

; Used by pads.s
cur_keys:  .res 2
new_keys:  .res 2

; Used by music engine
tvSystem:   .res 1

TRACKNAMES_TOP = 3
TRACKNAMES_ADDR = $2000 + 32 * TRACKNAMES_TOP + 2
STATUS_BAR_TOP = 24
STATUS_BAR_ADDR = $2000 + 32 * STATUS_BAR_TOP
BEAT_POS_ADDR = STATUS_BAR_ADDR + 32 * 1 + 2
CYCLES_ADDR = STATUS_BAR_ADDR + 32 * 1 + 25
ROM_SIZE_ADDR = STATUS_BAR_ADDR + 32 * 2 + 2
WORD_PEAK_ADDR = STATUS_BAR_ADDR + 32 * 2 + 21
PEAK_ADDR = WORD_PEAK_ADDR + 4

.segment "INESHDR"
  .byt "NES",$1A  ; magic signature
  .byt 1          ; PRG ROM size in 16384 byte units
  .byt 1          ; CHR ROM size in 8192 byte units
  .byt $01        ; mirroring type and mapper number lower nibble
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
  bit SNDCHN      ; Acknowledge DMC IRQ
  lda #$40
  sta P2          ; Disable APU Frame IRQ
  lda #$0F
  sta SNDCHN      ; Disable DMC playback, initialize other channels
  cld             ; Turn off decimal mode on certain famiclones

  jsr getTVSystem ; Wait for the PPU to stabilize
  sta tvSystem

  ; Initialize used memory
  jsr pently_init
  jsr display_tracknames
  jsr clear_rehearsal
  
  lda #0
  sta cur_song
  jsr pently_start_music

  ; Set up sprite 0 hit, on the same line as the status bar
  lda #2
  sta OAM+1  ; tile number
  lda #STATUS_BAR_TOP * 8 - 1
  sta OAM+0  ; Y position
  lda #0
  sta OAM+2  ; attribute
  sta OAM+3  ; X position
  sta cyclespeakhi
  sta cyclespeaklo

  ; Present one frame with only sprite 0 to prime the profiler
  lda #4
  sta oam_used

forever:
  ldx oam_used
  jsr ppu_clear_oam

  ; Wait for vblank
  lda nmis
  :
    cmp nmis
    beq :-

  ; Upload display list to OAM
  ldx #0
  stx OAMADDR
  lda #>OAM
  sta OAM_DMA

  ; Write cycle count
  lda #VBLANK_NMI
  sta PPUCTRL
  lda #>CYCLES_ADDR
  sta PPUADDR
  lda #<CYCLES_ADDR
  sta PPUADDR
  ldx #4
  :
    lda cyc_digits,x
    sta PPUDATA
    dex
    bpl :-
  lda #>PEAK_ADDR
  sta PPUADDR
  lda #<PEAK_ADDR
  sta PPUADDR
  ldx #4
  :
    lda peak_digits,x
    sta PPUDATA
    dex
    bpl :-

  ; Write beat marker
  lda #$23
  sta PPUADDR
  lda #$22
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
  
  ; Turn the display on
  ldy #0
  ldx #0
  lda #VBLANK_NMI|BG_0000|OBJ_0000
  sec
  jsr ppu_screen_on

  jsr run_profiler
  jsr read_pads
  lda cur_keys
  and #KEY_SELECT
  beq :+
    lda #$80
  :
  sta is_fast_forward
  
  lda new_keys
  and #KEY_DOWN
  beq notDown
    inc cur_song
    lda cur_song
    cmp #NUM_SONGS
    bcc have_new_song
    lda #0
    jmp have_new_song
  notDown:

  lda new_keys
  and #KEY_UP
  beq notUp
    dec cur_song
    lda cur_song
    cmp #NUM_SONGS
    bcc have_new_song
      lda #NUM_SONGS-1
    have_new_song:
    sta cur_song
    jsr pently_start_music
    lda #0
    sta cyclespeakhi
    sta cyclespeaklo
  notUp:

  ; Prepare the next frame
  lda #4
  sta oam_used

  ldx #8
  lda cur_song
  asl a
  asl a
  asl a
  clc
  adc #TRACKNAMES_TOP*8+3
  tay
  lda #0
  jsr draw_y_arrow_sprite

  jsr pently_get_beat_fraction
  clc
  adc #64
  tax
  ldy #STATUS_BAR_TOP*8+11
  lda #0
  jsr draw_y_arrow_sprite

  jmp forever
.endproc


.proc puts_multiline_ay
src = $00
dst = $02
  sta src+1
  sty src+0
  lineloop:
    ldy dst+1
    sty PPUADDR
    ldy dst+0
    sty PPUADDR
    ldy #0
    charloop:
      lda (src),y
      beq done
      cmp #$0A
      beq is_newline
      sta PPUDATA
      iny
      bne charloop
    is_newline:

    ; Add Y (length before newline) plus 1 to text pointer
    ;sec  ; CMP already set carry
    tya
    adc src
    sta src
    lda src+1
    adc #0
    sta src+1
    lda dst
    adc #32
    sta dst
    lda dst+1
    adc #0
    sta dst+1

    ; crop to the status bar top
    ; (things below it are limited to 1 line tall)
    lda dst+0
    cmp #<STATUS_BAR_ADDR
    lda dst+1
    sbc #>STATUS_BAR_ADDR
    bcc lineloop
  done:
  rts
.endproc

.proc display_tracknames
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

src = $00
dst = $02
  lda #<TRACKNAMES_ADDR
  sta dst+0
  lda #>TRACKNAMES_ADDR
  sta dst+1
  ldy #<tracknames_txt
  lda #>tracknames_txt
  jsr puts_multiline_ay

  lda #<ROM_SIZE_ADDR
  sta dst+0
  lda #>ROM_SIZE_ADDR
  sta dst+1
  ldy #<bytes_txt
  lda #>bytes_txt
  jsr puts_multiline_ay
  lda #$20
.endproc

;;
; Draw the status bar on a nametable.
; @param A $20, $24, $28, or $2C
.proc draw_status_bar_top
whichnt = $00
  ora #>STATUS_BAR_ADDR
  sta whichnt
  sta PPUADDR
  lda #<STATUS_BAR_ADDR
  sta PPUADDR
  lda #$02  ; status bar top blank tile
  ldx #32
  :
    sta PPUDATA
    dex
    bne :-

  ; Draw graphics in top of status bar
  ldx #$08  ; "Pently demo"
  lda #<STATUS_BAR_ADDR + 2
  ldy #8
  jsr logopart

  ldx #$14  ; "Copr. 20xx Damian Yerrick"
  lda #<STATUS_BAR_ADDR + 30 - 12
  ldy #12
logopart:
  pha
  lda whichnt
  sta PPUADDR
  pla
  sta PPUADDR
  logoloop:
    stx PPUDATA
    inx
    dey
    bne logoloop
  rts
.endproc

.proc clear_rehearsal
  ldx #$24
  lda #' '
  ldy #0
  tay
  jsr ppu_clear_nt
  lda #$24
  jmp draw_status_bar_top
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

bytes_txt:
  .byt "ROM:"
  .byt '0'|<((PENTLY_SIZE / 1000) .MOD 10)
  .byt '0'|<((PENTLY_SIZE / 100) .MOD 10)
  .byt '0'|<((PENTLY_SIZE / 10) .MOD 10)
  .byt '0'|<((PENTLY_SIZE / 1) .MOD 10)
  .byt " bytes     Peak",0


main_palette:
  .byt $0F,$00,$10,$30, $0F,$00,$10,$30, $0F,$00,$10,$30, $0F,$00,$10,$30
  .byt $0F,$00,$10,$30, $0F,$00,$10,$30, $0F,$00,$10,$30, $0F,$00,$10,$30

.segment "CHR"
  .incbin "obj/nes/bggfx.chr"
