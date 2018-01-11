.include "pentlyconfig.inc"
.include "pently.inc"
.include "nes.inc"
.include "shell.inc"
.import pently_rehearsal_marks

; At first, the plan was to make the visualization/rehearsal screen
; inaccessible unless visualization or rehearsal is enabled.  It was
; later decided to put the track muting controls in the same screen.

; Local TODO for https://github.com/pinobatch/pently/issues/27
; 1. Find rehearsal mark corresponding to current song row
; 2. 
; 3. Display arrow at current rehearsal mark
; 4. Check issue
; 5. Seek to previous or next rehearsal mark
; 6. Check issue
; 7. Default song and rehearsal mark when building ROM
; 8. Tempo scaling
; 9. Playback stepping a row at a time
; 10. Bar check
; 11. Continue to watch for grace note glitches
; 12. Track mute/solo

.zeropage
vis_to_clear: .res 1
.if PENTLY_USE_REHEARSAL
  vis_cur_song_section: .res 1
  vis_num_sections: .res 1
  vis_section_load_row: .res 1
  vis_section_src: .res 2
.endif

; Injection palette
.if PENTLY_USE_VIS
  vis_pulse1_color: .res 1
  vis_pulse2_color: .res 1
  vis_tri_color: .res 1
  vis_noise_color: .res 1
.endif

CH_TRI = $08
CH_NOISE = $0C
CH_END = $10

copydst_lo = $0180
copydst_hi = $0181
copybuf = $0100
LF = $0A

songrow = 35
caporow = 36

.code
.proc vis
  .if ::PENTLY_USE_REHEARSAL
    lda #caporow
    sta vis_section_load_row
    lda #2
    sta vis_to_clear
  .else
    lda #$FF
    sta vis_section_load_row
    lda #1
    sta vis_to_clear
  .endif

  jsr load_song_title
  

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

  ; Clearing nametable must be FAST
  lda vis_to_clear
  beq vis_cleared
    jsr vis_clear_part
    lda #VBLANK_NMI|OBJ_1000|BG_0000|0
    bne have_which_nt
  vis_cleared:
    lda #>OAM
    sta OAM_DMA
    .if ::PENTLY_USE_VIS
      ; Update palette
      lda #$3F
      sta PPUADDR
      lda #$11
      sta PPUADDR
      lda vis_pulse1_color
      ldx vis_noise_color
      sta PPUDATA
      stx PPUDATA
      bit PPUDATA
      bit PPUDATA
      lda vis_pulse2_color
      sta PPUDATA
      bit PPUDATA
      bit PPUDATA
      bit PPUDATA
      lda vis_tri_color
      sta PPUDATA
    .endif
    
    lda copydst_hi
    bmi nocopy
      sta PPUADDR
      lda copydst_lo
      sta PPUADDR
      ldx #0
      :
        lda copybuf,x
        sta PPUDATA
        inx
        cpx #32
        bcc :-
    
    nocopy:
    lda #VBLANK_NMI|OBJ_1000|BG_0000|1
    sta copydst_hi
  have_which_nt:

  ldx #0
  ldy #0
  sec
  jsr ppu_screen_on
  jsr pently_update
  jsr read_pads
  ldx #4
  stx oam_used
  jsr vis_prepare_vram_row
  .if ::PENTLY_USE_VIS
    jsr vis_update_obj
  .endif
  
  .if ::PENTLY_USE_REHEARSAL
    lda new_keys
    and #KEY_DOWN
    beq notDown
      clc
      ldx pently_rowshi
      lda pently_rowslo
      adc #128
      bcc :+
        inx
      :
      jsr pently_skip_to_row
    
    notDown:
  .endif

  lda new_keys
  and #KEY_B|KEY_LEFT
  bne vis_done
  jmp vis_loop
vis_done:
  rts
.endproc

; Song name and section names ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc clear_copybuf
  tya
  sec
  ror a
  sta copydst_hi
  lda #0
  ror a
  lsr copydst_hi
  ror a
  lsr copydst_hi
  ror a
  sta copydst_lo
  ldx #31
  lda #' '
  :
    sta copybuf,x
    dex
    bpl :-
  bail:
  rts
.endproc

.proc load_song_title
bail = clear_copybuf::bail
src = $00
newlines_left = $03
  ldy #songrow
  jsr clear_copybuf
  lda #>tracknames_txt
  ldy #<tracknames_txt
  sta src+1

  lda cur_song
  beq found
  sta newlines_left
  lda #0
  sta src+0
  searchloop:
    lda (src),y
    beq bail
    iny
    bne :+
      inc src+1
    :
    cmp #LF
    bne searchloop
    dec newlines_left
    bne searchloop
  found:
  sty src+0
  ldx #2
.endproc
.proc print_to_copybuf
src = $00
  ldy #0
  copyloop:
    lda (src),y
    beq not_found
    cmp #LF
    beq not_found
    sta copybuf,x
    iny
    inx
    cpx #32
    bcc copyloop
  not_found:
  rts
.endproc

.proc vis_clear_part
  clc
  adc #$23
  sta PPUADDR
  lda #$80
  sta PPUADDR
  lda #' '
  ldx #64
  :
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    sta PPUDATA
    dex
    bne :-
  dec vis_to_clear
bail:
  rts
.endproc

.proc vis_prepare_vram_row
nope = vis_clear_part::bail
src = $00

  ; Ensure there's something to load
  ldy vis_section_load_row
  bmi nope
  
  ; and room to load it
  lda copydst_hi
  bpl nope

  jsr clear_copybuf
  lda vis_section_load_row
  sec
  sbc #caporow + 1
  bcs past_caporow
    ; 'Capo' row: Load the word "capo"
    lda #'c'
    sta copybuf+3
    lda #'a'
    sta copybuf+4
    lda #'p'
    sta copybuf+5
    lda #'o'
    sta copybuf+6

    ; With that out of the way, we can find the rehearsal marks
    lda cur_song
    asl a
    tax
    lda pently_rehearsal_marks,x
    sta vis_section_src+0
    lda pently_rehearsal_marks+1,x
    sta vis_section_src+1
    ldy #0
    lda (vis_section_src),y
    sta $5555
    sta vis_num_sections
    beq no_marks_left

    ; Skip past the row counts to the mark names
    asl a
    adc #2
    adc vis_section_src
    sta vis_section_src
    bcc :+
      inc vis_section_src+1
    :
    inc vis_section_load_row
    rts
  past_caporow:
    lda vis_section_src
    sta src
    lda vis_section_src+1
    sta src+1
    ldx #3
    jsr print_to_copybuf
    
    ; If at NUL terminator, stop
    cmp #0
    beq no_marks_left

    ; Move to next piece
    sec
    tya
    adc vis_section_src
    sta vis_section_src
    bcc :+
      inc vis_section_src+1
    :
    inc vis_section_load_row
    rts

no_marks_left:
  lda #$FF
  sta vis_section_load_row

.endproc

; Visualizer ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

VIS_PITCH_Y = 183
TARGET_NOTE_DOT_TILE = $13

.if PENTLY_USE_VIS

.proc vis_update_obj
semitonenum = $08
overtone_x = $09
effective_vol = $0A
semitone_xlo = $0C
semitone_xhi = $0D

  ldy #4

  ; Y: OAM index; X: channel
  ldx #0
  chloop:
    ; Draw pitch/volume marks
    lda pently_vis_dutyvol,x
    and #$0F
    beq pitchvol_mark_done  ; Draw no such mark for silent channels
      jmp draw_pitchvol_mark
    pitchvol_mark_done:

    ; Draw target note marks for pulse 1, pulse 2 and triangle
    cpx #CH_NOISE
    bcs target_note_mark_done
      jmp draw_target_note_mark
    target_note_mark_done:
    inx
    inx
    inx
    inx
    cpx #CH_END
    bcc chloop
  sty oam_used

  ; Calculate palette based on attack injection
  ldx #$20
  lda pently_vis_arpphase+0
  bmi pulse1_injected
    ldx #$26
  pulse1_injected:
  stx vis_pulse1_color

  ldx #$20
  lda pently_vis_arpphase+4
  bmi pulse2_injected
    ldx #$2A
  pulse2_injected:
  stx vis_pulse2_color

  ldx #$20
  lda pently_vis_arpphase+CH_TRI
  bmi tri_injected
    ldx #$12
  tri_injected:
  stx vis_tri_color

  ; Calculate noise palette based on color
  ldx #$10
  lda pently_vis_pitchhi+CH_NOISE
  bpl noise_is_hiss
    ldx #$28
  noise_is_hiss:
  stx vis_noise_color
  rts
    
draw_pitchvol_mark:
  lsr a
  cpx #CH_TRI
  bne :+
    lda #0
  :
  sta effective_vol

  lda pently_vis_pitchhi,x
  cpx #CH_NOISE
  bne st_not_noise
    stx semitone_xlo
    and #$0F
    tax
    lda noise_to_sprite_x,x
    ldx semitone_xlo
    jmp have_semitone_xhi
  st_not_noise:

  ; Triangle draws the lowest octave as hollow and the other
  ; octaves as solid, except offset an octave to the left because
  ; it sounds an octave below pulse.
  cpx #CH_TRI
  bne have_semitonenum
    sta semitonenum
    cmp #12  ; C=0 for hollow (lowest) octave, 1 for solid octaves
    lda #3 * 12 * 5
    bcs :+
      lda #3 * 12 * 4
      inc effective_vol
    :
    sta overtone_x
    lda semitonenum
    bcc :+
      sbc #12
    :
  have_semitonenum:
  sta semitonenum
  sta semitone_xhi
  lda pently_vis_pitchlo,x
  asl a
  rol semitone_xhi
  sta semitone_xlo
  clc
  adc pently_vis_pitchlo,x
  bpl :+
    inc semitone_xhi
  :
  lda semitonenum
  adc semitone_xhi
  clc
  adc #16
have_semitone_xhi:
  sta semitone_xhi

  lda #VIS_PITCH_Y  ; Y position
  sta OAM+0,y
  lda effective_vol
  ora vis_ch_vol_tiles,x
  sta OAM+1,y
  lda vis_ch_attribute,x
  sta OAM+2,y
  lda semitone_xhi
  sta OAM+3,y
  iny
  iny
  iny
  iny

  cpx #CH_TRI
  bne no_overtone_mark
  clc
  adc overtone_x
  bcs no_overtone_mark
    sta OAM+3,y
    lda #VIS_PITCH_Y
    sta OAM+0,y
    lda #$12  ; triangle overtone mark
    sta OAM+1,y
    lda #$02  ; triangle attribute
    sta OAM+2,y
    iny
    iny
    iny
    iny
  no_overtone_mark:
  jmp pitchvol_mark_done

draw_target_note_mark:
  ; First, is this a black key or a white key?
  lda pently_vis_note,x
  cmp #96
  bcc :+
    sbc #96
  :
  cmp #48
  bcc :+
    sbc #48
  :
  cmp #24
  bcc :+
    sbc #24
  :
  cmp #12
  bcc :+
    sbc #12
  :
  
  stx semitone_xlo
  tax
  lda whitekey_pos,x
  lsr a
  ldx semitone_xlo
  sta semitone_xhi
  
  lda vis_ch_whitekey_y,x
  bcc :+
    lda vis_ch_blackkey_y,x
  :
  sta OAM+0,y
  lda #TARGET_NOTE_DOT_TILE
  sta OAM+1,y
  lda vis_ch_attribute,x
  sta OAM+2,y
  
  ; Find the X position of the mark
  lda pently_vis_note,x
  cpx #CH_TRI
  bne target_not_trioctave
  cmp #12
  bcc target_not_trioctave
    sbc #12
  target_not_trioctave:
  sta semitonenum
  asl a
  clc
  adc semitonenum
  clc
  adc semitone_xhi
  sta OAM+3,y
  iny
  iny
  iny
  iny
  jmp target_note_mark_done
.endproc

.rodata

vis_ch_whitekey_y:
  ; 0. Y base for white keys
  ; 1. Y position for black keys
  ; 2. Tile base (for volume)
  ; 3. attribute
  .byte 170, 157, $00, 0
  .byte 172, 161, $00, 1
  .byte 174, 165, $10, 2
  .byte 255, 255, $08, 0
vis_ch_blackkey_y = vis_ch_whitekey_y + 1
vis_ch_vol_tiles = vis_ch_whitekey_y + 2
vis_ch_attribute = vis_ch_whitekey_y + 3

; Approximate X positions of noise pitches, assuming 93-step
; waveform.
noise_to_sprite_x:
  .byte 248, 212, 176, 140, 104, 83, 68, 57, 45, 33, 12
  ; The following are not to scale with the rest of the keyboard.
  ; If they were, they'd lie to the left of the keyboard's left edge.
  .byte 10, 8, 6, 3, 0

whitekey_pos:
  .byte 16*2+0
  .byte       16*2+1
  .byte 15*2+0
  .byte 17*2+0
  .byte       16*2+1
  .byte 16*2+0
  .byte       16*2+1
  .byte 15*2+0
  .byte 17*2+0
  .byte       16*2+1
  .byte 16*2+0
  .byte       16*2+1

.endif  ; PENTLY_USE_VIS
