;
; Pently audio engine
; Music interpreter and instrument renderer
;
; Copyright 2009-2018 Damian Yerrick
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

.include "pentlyseq.inc"
.include "pently.inc"
.include "../obj/nes/pentlybss.inc"

.importzp pently_zp_state
.import pentlyBSS
.import periodTableLo, periodTableHi
.export pentlyi_update_music, pentlyi_update_music_ch
.if PENTLY_USE_ATTACK_PHASE && PENTLY_USE_NOISE_POOLING
  .export pentlyi_attackPitch, pentlyi_attackLen, pentlyi_noteAttackPos
.endif
.if PENTLY_USE_PAL_ADJUST
.importzp tvSystem
.endif

.if PENTLY_USE_ROW_CALLBACK
.import pently_row_callback, pently_dalsegno_callback
.endif

PENTLY_NUM_CHANNELS = 4
PENTLY_DRUM_TRACK = 12
PENTLY_ATTACK_TRACK = 16
PENTLY_MAX_CHANNEL_VOLUME = 4
PENTLY_INITIAL_TEMPO = 300
PENTLY_INITIAL_ROW_LENGTH = 4
PENTLY_MAX_TEMPO_SCALE = 8

.if PENTLY_USE_ATTACK_TRACK
  PENTLY_LAST_TRACK = PENTLY_ATTACK_TRACK
.else
  PENTLY_LAST_TRACK = PENTLY_DRUM_TRACK
.endif

PENTLY_USE_TEMPO_ROUNDING = PENTLY_USE_TEMPO_ROUNDING_SEGNO || (PENTLY_USE_TEMPO_ROUNDING_PLAY_CH >= 0) || PENTLY_USE_TEMPO_ROUNDING_BEAT

; pently_zp_state (PENTLY_USE_ATTACK_PHASE = 1)
;       +0                +1                +2                +3
;  0  | Sq1 sound effect data ptr           Sq1 music pattern data ptr
;  4  | Sq2 sound effect data ptr           Sq2 music pattern data ptr
;  8  | Tri sound effect data ptr           Tri music pattern data ptr
; 12  | Noise sound effect data ptr         Noise music pattern data ptr
; 16  | Sq1 envelope data ptr               Attack music pattern data ptr
; 20  | Sq2 envelope data ptr               Conductor track position
; 24  | Tri envelope data ptr               Tempo counter
; 28  | Noise envelope data ptr             Play/Pause        Attack channel
;
; pently_zp_state (PENTLY_USE_ATTACK_PHASE = 0)
;       +0                +1                +2                +3
;  0  | Sq1 sound effect data ptr           Sq1 music pattern data ptr
;  4  | Sq2 sound effect data ptr           Sq2 music pattern data ptr
;  8  | Tri sound effect data ptr           Tri music pattern data ptr
; 12  | Noise sound effect data ptr         Noise music pattern data ptr
; 16  | Conductor track position            Tempo counter
; 20  | Play/Pause

.zeropage
; ASM6 translation quirk:
; The delay_labels mechanism to reduce forward references to
; pently_zp_state and pentlymusicbase does not work correctly
; if the references are in a .if block.  So move them to
; .zeropage so that delay_labels will not touch them.

pentlyi_chnPatternPos = pently_zp_state + 2
.if PENTLY_USE_ATTACK_PHASE
  pentlyi_noteAttackPos   = pently_zp_state + 16
  pentlyi_conductorPos    = pently_zp_state + 22
  pently_tempoCounterLo   = pently_zp_state + 26
  pently_tempoCounterHi   = pently_zp_state + 27
  pently_music_playing    = pently_zp_state + 30
  pentlyi_attackChn       = pently_zp_state + 31
.else
  pentlyi_conductorPos    = pently_zp_state + 16
  pently_tempoCounterLo   = pently_zp_state + 18
  pently_tempoCounterHi   = pently_zp_state + 19
  pently_music_playing    = pently_zp_state + 20
.endif

.bss
; Statically allocated so as not to be cleared by the clear loop
pentlyi_conductorSegnoLo        = pentlyBSS + 16
pentlyi_conductorSegnoHi        = pentlyBSS + 17

; The rest is allocated by pentlybss.py
; Noise envelope is NOT unused.  Conductor track cymbals use it.
pentlymusicbase: .res pentlymusicbase_size

; Visualize particular notes within a playing score
.if PENTLY_USE_ARPEGGIO || PENTLY_USE_ATTACK_TRACK
  pently_vis_arpphase = pentlyi_arpPhase
.endif
.if PENTLY_USE_PORTAMENTO
  pently_vis_note = pentlyi_notePitch
.else
  pently_vis_note = pentlyi_chPitchHi
.endif

.segment PENTLY_RODATA
pentlymusic_rodata_start = *

FRAMES_PER_MINUTE_PAL = 3000
FRAMES_PER_MINUTE_NTSC = 3606
FRAMES_PER_MINUTE_GB = 3584  ; not used in NES port
FRAMES_PER_MINUTE_SGB = 3670  ; not used in NES port
pently_fpmLo:
  .byt <FRAMES_PER_MINUTE_NTSC, <FRAMES_PER_MINUTE_PAL, <FRAMES_PER_MINUTE_PAL
pently_fpmHi:
  .byt >FRAMES_PER_MINUTE_NTSC, >FRAMES_PER_MINUTE_PAL, >FRAMES_PER_MINUTE_PAL

pentlyi_silent_pattern:  ; a pattern consisting of a single whole rest
  .byt 26*8+7, 255
pentlyi_durations:
  .byt 1, 2, 3, 4, 6, 8, 12, 16

.if PENTLY_USE_VIBRATO
PENTLY_PREVIBRATO_PERIOD = 11
PENTLY_VIBRATO_PERIOD = 12
; bit 7: negate; bits 6-0: amplitude in units of 1/128 semitone
pentlyi_vibrato_pattern:
  .byt $88,$8B,$8C,$8B,$88,$00,$08,$0B,$0C,$0B,$08
.endif

.if PENTLY_USE_PORTAMENTO
pentlyi_porta1x_rates_lo:
  .byte 4, 8, 12, 16, 24, 32, 48, 64, 96, 128, 128
pentlyi_porta1x_rates_hi:
  .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
.endif

.segment PENTLY_CODE
pentlymusic_code_start = *

.proc pently_start_music
  ; Fetch initial conductor track position (limit 128 songs)
  asl a
  tax
  lda pently_songs,x
  sta pentlyi_conductorPos
  sta pentlyi_conductorSegnoLo
  lda pently_songs+1,x
  sta pentlyi_conductorPos+1
  sta pentlyi_conductorSegnoHi

  ; Clear all music state except that shared with sound effects
  ldy #pentlymusicbase_size - 1
  lda #0
  .if ::PENTLY_USE_ATTACK_TRACK
    sta pentlyi_attackChn
  .endif
  :
    sta pentlymusicbase,y
    dey
    bpl :-

  ; Init each track's volume and play silent pattern
  ldx #PENTLY_LAST_TRACK
  channelLoop:
    lda #<pentlyi_silent_pattern
    sta pentlyi_chnPatternPos,x
    lda #>pentlyi_silent_pattern
    sta pentlyi_chnPatternPos+1,x
    tya  ; Y is $FF from the clear everything loop
    sta pentlyi_musicPattern,x
    .if ::PENTLY_USE_CHANNEL_VOLUME
      .if ::PENTLY_USE_ATTACK_TRACK
        cpx #PENTLY_ATTACK_TRACK
        bcs :+
      .endif
        lda #PENTLY_MAX_CHANNEL_VOLUME
        sta pentlyi_chVolScale,x
      :
    .endif
    dex
    dex
    dex
    dex
    bpl channelLoop

  ; Set tempo upcounter and beat part to wrap around
  ; the first time they are incremented
  lda #$FF
  sta pently_tempoCounterLo
  sta pently_tempoCounterHi
  .if ::PENTLY_USE_BPMMATH
    sta pently_row_beat_part
    lda #PENTLY_INITIAL_ROW_LENGTH
    sta pently_rows_per_beat
  .endif
  lda #<PENTLY_INITIAL_TEMPO
  sta pentlyi_tempoLo
  lda #>PENTLY_INITIAL_TEMPO
  sta pentlyi_tempoHi
  ; Fall through
.endproc
.proc pently_resume_music
  lda #1
  ; Fall through
.endproc
.proc pently_set_music_playing
  sta pently_music_playing
  rts
.endproc

.proc pently_stop_music
  lda #0
  beq pently_set_music_playing
.endproc

.proc pentlyi_update_music
  lda pently_music_playing
  beq music_not_playing

  ; This applies Bresenham's algorithm to tick generation: add
  ; rows per minute every frame, then subtract frames per minute
  ; when it overflows.  But
  .if ::PENTLY_USE_REHEARSAL
scaled_tempoHi  = pently_zptemp + 0

    lda pentlyi_tempoHi
    sta scaled_tempoHi
    lda pentlyi_tempoLo
    ldx pently_tempo_scale
    clc  ; allow have_scaled_tempoLo to round
    beq have_scaled_tempoLo
    cpx #PENTLY_MAX_TEMPO_SCALE
    bcs music_not_playing
    shiftLoop:
      lsr scaled_tempoHi
      ror a
      dex
      bne shiftLoop
    have_scaled_tempoLo:
    adc pently_tempoCounterLo
    sta pently_tempoCounterLo
    lda scaled_tempoHi
  .else
    lda pentlyi_tempoLo
    clc
    adc pently_tempoCounterLo
    sta pently_tempoCounterLo
    lda pentlyi_tempoHi
  .endif
  adc pently_tempoCounterHi
  sta pently_tempoCounterHi
  bcs pentlyi_next_row
music_not_playing:
  rts
.endproc

; Conductor reading ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc pentlyi_next_row
  ; Subtract tempo
  .if ::PENTLY_USE_PAL_ADJUST
    ldy tvSystem
  .else
    ldy #0
  .endif
  ; sec  ; carry was set by bcs in pentlyi_update_music
  lda pently_tempoCounterLo
  sbc pently_fpmLo,y
  sta pently_tempoCounterLo
  lda pently_tempoCounterHi
  sbc pently_fpmHi,y
  sta pently_tempoCounterHi

  .if ::PENTLY_USE_REHEARSAL
    inc pently_rowslo
    bne :+
      inc pently_rowshi
    :
  .endif
  .if ::PENTLY_USE_BPMMATH
    ; Update row
    ldy pently_row_beat_part
    iny
    cpy pently_rows_per_beat
    bcc :+
      .if ::PENTLY_USE_TEMPO_ROUNDING_BEAT
        jsr pentlyi_round_to_beat
      .endif
      ldy #0
    :
    sty pently_row_beat_part
  .endif

.if ::PENTLY_USE_ROW_CALLBACK
  jsr pently_row_callback
.endif

  ; If in middle of waitRows, don't process conductor
  lda pentlyi_songWaitRows
  beq doConductor
  dec pentlyi_songWaitRows
  jmp pentlyi_read_patterns

doConductor:
  ldy #0
  lda (pentlyi_conductorPos),y
  inc pentlyi_conductorPos
  bne :+
    inc pentlyi_conductorPos+1
  :
  cmp #PENTLY_CON_WAITROWS
  beq is_waitrows
  bcs not_playpat
    ; 00-07 pp tt ii: Play pattern pp on track A & $07,
    ; transposed up tt semitones, with instrument ii
    and #$07
    asl a
    asl a
    tax
    .if ::PENTLY_USE_TEMPO_ROUNDING_PLAY_CH >= 0
      cpx #PENTLY_USE_TEMPO_ROUNDING_PLAY_CH
      bne not_round_ch
        jsr pentlyi_round_to_beat
        ldx #PENTLY_USE_TEMPO_ROUNDING_PLAY_CH
        ldy #0
      not_round_ch:
    .endif

    lda #0
    cpx #PENTLY_ATTACK_TRACK
    ; If attack track is enabled, don't enable legato on attack
    ; track. Otherwise, don't start patterns on attack track at all
    ; because another variable overlaps it.
    .if ::PENTLY_USE_ATTACK_TRACK
      bcs skipClearLegato
    .else
      bcs skip3conductor
    .endif
      sta pentlyi_noteLegato,x  ; start all patterns with legato off
    skipClearLegato:

    lda (pentlyi_conductorPos),y
    sta pentlyi_musicPattern,x
    iny
    lda (pentlyi_conductorPos),y
    sta pentlyi_chBaseNote,x
    iny
    lda (pentlyi_conductorPos),y
    sta pentlyi_instrument,x
    jsr pentlyi_start_pattern
  skip3conductor:
    lda #3
    clc
    adc pentlyi_conductorPos
    sta pentlyi_conductorPos
    bcc :+
      inc pentlyi_conductorPos+1
    :
    jmp doConductor

  is_waitrows:
    ; 20 ww: Wait ww+1 rows
    lda (pentlyi_conductorPos),y
    sta pentlyi_songWaitRows
    inc pentlyi_conductorPos
    bne :+
      inc pentlyi_conductorPos+1
    :
    jmp pentlyi_read_patterns
  not_playpat:
  
  ; Loop control block 21-23
  cmp #PENTLY_CON_DALSEGNO
  beq is_dalsegno
  bcs not_loopcontrol
  cmp #PENTLY_CON_SEGNO
  bcs is_segno
    ; 21: Fine (end playback; set playing and tempo to 0)
    lda #0
    sta pently_music_playing
    sta pentlyi_tempoHi
    sta pentlyi_tempoLo
    .if ::PENTLY_USE_ROW_CALLBACK
      clc
      jmp pently_dalsegno_callback
   .else
      rts
   .endif
  is_segno:
    lda pentlyi_conductorPos
    sta pentlyi_conductorSegnoLo
    lda pentlyi_conductorPos+1
    sta pentlyi_conductorSegnoHi
    jmp segno_round
  is_dalsegno:
    lda pentlyi_conductorSegnoLo
    sta pentlyi_conductorPos
    lda pentlyi_conductorSegnoHi
    sta pentlyi_conductorPos+1
    .if ::PENTLY_USE_ROW_CALLBACK
      sec
      jsr pently_dalsegno_callback
    .endif
    .if ::PENTLY_USE_TEMPO_ROUNDING_SEGNO
    segno_round:
      jsr pentlyi_round_to_beat
    .else
      segno_round = doConductor
    .endif

    jmp doConductor
  not_loopcontrol:

  cmp #PENTLY_CON_NOTEON
  bcs not_setattack
    ; 24-26: Play attack track on channel A & $07
    .if ::PENTLY_USE_ATTACK_TRACK
      and #%00000011
      asl a
      asl a
      sta pentlyi_attackChn
    .endif
    jmp doConductor
  not_setattack:

  cmp #PENTLY_CON_SETTEMPO
  bcs not_noteon
    ; 28-2F nn ii: Play note nn with instrument ii on track A & $07
    and #%00000011
    asl a
    asl a
    tax
    lda (pentlyi_conductorPos),y
    inc pentlyi_conductorPos
    bne :+
      inc pentlyi_conductorPos+1
    :
    pha
    lda (pentlyi_conductorPos),y
    tay
    pla
    jsr pently_play_note
    jmp skipConductorByte
  not_noteon:
  
  cmp #PENTLY_CON_SETBEAT
  bcs not_tempo_change
    ; 30-37 tt: Set tempo to (A & $07) * 256 + tt
    and #%00000111
    sta pentlyi_tempoHi
    lda (pentlyi_conductorPos),y
    sta pentlyi_tempoLo
  skipConductorByte:
    inc pentlyi_conductorPos
    bne :+
      inc pentlyi_conductorPos+1
    :
    jmp doConductor
  not_tempo_change:
  
  cmp #PENTLY_CON_SETBEAT+8
  bcs not_set_beat
    .if ::PENTLY_USE_BPMMATH
      and #%00000111
      tay
      lda pentlyi_durations,y
      sta pently_rows_per_beat
      ldy #0
      sty pently_row_beat_part
    .endif
  not_set_beat:

  jmp doConductor
.endproc

; Pattern reading ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc pentlyi_read_patterns
  ldx #4 * (PENTLY_NUM_CHANNELS - 1)
  channelLoop:
    jsr pentlyi_read_pattern
    dex
    dex
    dex
    dex
    bpl channelLoop

  ; Process attack track last so it can override a just played attack
  .if ::PENTLY_USE_ATTACK_TRACK
    ldx #PENTLY_ATTACK_TRACK
    ;jmp pentlyi_read_pattern
    ; (that's a fallthrough)
  .else
    rts
  .endif
.endproc
.proc pentlyi_read_pattern
  lda pentlyi_noteRowsLeft,x
  beq anotherPatternByte
skipNote:
  dec pentlyi_noteRowsLeft,x
  rts

anotherPatternByte:
  ; Read one pattern byte.  If it's a loop, restart the pattern.
  lda (pentlyi_chnPatternPos,x)
  cmp #PENTLY_PATEND
  bne notStartPatternOver
    jsr pentlyi_start_pattern
    lda (pentlyi_chnPatternPos,x)
  notStartPatternOver:
  inc pentlyi_chnPatternPos,x
  bne patternNotNewPage
    inc pentlyi_chnPatternPos+1,x
  patternNotNewPage:

  cmp #PENTLY_INSTRUMENT
  bcc isNoteCmd
  sbc #PENTLY_INSTRUMENT
  cmp #num_patcmdhandlers  ; ignore invalid pattern commands
  bcs anotherPatternByte
  asl a
  tay
  lda patcmdhandlers+1,y
  pha
  lda patcmdhandlers,y
  pha
  rts

isNoteCmd:
  
  ; set the note's duration
  pha
  and #$07
  tay
  lda pentlyi_durations,y
  sta pentlyi_noteRowsLeft,x
  pla
  .if ::PENTLY_USE_VARMIX
    ldy pently_mute_track,x
    bmi isKeyOff
  .endif
  lsr a
  lsr a
  lsr a
  cmp #25
  bcc isTransposedNote
  beq notKeyOff
  isKeyOff:
    lda #0
    .if ::PENTLY_USE_ATTACK_TRACK
      cpx #PENTLY_ATTACK_TRACK
      bcs notKeyOff
    .endif
    .if ::PENTLY_USE_ATTACK_PHASE
      sta pentlyi_attackLen,x
    .endif
    sta pentlyi_sustainVol,x
  notKeyOff:
  jmp skipNote

  isTransposedNote:
    cpx #PENTLY_DRUM_TRACK
    beq isDrumNote
    clc
    adc pentlyi_chBaseNote,x
    ldy pentlyi_instrument,x
    jsr pently_play_note
    jmp skipNote

isDrumNote:
  .if ::PENTLY_USE_VARMIX
    ldy pently_mute_track+PENTLY_DRUM_TRACK
    bmi skipNote
  .endif
  asl a
  pha
  tax
  lda pently_drums,x
  jsr pently_start_sound
  pla
  tax
  lda pently_drums+1,x
  bmi noSecondDrum
  jsr pently_start_sound
noSecondDrum:
  ldx #PENTLY_DRUM_TRACK
  jmp skipNote

; Effect handlers
; The 6502 adds 2 to PC in JSR and 1 in RTS, so push minus 1.
; Each effect is called with carry clear and the effect number
; times 2 in Y.
patcmdhandlers:
  .addr set_fx_instrument-1
  .addr set_fx_arpeggio-1
  .addr set_fx_legato-1
  .addr set_fx_legato-1
  .addr set_fx_transpose-1
  .addr set_fx_grace-1
  .addr set_fx_vibrato-1
  .addr set_fx_ch_volume-1

  .addr set_fx_portamento-1
  .addr set_fx_portamento-1  ; Reserved for future use
  .addr set_fx_fastarp-1
  .addr set_fx_slowarp-1
num_patcmdhandlers = (* - patcmdhandlers) / 2

set_fx_instrument:
  lda (pentlyi_chnPatternPos,x)
  sta pentlyi_instrument,x
nextPatternByte:
  inc pentlyi_chnPatternPos,x
  bne :+
    inc pentlyi_chnPatternPos+1,x
  :
  jmp anotherPatternByte

.if ::PENTLY_USE_ARPEGGIO
set_fx_arpeggio:
  cpx #PENTLY_DRUM_TRACK
  bcs :+
    lda (pentlyi_chnPatternPos,x)
    lsr a
    lsr a
    lsr a
    lsr a
    sta pentlyi_arpInterval1,x
    lda (pentlyi_chnPatternPos,x)
    and #$0F
    sta pentlyi_arpInterval2,x
  :
  jmp nextPatternByte
set_fx_fastarp:
  cpx #PENTLY_DRUM_TRACK
  bcs :+
    lda #%10111111
    and pentlyi_arpPhase,x
    sta pentlyi_arpPhase,x
  :
  jmp anotherPatternByte
set_fx_slowarp:
  cpx #PENTLY_DRUM_TRACK
  bcs :+
    lda #%01000000
    ora pentlyi_arpPhase,x
    sta pentlyi_arpPhase,x
  :
  jmp anotherPatternByte
.else
  set_fx_arpeggio = nextPatternByte
  set_fx_fastarp = anotherPatternByte
  set_fx_slowarp = anotherPatternByte
.endif

set_fx_legato:
  cpx #PENTLY_DRUM_TRACK
  bcs :+
    tya
    and #$02
    sta pentlyi_noteLegato,x
  :
  jmp anotherPatternByte

set_fx_grace:
  lda (pentlyi_chnPatternPos,x)
  ; Because grace note processing decrements before comparing to
  ; zero, 1 is treated the same as 0.
  ; 0: this row's pattern already read
  ; 1: will read this row's pattern this frame
  ; 2: will read this row's pattern next frame
  ; 3: will read this row's pattern 2 frames from now
  clc
  adc #1
  sta pentlyi_graceTime,x
  jmp nextPatternByte

set_fx_transpose:
  lda pentlyi_chBaseNote,x
  adc (pentlyi_chnPatternPos,x)
  sta pentlyi_chBaseNote,x
  jmp nextPatternByte

.if ::PENTLY_USE_VIBRATO
set_fx_vibrato:
  cpx #PENTLY_DRUM_TRACK
  bcs :+
    lda (pentlyi_chnPatternPos,x)
    and #$07
    sta pentlyi_vibratoDepth,x
  :
  jmp nextPatternByte
.else
  set_fx_vibrato = nextPatternByte
.endif

.if ::PENTLY_USE_PORTAMENTO
set_fx_portamento:
  cpx #PENTLY_DRUM_TRACK
  bcs :+
    lda (pentlyi_chnPatternPos,x)
    sta pentlyi_chPortamento,x
  :
  jmp nextPatternByte
.else
  set_fx_portamento = nextPatternByte 
.endif

.if ::PENTLY_USE_CHANNEL_VOLUME
set_fx_ch_volume:
  .if ::PENTLY_USE_ATTACK_TRACK
    ; Channel volume has no effect on attack track, yet it should be
    ; explicitly ignored so that if attack and pulse share a pattern,
    ; it doesn't clobber some other variable.
    cpx #PENTLY_ATTACK_TRACK
    bcs :+
  .endif
    lda (pentlyi_chnPatternPos,x)
    sta pentlyi_chVolScale,x
  :
  jmp nextPatternByte
.else
  set_fx_ch_volume = nextPatternByte 
.endif

.endproc

.proc pentlyi_start_pattern
  lda #0
  sta pentlyi_graceTime,x
  sta pentlyi_noteRowsLeft,x
  lda pentlyi_musicPattern,x
  cmp #255
  bcc @notSilentPattern
    lda #<pentlyi_silent_pattern
    sta pentlyi_chnPatternPos,x
    lda #>pentlyi_silent_pattern
    sta pentlyi_chnPatternPos+1,x
    rts
  @notSilentPattern:
  asl a
  tay
  bcc @isLoPattern
    lda pently_patterns+256,y
    sta pentlyi_chnPatternPos,x
    lda pently_patterns+257,y
    sta pentlyi_chnPatternPos+1,x
    rts
  @isLoPattern:
  lda pently_patterns,y
  sta pentlyi_chnPatternPos,x
  lda pently_patterns+1,y
  sta pentlyi_chnPatternPos+1,x
  rts
.endproc

.if PENTLY_USE_REHEARSAL
; Known bug: Tracks with GRACE effects may fall behind
.proc pentlyi_skip_to_row_nz
  pha
  txa
  pha
  
  ; Fake out grace processing
  ldx #PENTLY_LAST_TRACK
  graceloop:
    lda pentlyi_graceTime,x
    beq noGraceThisCh
      lda #0
      sta pentlyi_graceTime,x
      jsr pentlyi_read_pattern
      jmp graceloop
    noGraceThisCh:
    dex
    dex
    dex
    dex
    bpl graceloop
  
  lda #0
  sta pently_tempoCounterHi
  sta pently_tempoCounterLo
  jsr pentlyi_next_row
  pla
  tax
  pla
  ; fall through to version that handles zero arguments correctly
.endproc
.proc pently_skip_to_row
  cpx pently_rowshi
  bne pentlyi_skip_to_row_nz
  cmp pently_rowslo
  bne pentlyi_skip_to_row_nz
  
  ; When seeking, kill cymbals because they tend to leave an
  ; envelope hanging
  lda #0
  sta pentlyi_sustainVol+PENTLY_DRUM_TRACK
  rts
.endproc
.endif

; Playing notes ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;
; Plays note A on channel X (0, 4, 8, 12) with instrument Y.
; Trashes ZP temp 0-1 and preserves X.
.proc pently_play_note
notenum       = pently_zptemp + 0
instrument_id = pently_zptemp + 1

  sta notenum
  sty instrument_id
  ; 5 bytes per instrument
  tya
  asl a
  asl a
  adc instrument_id
  tay
  
  ; at this point:
  ; x = channel #
  ; y = offset in instrument table
.if ::PENTLY_USE_ATTACK_TRACK
  cpx #PENTLY_ATTACK_TRACK
  bcs skipSustainPart
    lda pentlyi_arpPhase,x  ; bit 7 set if attack is injected
    bmi dont_legato_injected_attack
      lda notenum
      sta pentlyi_attackPitch,x
.endif
    dont_legato_injected_attack:
    lda notenum
.if ::PENTLY_USE_PORTAMENTO
    cpx #PENTLY_DRUM_TRACK
    bcs bypass_notePitch
      sta pentlyi_notePitch,x
      bcc pitch_is_stored
    bypass_notePitch:
.endif
      sta pentlyi_chPitchHi,x
    pitch_is_stored:
    lda pentlyi_noteLegato,x
    bne skipAttackPart
    lda instrument_id
    sta pentlyi_instrument,x
    lda pently_instruments,y
    asl a
    asl a
    asl a
    asl a
    ora #$0C
    sta pentlyi_sustainVol,x
    cpx #PENTLY_DRUM_TRACK
    bcs skipSustainPart
      .if ::PENTLY_USE_ARPEGGIO
        lda #%01000000
        and pentlyi_arpPhase,x
        sta pentlyi_arpPhase,x  ; keep only bit 6: is arp fast
      .elseif ::PENTLY_USE_ATTACK_TRACK
        lda #0
        sta pentlyi_arpPhase,x
      .endif
      .if ::PENTLY_USE_VIBRATO
        lda #PENTLY_VIBRATO_PERIOD + PENTLY_PREVIBRATO_PERIOD
        sta pentlyi_vibratoPhase,x
      .endif
  skipSustainPart:

.if ::PENTLY_USE_ATTACK_PHASE
  lda pently_instruments+4,y
  beq skipAttackPart
    txa
    pha
    .if ::PENTLY_USE_ATTACK_TRACK
      cpx #PENTLY_ATTACK_TRACK
      bcc notAttackTrack
        ldx pentlyi_attackChn
        lda #$80  ; Disable arpeggio, vibrato, and legato until sustain
        ora pentlyi_arpPhase,x
        sta pentlyi_arpPhase,x
      notAttackTrack:
      lda notenum
      sta pentlyi_attackPitch,x
    .endif
    
    lda pently_instruments+4,y
    sta pentlyi_noteAttackPos+1,x
    lda pently_instruments+3,y
    sta pentlyi_noteAttackPos,x
    lda pently_instruments+2,y
    and #$7F
    sta pentlyi_attackLen,x
    pla
    tax
.endif

skipAttackPart:
  ; Fall through
.endproc
.proc pentlyi_play_note_rts
  rts
.endproc

; The mixer (in pentlysound.s) expects output to be stored in
; zero page temporaries 2, 3, and 4.
xsave        = pently_zptemp + 0
out_volume   = pently_zptemp + 2
out_pitch    = pently_zptemp + 3
out_pitchadd = pently_zptemp + 4

;;
; Calculates the pitch, detune amount, and volume for channel X.
; @return out_volume: value for $4000/$4004/$4008/$400C
;   out_pitch: semitone number
;   out_pitchadd: amount to add to semitone
;   X: preserved
.proc pentlyi_update_music_ch

  lda pently_music_playing
  bne :+
    jmp pentlyi_set_ch_silent
  :

  lda pentlyi_graceTime,x
  beq nograce
  dec pentlyi_graceTime,x
  bne nograce
    jsr pentlyi_read_pattern
  nograce:

.if ::PENTLY_USE_ATTACK_TRACK
  cpx #PENTLY_ATTACK_TRACK
  bcs pentlyi_play_note_rts
.endif
  
.if ::PENTLY_USE_VIS
  lda #0
  sta pently_vis_pitchlo,x
.endif

.if ::PENTLY_USE_PORTAMENTO
  cpx #PENTLY_DRUM_TRACK
  bcs no_pitch_no_porta
    jsr pentlyi_calc_portamento
  no_pitch_no_porta:
.endif

.if ::PENTLY_USE_ATTACK_PHASE
  ; Handle attack phase of envelope
  lda pentlyi_attackLen,x
  beq pentlyi_calc_sustain
  dec pentlyi_attackLen,x
  lda (pentlyi_noteAttackPos,x)
  inc pentlyi_noteAttackPos,x
  bne :+
    inc pentlyi_noteAttackPos+1,x
  :
  .if ::PENTLY_USE_CHANNEL_VOLUME
    jsr pentlyi_scale_volume
  .else
    sta out_volume
  .endif

  ldy pentlyi_chPitchHi,x
  .if ::PENTLY_USE_PORTAMENTO
    ; Use portamento pitch if not injected
    cpx #PENTLY_DRUM_TRACK
    bcs attack_not_pitched_ch
      .if ::PENTLY_USE_ATTACK_TRACK
        lda pentlyi_arpPhase,x
        bpl porta_not_injected
      .endif
    attack_not_pitched_ch:
  .endif
  .if ::PENTLY_USE_ATTACK_TRACK
    ldy pentlyi_attackPitch,x
  .endif
porta_not_injected:

  ; X=instrument, Y=pitch (before adding arp env)
  ; Read saved duty/ctrl/volume byte from attack envelope
  lda out_volume
  and #$30
  cmp #$01  ; C true: use 0 instead of an envelope byte for pitch
  tya
  bcs :+
  adc (pentlyi_noteAttackPos,x)
  inc pentlyi_noteAttackPos,x
  bne :+
    inc pentlyi_noteAttackPos+1,x
  :

  ; At this point, A is the note pitch with envelope modification,
  ; but not effect modification.  Arpeggio, vibrato, and portamento
  ; need to be applied to the same-track note, not injected attacks.
  sta out_pitch
  .if ::PENTLY_USE_ATTACK_TRACK
    ldy pentlyi_arpPhase,x
    bpl not_injected
      .if ::PENTLY_USE_VIBRATO || ::PENTLY_USE_PORTAMENTO
        lda #0
        sta out_pitchadd
      .endif
      rts
    not_injected:
  .endif

  jmp pentlyi_calc_pitch_effects
.else
  ;jmp pentlyi_calc_sustain
.endif
.endproc

.proc pentlyi_calc_sustain
  lda pentlyi_sustainVol,x
  lsr a
  lsr a
  lsr a
  lsr a
  beq pentlyi_set_ch_silent
  .if ::PENTLY_USE_CHANNEL_VOLUME
    jsr pentlyi_scale_volume
  .else
    sta out_volume
  .endif
  lda pentlyi_instrument,x
  asl a
  asl a
  adc pentlyi_instrument,x
  tay
  lda out_volume
  eor pently_instruments,y
  and #$F0  ; keep instrument bits 7-4 and volume bits 3-0
  eor out_volume
  sta out_volume
  lda pentlyi_sustainVol,x
  sec
  sbc pently_instruments+1,y
  bcc pentlyi_set_ch_silent
  sta pentlyi_sustainVol,x

  ; Detached (instrument attribute 2 bit 7):
  ; Cut note when half a row remains
  lda pently_instruments+2,y
  bpl notCutNote
  lda pentlyi_noteRowsLeft,x
  bne notCutNote

  clc
  lda pently_tempoCounterLo
  adc #<(FRAMES_PER_MINUTE_NTSC/2)
  lda pently_tempoCounterHi
  adc #>(FRAMES_PER_MINUTE_NTSC/2)
  bcc notCutNote

  ; Unless the next byte in the pattern is a tie or a legato enable,
  ; cut the note
  lda (pentlyi_chnPatternPos,x)
  cmp #PENTLY_LEGATO_ON
  beq notCutNote
  cmp #PENTLY_LEGATO_OFF
  beq pentlyi_set_ch_silent
  and #$F8
  cmp #PENTLY_N_TIE
  beq notCutNote
  lda pentlyi_noteLegato,x
  beq pentlyi_set_ch_silent
  notCutNote:

  lda pentlyi_chPitchHi,x
  sta out_pitch
  jmp pentlyi_calc_pitch_effects
.endproc

.proc pentlyi_set_ch_silent
  lda #0
  sta out_volume
  .if ::PENTLY_USE_ATTACK_TRACK
    cpx #PENTLY_ATTACK_TRACK
    bcs track_is_not_channel
  .endif
    sta pentlyi_sustainVol,x
  track_is_not_channel:
  rts
.endproc

;;
; Applies pitch effects (arpeggio, vibrato, and portamento) to
; out_pitch and clears the attack injection flag once attack ends.
; @param X channel ID
.proc pentlyi_calc_pitch_effects

  .if ::PENTLY_USE_ARPEGGIO
    stx xsave
  
    ; 7: attack is injected
    ; 6: slow
    ; 2-1: phase
    ; 0: phase low bit
    lda #$3F
    cmp pentlyi_arpPhase,x
    lda #0
    rol a  ; A = 0 for slow arp or 1 for fast arp
    ora pentlyi_arpPhase,x
    and #$07  ; A[2:1]: arp phase; A[0]: need to increase
    tay
    and #$06
    beq bumpArpPhase

    ; So we're in a nonzero phase.  Load the interval.
    and #$04  ; A=0 for phase 1, 4 for phase 2
    beq :+
      lda #pentlyi_arpInterval2-pentlyi_arpInterval1
    :
    adc xsave
    tax
    lda pentlyi_arpInterval1,x

    ; If phase 2's interval is 0, cycle through two phases (2, 4)
    ; or four (2-5) instead of three (0, 1, 2) or six (0-5).
    bne bumpArpPhase
    cpy #4
    bcc bumpArpPhase
      ldy #0
    bumpArpPhase:
    iny
    cpy #6
    bcc noArpRestart
      ldy #0
    noArpRestart:

    ; At this point, A is the arpeggio interval and Y is the next phase
    clc
    adc out_pitch
    sta out_pitch
    ldx xsave
    tya

    ; Combine new arp phase and lack of injection with old arp rate
    eor pentlyi_arpPhase,x
    and #%10000111
    eor pentlyi_arpPhase,x
    sta pentlyi_arpPhase,x
  .elseif ::PENTLY_USE_ATTACK_TRACK
    ; If arpeggio support is off, just clear the attack injection flag
    lda #0
    sta pentlyi_arpPhase,x
  .endif

  .if ::PENTLY_USE_VIBRATO || ::PENTLY_USE_PORTAMENTO
    ;jmp pentlyi_calc_vibrato
  .else
    rts
  .endif
.endproc

.if ::PENTLY_USE_VIBRATO

;;
; Add the vibrato
; Assumes NOT an injected attack.
.proc pentlyi_calc_vibrato
  .if ::PENTLY_USE_PORTAMENTO
    lda pentlyi_chPitchLo,x
  .else
    lda #0
  .endif

  sta out_pitchadd
  ora pentlyi_vibratoDepth,x  ; Skip calculation if depth is 0
  beq not_vibrato_rts
  .if ::PENTLY_USE_PORTAMENTO
    lda pentlyi_vibratoDepth,x
    beq have_instantaneous_amplitude
  .endif

  ; Clock vibrato
  ldy pentlyi_vibratoPhase,x
  bne :+
    ldy #PENTLY_VIBRATO_PERIOD
  :
  dey
  tya
  sta pentlyi_vibratoPhase,x
  cpy #PENTLY_VIBRATO_PERIOD-1
  bcs not_vibrato

  lda pentlyi_vibrato_pattern,y
  cmp #$80              ; carry set if decrease
  php
  ldy pentlyi_vibratoDepth,x
  and #$0F
  vibratodepthloop:
    asl a
    dey
    bne vibratodepthloop
  plp
  bcc have_instantaneous_amplitude
    dec out_pitch
    eor #$FF
    adc #0
  have_instantaneous_amplitude:

  .if ::PENTLY_USE_PORTAMENTO
    clc
    adc pentlyi_chPitchLo,x
    bcc :+
      inc out_pitch
    :
  .endif

  ; At this point, out_pitch:A is the next pitch
  .if ::PENTLY_USE_VIS
    sta pently_vis_pitchlo,x
  .endif
  jsr pentlyi_calc_frac_pitch
  eor #$FF
  clc
  adc #1
  sta out_pitchadd
not_vibrato_rts:
  rts

.if ::PENTLY_USE_PORTAMENTO
not_vibrato:
  lda #0
  beq have_instantaneous_amplitude
.else
not_vibrato = not_vibrato_rts
.endif
.endproc

; This simplified version of pentlyi_calc_vibrato is used if portamento but
; not vibrato is enabled
.elseif ::PENTLY_USE_PORTAMENTO

.proc pentlyi_calc_vibrato
  lda pentlyi_chPitchLo,x
  .if ::PENTLY_USE_VIS
    sta pently_vis_pitchlo,x
  .endif
  beq have_pitchadd
    jsr pentlyi_calc_frac_pitch
    eor #$FF
    clc
    adc #1
  have_pitchadd:
  sta out_pitchadd
  rts
.endproc

.endif

.if ::PENTLY_USE_CHANNEL_VOLUME
;;
; Stores the instrument duty and volume scaled by channel volume
; to the output variable.
; @param X channel number
; @param A bits 7-6: duty; bits 0-3: volume
.proc pentlyi_scale_volume

  ldy pentlyi_chVolScale,x
  bne chvol_nonzero
    and #$F0
    sta out_volume
    rts
  chvol_nonzero:

  cpy #PENTLY_MAX_CHANNEL_VOLUME
  bcs chvol_unchanged

    pha
    and #$0F
    sta out_volume
    lda #0
    chvol_loop:
      adc out_volume
      dey
      bne chvol_loop
    lsr a
    lsr a
    adc #0
    sta out_volume

    ; combine with duty bits from out_volume
    pla
    eor out_volume
    and #$F0
    eor out_volume
  chvol_unchanged:
  sta out_volume
  rts
.endproc
.endif

.if ::PENTLY_USE_VIBRATO || ::PENTLY_USE_PORTAMENTO

;;
; Calculates the amount of period reduction needed to raise a note
; by a fraction of a semitone.
; @param out_pitch the semitone number to calculate around
; @param A the fraction of semitones
; @return the additional distance in period units
.proc pentlyi_calc_frac_pitch
prodlo       = pently_zptemp + 0
pitch_sub    = pently_zptemp + 1
out_pitch    = pently_zptemp + 3

  ; Find the difference between the next note's period and that of
  ; this note
  sta pitch_sub
  sec
  ldy out_pitch
  lda periodTableLo,y
  sbc periodTableLo+1,y

  ; Multiply the difference by pitch_sub.
  ; The period difference is stored in the lower bits of prodlo; the
  ; low byte of the product is stored in the upper bits.
  lsr a  ; prime the carry bit for the loop
  sta prodlo
  lda #0
  ldy #8
loop:
  ; At the start of the loop, one bit of prodlo has already been
  ; shifted out into the carry.
  bcc noadd
    clc
    adc pitch_sub
  noadd:
  ror a
  ror prodlo  ; pull another bit out for the next iteration
  dey         ; inc/dec don't modify carry; only shifts and adds do
  bne loop

  asl prodlo  ; Rounding: Set carry iff result low byte >= 128
  adc #0
  rts
.endproc
.endif


.if ::PENTLY_USE_PORTAMENTO
.proc pentlyi_calc_portamento
portaRateLo = pently_zptemp+0
portaRateHi = pently_zptemp+1

  lda pentlyi_chPortamento,x
  bne not_instant  ; $00: portamento disabled
    sta pentlyi_chPitchLo,x
    lda pentlyi_notePitch,x
    sta pentlyi_chPitchHi,x
    rts
  not_instant:

  .if ::PENTLY_USE_303_PORTAMENTO
    and #$30
  .else
    and #$10
  .endif
  lsr a
  lsr a
  lsr a
  tay
  lda portamentocalc_funcs+1,y
  pha
  lda portamentocalc_funcs+0,y
  pha
  rts

; These functions calculate the instantaneous portamento rate

portamentocalc_funcs:
  .addr calc_whole_semitone-1
  .addr calc_fraction-1
.if ::PENTLY_USE_303_PORTAMENTO
  .addr calc_tb303-1
  .addr calc_tb303-1
.endif
num_portamentocalc_funcs = (* - portamentocalc_funcs) / 2

.if ::PENTLY_USE_303_PORTAMENTO
calc_tb303:
  ; Calculate the displacement to the final pitch
  sec
  lda pentlyi_chPitchLo,x
  sta portaRateLo
  lda pentlyi_chPitchHi,x
  sbc pentlyi_notePitch,x
  sta portaRateHi

  ; Take its absolute value before scaling
  bcs tb303_alreadyPositive
    lda #1  ; compensate for carry being clear
    sbc portaRateLo
    sta portaRateLo
    lda #0
    sbc portaRateHi
    sta portaRateHi
  tb303_alreadyPositive:

  ; Scale based on approach time constant setting
  lda pentlyi_chPortamento,x
  and #$0F
  tay
  lda portaRateLo
  tb303_scale:
    lsr portaRateHi
    ror a
    dey
    bpl tb303_scale
  adc #0
  bcc tb303_no_carry
    inc portaRateHi
  tb303_no_carry:
  sta portaRateLo

  ; If rate is zero, make it nonzero
  ora portaRateHi
  bne portamento_add
    inc portaRateLo
  jmp portamento_add
.endif

calc_whole_semitone:
;  ldy #0  ; Y is 0, 2, or 4 at entry, and for this routine it's 0
  sty portaRateLo
  lda pentlyi_chPortamento,x
  sta portaRateHi
  jmp portamento_add

calc_fraction:
  ldy pentlyi_chPortamento,x
  lda pentlyi_porta1x_rates_lo-$10,y
  sta portaRateLo
  lda pentlyi_porta1x_rates_hi-$10,y
  sta portaRateHi
portamento_add:
  lda pentlyi_chPitchHi,x
  cmp pentlyi_notePitch,x
  bcs is_decrease
  lda pentlyi_chPitchLo,x
  adc portaRateLo
  sta pentlyi_chPitchLo,x
  lda pentlyi_chPitchHi,x
  adc portaRateHi
  cmp pentlyi_notePitch,x
  bcc have_pitchHi
  at_target:
    lda #0
    sta pentlyi_chPitchLo,x
    lda pentlyi_notePitch,x
  have_pitchHi:
  sta pentlyi_chPitchHi,x
  rts

is_decrease:
  lda pentlyi_chPitchLo,x
  sbc portaRateLo
  sta pentlyi_chPitchLo,x
  lda pentlyi_chPitchHi,x
  sbc portaRateHi
  cmp pentlyi_notePitch,x
  bcs have_pitchHi
  bcc at_target
.endproc

.endif

.if PENTLY_USE_TEMPO_ROUNDING
;;
; Rounds accumulated musical time within this row to either
; zero or one whole tick.
.proc pentlyi_round_to_beat
  ; Calculate half a tick's worth of musical time
  lda pentlyi_tempoHi
  lsr a
  tax
  lda pentlyi_tempoLo
  ror a
  ; XXAA = half tick length

  ; Musical time till next row = -tempoCounter
  ; Calculate tempoCounter + halfTick
  sbc pently_tempoCounterLo
  tay
  txa
  sbc pently_tempoCounterHi
  pha
  ; Stack[1]:Y = Remaining musical time in row half a tick ago

  ; If this is greater than FPM, it's greater than one row
  ; and we should round DOWN.
  ; Otherwise, round UP.
  ldx tvSystem
  tya
  cmp pently_fpmLo,x
  pla
  sbc pently_fpmHi,x
  ; C set to round DOWN; C clear to round UP

  ldy #0
  tya
  bcs :+
    lda pentlyi_tempoLo
    ldy pentlyi_tempoHi
    sec
  :
  sbc pently_fpmLo,x
  sta pently_tempoCounterLo
  tya
  sbc pently_fpmHi,x
  sta pently_tempoCounterHi
  rts
.endproc
.endif


.segment PENTLY_RODATA
pentlymusic_rodata_size = * - pentlymusic_rodata_start
.segment PENTLY_CODE
pentlymusic_code_size = * - pentlymusic_code_start
PENTLYMUSIC_SIZE = pentlymusic_rodata_size + pentlymusic_code_size

; aliases for cc65
_pently_start_music = pently_start_music
_pently_resume_music = pently_resume_music
_pently_stop_music = pently_stop_music
.if PENTLY_USE_REHEARSAL
  _pently_skip_to_row = pently_skip_to_row
.endif
