.include "pentlyconfig.inc"
.include "pently.inc"
.if PENTLY_USE_VIS  ; Skip the whole thing if visualization is off
.include "nes.inc"
.include "shell.inc"

.zeropage
vis_to_clear: .res 1
vis_num_song_sections: .res 1
vis_song_sections_ok: .res 1

.code
.proc vis
  lda #0
  sta vis_song_sections_ok
  lda #2
  sta vis_to_clear
  ldx #4
  stx oam_used
vis_loop:
  ldx oam_used
  jsr ppu_clear_oam

  ; Wait for vblank
  lda nmis
  :
    cmp nmis
    beq :-
  lda vis_to_clear
  beq vis_cleared
    jsr vis_clear_part
    lda #VBLANK_NMI|OBJ_1000|BG_0000|0
    bne have_which_nt
  vis_cleared:
    lda #>OAM
    sta OAM_DMA
    lda #VBLANK_NMI|OBJ_1000|BG_0000|1
  have_which_nt:
  ldx #0
  ldy #0
  sec
  jsr ppu_screen_on
  jsr pently_update
  jsr read_pads
  ldx #4
  stx oam_used

  lda new_keys
  and #KEY_B
  bne vis_done
  jmp vis_loop
vis_done:
  rts
.endproc

.endif  ; PENTLY_USE_VIS

.proc vis_clear_part
  clc
  adc #$23
  sta PPUADDR
  lda #$60
  sta PPUADDR
  lda #'.'
  ldx #72
  :
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    dex
    bne :-
  dec vis_to_clear
  rts
.endproc

.proc vis_update_vram
  rts
.endproc