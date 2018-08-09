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

.include "pentlyconfig.inc"
.include "pently.inc"
.include "pentlyseq.inc"
.include "../obj/nes/pentlybss.inc"

.importzp pently_zp_state
.import pentlyBSS
.import periodTableLo, periodTableHi
.export pently_update_music, pently_update_music_ch

.if PENTLY_USE_PAL_ADJUST
.importzp tvSystem
.endif

.if PENTLY_USE_ROW_CALLBACK
.import pently_row_callback, pently_dalsegno_callback
.endif

NUM_CHANNELS = 4
DRUM_TRACK = 12
ATTACK_TRACK = 16
MAX_CHANNEL_VOLUME = 4
DEFAULT_TEMPO = 300
DEFAULT_ROWS_PER_BEAT = 4
MAX_TEMPO_SCALE = 8

.if PENTLY_USE_ATTACK_TRACK
  LAST_TRACK = ATTACK_TRACK
.else
  LAST_TRACK = DRUM_TRACK
.endif

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

musicPatternPos = pently_zp_state + 2
.if PENTLY_USE_ATTACK_PHASE
  noteAttackPos           = pently_zp_state + 16
  conductorPos            = pently_zp_state + 22
  pently_tempoCounterLo   = pently_zp_state + 26
  pently_tempoCounterHi   = pently_zp_state + 27
  pently_music_playing    = pently_zp_state + 30
  attackChannel           = pently_zp_state + 31
.else
  conductorPos            = pently_zp_state + 16
  pently_tempoCounterLo   = pently_zp_state + 18
  pently_tempoCounterHi   = pently_zp_state + 19
  pently_music_playing    = pently_zp_state + 20
.endif


.bss
; Statically allocated so as not to be cleared by the clear loop
conductorSegnoLo        = pentlyBSS + 16
conductorSegnoHi        = pentlyBSS + 17

; The rest is allocated by pentlybss.py
; Noise envelope is NOT unused.  Conductor track cymbals use it.
pentlymusicbase: .res pentlymusicbase_size

; Regardless of whether pentlyBSS puts arpIntervalA before
; arpIntervalB or vice versa, arpInterval1 must precede
; arpInterval2 because of how they're indexed.
.if PENTLY_USE_ARPEGGIO
  .if arpIntervalB - arpIntervalA > 0
    arpInterval1 = arpIntervalA
    arpInterval2 = arpIntervalB
  .else
    arpInterval1 = arpIntervalB
    arpInterval2 = arpIntervalA
  .endif
.endif

; Visualize particular notes within a playing score
.if PENTLY_USE_ARPEGGIO || PENTLY_USE_ATTACK_TRACK
  pently_vis_arpphase = arpPhase
.endif
.if PENTLY_USE_PORTAMENTO
  pently_vis_note = notePitch
.else
  pently_vis_note = chPitchHi
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

silentPattern:  ; a pattern consisting of a single whole rest
  .byt 26*8+7, 255
durations:
  .byt 1, 2, 3, 4, 6, 8, 12, 16

.if PENTLY_USE_VIBRATO
; bit 7: negate; bits 6-0: amplitude in units of 1/128 semitone
vibratoPattern:
  .byt $88,$8B,$8C,$8B,$88,$00,$08,$0B,$0C,$0B,$08
.endif

.if PENTLY_USE_PORTAMENTO
porta1x_rates_lo:
  .byte 4, 8, 12, 16, 24, 32, 48, 64, 96, 128, 128
porta1x_rates_hi:
  .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
.endif

.segment PENTLY_CODE
pentlymusic_code_start = *

.proc pently_start_music
  ; Fetch initial conductor track position (limit 128 songs)
  asl a
  tax
  lda pently_songs,x
  sta conductorPos
  sta conductorSegnoLo
  lda pently_songs+1,x
  sta conductorPos+1
  sta conductorSegnoHi

  ; Clear all music state except that shared with sound effects
  ldy #pentlymusicbase_size - 1
  lda #0
  .if ::PENTLY_USE_ATTACK_TRACK
    sta attackChannel
  .endif
  :
    sta pentlymusicbase,y
    dey
    bpl :-

  ; Init each track's volume and play silent pattern
  ldx #LAST_TRACK
  channelLoop:
    lda #<silentPattern
    sta musicPatternPos,x
    lda #>silentPattern
    sta musicPatternPos+1,x
    tya  ; Y is $FF from the clear everything loop
    sta musicPattern,x
    .if ::PENTLY_USE_CHANNEL_VOLUME && (::LAST_TRACK >= ::ATTACK_TRACK)
      cpx #ATTACK_TRACK
      bcs :+
        lda #MAX_CHANNEL_VOLUME
        sta channelVolume,x
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
    lda #DEFAULT_ROWS_PER_BEAT
    sta pently_rows_per_beat
  .endif
  lda #<DEFAULT_TEMPO
  sta music_tempoLo
  lda #>DEFAULT_TEMPO
  sta music_tempoHi
  ; Fall through
.endproc
.proc pently_resume_music
  lda #1
have_music_playing:
  sta pently_music_playing
  rts
.endproc

.proc pently_stop_music
  lda #0
  beq pently_resume_music::have_music_playing
.endproc

.proc pently_update_music
  lda pently_music_playing
  beq music_not_playing

  ; This applies Bresenham's algorithm to tick generation: add
  ; rows per minute every frame, then subtract frames per minute
  ; when it overflows.  But
  .if ::PENTLY_USE_REHEARSAL
scaled_tempoHi  = pently_zptemp + 0

    lda music_tempoHi
    sta scaled_tempoHi
    lda music_tempoLo
    ldx pently_tempo_scale
    clc  ; allow have_scaled_tempoLo to round
    beq have_scaled_tempoLo
    cpx #MAX_TEMPO_SCALE
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
    lda music_tempoLo
    clc
    adc pently_tempoCounterLo
    sta pently_tempoCounterLo
    lda music_tempoHi
  .endif
  adc pently_tempoCounterHi
  sta pently_tempoCounterHi
  bcs pently_next_row
music_not_playing:
  rts
.endproc

; Conductor reading ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc pently_next_row
  ; Subtract tempo
  .if ::PENTLY_USE_PAL_ADJUST
    ldy tvSystem
  .else
    ldy #0
  .endif
  ; sec  ; carry was set by bcs in pently_update_music
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
      ldy #0
    :
    sty pently_row_beat_part
  .endif

.if ::PENTLY_USE_ROW_CALLBACK
  jsr pently_row_callback
.endif

  ; If in middle of waitRows, don't process conductor
  lda conductorWaitRows
  beq doConductor
  dec conductorWaitRows
  jmp processPatterns

doConductor:
  ldy #0
  lda (conductorPos),y
  inc conductorPos
  bne :+
    inc conductorPos+1
  :
  cmp #CON_WAITROWS
  beq is_waitrows
  bcs not_playpat
    ; 00-07 pp tt ii: Play pattern pp on track A & $07,
    ; transposed up tt semitones, with instrument ii
    and #$07
    asl a
    asl a
    tax

    lda #0
    cpx #ATTACK_TRACK
    ; If attack track is enabled, don't enable legato on attack
    ; track. Otherwise, don't start patterns on attack track at all
    ; because another variable overlaps it.
    .if ::PENTLY_USE_ATTACK_TRACK
      bcs skipClearLegato
    .else
      bcs skip3conductor
    .endif
      sta noteLegato,x  ; start all patterns with legato off
    skipClearLegato:

    lda (conductorPos),y
    sta musicPattern,x
    iny
    lda (conductorPos),y
    sta patternTranspose,x
    iny
    lda (conductorPos),y
    sta noteInstrument,x
    jsr startPattern
  skip3conductor:
    lda #3
    clc
    adc conductorPos
    sta conductorPos
    bcc :+
      inc conductorPos+1
    :
    jmp doConductor

  is_waitrows:
    ; 20 ww: Wait ww+1 rows
    lda (conductorPos),y
    sta conductorWaitRows
    inc conductorPos
    bne :+
      inc conductorPos+1
    :
    jmp processPatterns
  not_playpat:
  
  ; Loop control block 21-23
  cmp #CON_DALSEGNO
  beq is_dalsegno
  bcs not_loopcontrol
  cmp #CON_SEGNO
  bcs is_segno
    ; 21: Fine (end playback; set playing and tempo to 0)
    lda #0
    sta pently_music_playing
    sta music_tempoHi
    sta music_tempoLo
    .if ::PENTLY_USE_ROW_CALLBACK
      clc
      jmp pently_dalsegno_callback
   .else
      rts
   .endif
  is_segno:
    lda conductorPos
    sta conductorSegnoLo
    lda conductorPos+1
    sta conductorSegnoHi
    jmp doConductor
  is_dalsegno:
    lda conductorSegnoLo
    sta conductorPos
    lda conductorSegnoHi
    sta conductorPos+1
    .if ::PENTLY_USE_ROW_CALLBACK
      sec
      jsr pently_dalsegno_callback
    .endif
    jmp doConductor
  not_loopcontrol:

  cmp #CON_NOTEON
  bcs not_setattack
    ; 24-26: Play attack track on channel A & $07
    .if ::PENTLY_USE_ATTACK_TRACK
      and #%00000011
      asl a
      asl a
      sta attackChannel
    .endif
    jmp doConductor
  not_setattack:

  cmp #CON_SETTEMPO
  bcs not_noteon
    ; 28-2F nn ii: Play note nn with instrument ii on track A & $07
    and #%00000011
    asl a
    asl a
    tax
    lda (conductorPos),y
    inc conductorPos
    bne :+
      inc conductorPos+1
    :
    pha
    lda (conductorPos),y
    tay
    pla
    jsr pently_play_note
    jmp skipConductorByte
  not_noteon:
  
  cmp #CON_SETBEAT
  bcs not_tempo_change
    ; 30-37 tt: Set tempo to (A & $07) * 256 + tt
    and #%00000111
    sta music_tempoHi
    lda (conductorPos),y
    sta music_tempoLo
  skipConductorByte:
    inc conductorPos
    bne :+
      inc conductorPos+1
    :
    jmp doConductor
  not_tempo_change:
  
  cmp #CON_SETBEAT+8
  bcs not_set_beat
    .if ::PENTLY_USE_BPMMATH
      and #%00000111
      tay
      lda durations,y
      sta pently_rows_per_beat
      ldy #0
      sty pently_row_beat_part
    .endif
  not_set_beat:

  jmp doConductor
.endproc

; Pattern reading ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc processPatterns
  ldx #4 * (NUM_CHANNELS - 1)
  channelLoop:
    jsr processTrackPattern
    dex
    dex
    dex
    dex
    bpl channelLoop

  ; Process attack track last so it can override a just played attack
  .if ::PENTLY_USE_ATTACK_TRACK
    ldx #ATTACK_TRACK
    ;jmp processTrackPattern
    ; (that's a fallthrough)
  .else
    rts
  .endif
.endproc
.proc processTrackPattern
  lda noteRowsLeft,x
  beq anotherPatternByte
skipNote:
  dec noteRowsLeft,x
  rts

anotherPatternByte:
  ; Read one pattern byte.  If it's a loop, restart the pattern.
  lda (musicPatternPos,x)
  cmp #PATEND
  bne notStartPatternOver
    jsr startPattern
    lda (musicPatternPos,x)
  notStartPatternOver:
  inc musicPatternPos,x
  bne patternNotNewPage
    inc musicPatternPos+1,x
  patternNotNewPage:

  cmp #INSTRUMENT
  bcc isNoteCmd
  sbc #INSTRUMENT
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
  lda durations,y
  sta noteRowsLeft,x
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
      cpx #ATTACK_TRACK
      bcs notKeyOff
    .endif
    .if ::PENTLY_USE_ATTACK_PHASE
      sta attack_remainlen,x
    .endif
    sta noteEnvVol,x
  notKeyOff:
  jmp skipNote

  isTransposedNote:
    cpx #DRUM_TRACK
    beq isDrumNote
    clc
    adc patternTranspose,x
    ldy noteInstrument,x
    jsr pently_play_note
    jmp skipNote

isDrumNote:
  .if ::PENTLY_USE_VARMIX
    ldy pently_mute_track+DRUM_TRACK
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
  ldx #DRUM_TRACK
  jmp skipNote

; Effect handlers
; The 6502 adds 2 to PC in JSR and 1 in RTS, so push minus 1.
; Each effect is called with carry clear and the effect number
; times 2 in Y.
.pushseg
.segment PENTLY_RODATA
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
.popseg

set_fx_instrument:
  lda (musicPatternPos,x)
  sta noteInstrument,x
nextPatternByte:
  inc musicPatternPos,x
  bne :+
    inc musicPatternPos+1,x
  :
  jmp anotherPatternByte

.if ::PENTLY_USE_ARPEGGIO
set_fx_arpeggio:
  cpx #DRUM_TRACK
  bcs :+
    lda (musicPatternPos,x)
    lsr a
    lsr a
    lsr a
    lsr a
    sta arpInterval1,x
    lda (musicPatternPos,x)
    and #$0F
    sta arpInterval2,x
  :
  jmp nextPatternByte
set_fx_fastarp:
  cpx #DRUM_TRACK
  bcs :+
    lda #%10111111
    and arpPhase,x
    sta arpPhase,x
  :
  jmp anotherPatternByte
set_fx_slowarp:
  cpx #DRUM_TRACK
  bcs :+
    lda #%01000000
    ora arpPhase,x
    sta arpPhase,x
  :
  jmp anotherPatternByte
.else
  set_fx_arpeggio = nextPatternByte
  set_fx_fastarp = anotherPatternByte
  set_fx_slowarp = anotherPatternByte
.endif

set_fx_legato:
  cpx #DRUM_TRACK
  bcs :+
    tya
    and #$02
    sta noteLegato,x
  :
  jmp anotherPatternByte

set_fx_grace:
  lda (musicPatternPos,x)
  ; Because grace note processing decrements before comparing to
  ; zero, 1 is treated the same as 0.
  ; 0: this row's pattern already read
  ; 1: will read this row's pattern this frame
  ; 2: will read this row's pattern next frame
  ; 3: will read this row's pattern 2 frames from now
  clc
  adc #1
  sta graceTime,x
  jmp nextPatternByte

set_fx_transpose:
  lda patternTranspose,x
  adc (musicPatternPos,x)
  sta patternTranspose,x
  jmp nextPatternByte

.if ::PENTLY_USE_VIBRATO
set_fx_vibrato:
  cpx #DRUM_TRACK
  bcs :+
    lda (musicPatternPos,x)
    and #$07
    sta vibratoDepth,x
  :
  jmp nextPatternByte
.else
  set_fx_vibrato = nextPatternByte
.endif

.if ::PENTLY_USE_PORTAMENTO
set_fx_portamento:
  cpx #DRUM_TRACK
  bcs :+
    lda (musicPatternPos,x)
    sta chPortamento,x
  :
  jmp nextPatternByte
.else
  set_fx_portamento = nextPatternByte 
.endif

.if ::PENTLY_USE_CHANNEL_VOLUME
set_fx_ch_volume:
  lda (musicPatternPos,x)
  sta channelVolume,x
  jmp nextPatternByte
.else
  set_fx_ch_volume = nextPatternByte 
.endif

.endproc

.proc startPattern
  lda #0
  sta graceTime,x
  sta noteRowsLeft,x
  lda musicPattern,x
  cmp #255
  bcc @notSilentPattern
    lda #<silentPattern
    sta musicPatternPos,x
    lda #>silentPattern
    sta musicPatternPos+1,x
    rts
  @notSilentPattern:
  asl a
  tay
  bcc @isLoPattern
    lda pently_patterns+256,y
    sta musicPatternPos,x
    lda pently_patterns+257,y
    sta musicPatternPos+1,x
    rts
  @isLoPattern:
  lda pently_patterns,y
  sta musicPatternPos,x
  lda pently_patterns+1,y
  sta musicPatternPos+1,x
  rts
.endproc

.if PENTLY_USE_REHEARSAL
; Known bug: Tracks with GRACE effects may fall behind
.proc skip_to_row_top
  pha
  txa
  pha
  
  ; Fake out grace processing
  ldx #LAST_TRACK
  graceloop:
    lda graceTime,x
    beq noGraceThisCh
      lda #0
      sta graceTime,x
      jsr processTrackPattern
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
  jsr pently_next_row
  pla
  tax
  pla
bottom:
  cpx pently_rowshi
  bne skip_to_row_top
  cmp pently_rowslo
  bne skip_to_row_top
  
  ; When seeking, kill cymbals because they tend to leave an
  ; envelope hanging
  lda #0
  sta noteEnvVol+DRUM_TRACK
  rts
.endproc
pently_skip_to_row = skip_to_row_top::bottom
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
  cpx #ATTACK_TRACK
  bcs skipSustainPart
    lda arpPhase,x  ; bit 7 set if attack is injected
    bmi dont_legato_injected_attack
      lda notenum
      sta attackPitch,x
.endif
    dont_legato_injected_attack:
    lda notenum
.if ::PENTLY_USE_PORTAMENTO
    cpx #DRUM_TRACK
    bcs bypass_notePitch
      sta notePitch,x
      bcc pitch_is_stored
    bypass_notePitch:
.endif
      sta chPitchHi,x
    pitch_is_stored:
    lda noteLegato,x
    bne skipAttackPart
    lda instrument_id
    sta noteInstrument,x
    lda pently_instruments,y
    asl a
    asl a
    asl a
    asl a
    ora #$0C
    sta noteEnvVol,x
    cpx #DRUM_TRACK
    bcs skipSustainPart
      .if ::PENTLY_USE_ARPEGGIO
        lda #%01000000
        and arpPhase,x
        sta arpPhase,x  ; keep only bit 6: is arp fast
      .elseif ::PENTLY_USE_ATTACK_TRACK
        lda #0
        sta arpPhase,x
      .endif
      .if ::PENTLY_USE_VIBRATO
        lda #23
        sta vibratoPhase,x
      .endif
  skipSustainPart:

.if ::PENTLY_USE_ATTACK_PHASE
  lda pently_instruments+4,y
  beq skipAttackPart
    txa
    pha
    .if ::PENTLY_USE_ATTACK_TRACK
      cpx #ATTACK_TRACK
      bcc notAttackTrack
        ldx attackChannel
        lda #$80  ; Disable arpeggio, vibrato, and legato until sustain
        ora arpPhase,x
        sta arpPhase,x
      notAttackTrack:
      lda notenum
      sta attackPitch,x
    .endif
    
    lda pently_instruments+4,y
    sta noteAttackPos+1,x
    lda pently_instruments+3,y
    sta noteAttackPos,x
    lda pently_instruments+2,y
    and #$7F
    sta attack_remainlen,x
    pla
    tax
.endif

skipAttackPart:
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
.proc pently_update_music_ch

  .if ::PENTLY_USE_VIS
    lda #0
    sta pently_vis_pitchlo,x
  .endif
  lda pently_music_playing
  bne :+
    jmp silenced
  :
  lda graceTime,x
  beq nograce
  dec graceTime,x
  bne nograce
    jsr processTrackPattern
  nograce:
  
.if ::PENTLY_USE_PORTAMENTO
  cpx #DRUM_TRACK
  bcs no_pitch_no_porta
    jsr update_portamento
  no_pitch_no_porta:
.endif

.if ::PENTLY_USE_ATTACK_PHASE
  ; Handle attack phase of envelope
  lda attack_remainlen,x
  beq sustain_phase
  dec attack_remainlen,x
  lda (noteAttackPos,x)
  inc noteAttackPos,x
  bne :+
    inc noteAttackPos+1,x
  :
  .if ::PENTLY_USE_CHANNEL_VOLUME
    jsr write_out_volume
  .else
    sta out_volume
  .endif

  ldy chPitchHi,x
  .if ::PENTLY_USE_PORTAMENTO
    ; Use portamento pitch if not injected
    cpx #DRUM_TRACK
    bcs attack_not_pitched_ch
      .if ::PENTLY_USE_ATTACK_TRACK
        lda arpPhase,x
        bpl porta_not_injected
      .endif
    attack_not_pitched_ch:
  .endif
  .if ::PENTLY_USE_ATTACK_TRACK
    ldy attackPitch,x
  .endif
porta_not_injected:

  ; X=instrument, Y=pitch (before adding arp env)
  ; Read saved duty/ctrl/volume byte from attack envelope
  lda out_volume
  and #$30
  cmp #$01  ; C true: use 0 instead of an envelope byte for pitch
  tya
  bcs :+
  adc (noteAttackPos,x)
  inc noteAttackPos,x
  bne :+
    inc noteAttackPos+1,x
  :

  ; At this point, A is the note pitch with envelope modification,
  ; but not effect modification.  Arpeggio, vibrato, and portamento
  ; need to be applied to the same-track note, not injected attacks.
  sta out_pitch
  .if ::PENTLY_USE_ATTACK_TRACK
    ldy arpPhase,x
    bpl not_injected
      .if ::PENTLY_USE_VIBRATO || ::PENTLY_USE_PORTAMENTO
        lda #0
        sta out_pitchadd
      .endif
      rts
    not_injected:
  .endif

  jmp add_pitch_effects
.else
  ;jmp sustain_phase
.endif
.endproc

.proc sustain_phase
  lda noteEnvVol,x
  lsr a
  lsr a
  lsr a
  lsr a
  beq silenced
  .if ::PENTLY_USE_CHANNEL_VOLUME
    jsr write_out_volume
  .else
    sta out_volume
  .endif
  lda noteInstrument,x
  asl a
  asl a
  adc noteInstrument,x
  tay
  lda out_volume
  eor pently_instruments,y
  and #$F0  ; keep instrument bits 7-4 and volume bits 3-0
  eor out_volume
  sta out_volume
  lda noteEnvVol,x
  sec
  sbc pently_instruments+1,y
  bcc silenced
  sta noteEnvVol,x

  ; Detached (instrument attribute 2 bit 7):
  ; Cut note when half a row remains
  lda pently_instruments+2,y
  bpl notCutNote
  lda noteRowsLeft,x
  bne notCutNote

  clc
  lda pently_tempoCounterLo
  adc #<(FRAMES_PER_MINUTE_NTSC/2)
  lda pently_tempoCounterHi
  adc #>(FRAMES_PER_MINUTE_NTSC/2)
  bcc notCutNote

  ; Unless the next byte in the pattern is a tie or a legato enable,
  ; cut the note
  lda (musicPatternPos,x)
  cmp #LEGATO_ON
  beq notCutNote
  cmp #LEGATO_OFF
  beq silenced
  and #$F8
  cmp #N_TIE
  beq notCutNote
  lda noteLegato,x
  bne notCutNote
  silenced:
    lda #0
    sta noteEnvVol,x
    sta out_volume
    rts
  notCutNote:

  lda chPitchHi,x
  sta out_pitch
  jmp add_pitch_effects
.endproc
silenced = sustain_phase::silenced

;;
; Applies pitch effects (arpeggio, vibrato, and portamento)
; to out_pitch and clears the attack injection flag.
; @param X
.proc add_pitch_effects

  .if ::PENTLY_USE_ARPEGGIO
    stx xsave
  
    ; 7: attack is injected
    ; 6: slow
    ; 2-1: phase
    ; 0: phase low bit
    lda #$3F
    cmp arpPhase,x
    lda #0
    rol a  ; A = 0 for slow arp or 1 for fast arp
    ora arpPhase,x
    and #$07  ; A[2:1]: arp phase; A[0]: need to increase
    tay
    and #$06
    beq bumpArpPhase

    ; So we're in a nonzero phase.  Load the interval.
    and #$04  ; A=0 for phase 1, 4 for phase 2
    beq :+
      lda #arpInterval2-arpInterval1
    :
    adc xsave
    tax
    lda arpInterval1,x

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
    eor arpPhase,x
    and #%10000111
    eor arpPhase,x
    sta arpPhase,x
  .elseif ::PENTLY_USE_ATTACK_TRACK
    ; If arpeggio support is off, just clear the attack injection flag
    lda #0
    sta arpPhase,x
  .endif

  .if ::PENTLY_USE_VIBRATO || ::PENTLY_USE_PORTAMENTO
    ;jmp add_vibrato
  .else
    rts
  .endif
.endproc

.if ::PENTLY_USE_VIBRATO
VIBRATO_PERIOD = 12

;;
; Add the vibrato
; Assumes NOT an injected attack.
.proc add_vibrato
  .if ::PENTLY_USE_PORTAMENTO
    lda chPitchLo,x
  .else
    lda #0
  .endif

  sta out_pitchadd
  ora vibratoDepth,x  ; Skip calculation if depth is 0
  beq not_vibrato_rts
  .if ::PENTLY_USE_PORTAMENTO
    lda vibratoDepth,x
    beq have_instantaneous_amplitude
  .endif

  ; Clock vibrato
  ldy vibratoPhase,x
  bne :+
    ldy #VIBRATO_PERIOD
  :
  dey
  tya
  sta vibratoPhase,x
  cpy #VIBRATO_PERIOD-1
  bcs not_vibrato

  lda vibratoPattern,y
  cmp #$80              ; carry set if decrease
  php
  ldy vibratoDepth,x
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
    adc chPitchLo,x
    bcc :+
      inc out_pitch
    :
  .endif

  ; At this point, out_pitch:A is the next pitch
  .if ::PENTLY_USE_VIS
    sta pently_vis_pitchlo,x
  .endif
  jsr calc_frac_pitch
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

; This simplified version of add_vibrato is used if portamento but
; not vibrato is enabled
.elseif ::PENTLY_USE_PORTAMENTO

.proc add_vibrato
  lda chPitchLo,x
  .if ::PENTLY_USE_VIS
    sta pently_vis_pitchlo,x
  .endif
  beq have_pitchadd
    jsr calc_frac_pitch
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
.proc write_out_volume
  ldy channelVolume,x
  bne chvol_nonzero
    and #$F0
    sta out_volume
    rts
  chvol_nonzero:

  cpy #MAX_CHANNEL_VOLUME
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
.proc calc_frac_pitch
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
.proc update_portamento
portaRateLo = pently_zptemp+0
portaRateHi = pently_zptemp+1

  lda chPortamento,x
  bne not_instant  ; $00: portamento disabled
    sta chPitchLo,x
    lda notePitch,x
    sta chPitchHi,x
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
  lda chPitchLo,x
  sta portaRateLo
  lda chPitchHi,x
  sbc notePitch,x
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
  lda chPortamento,x
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
  lda chPortamento,x
  sta portaRateHi
  jmp portamento_add

calc_fraction:
  ldy chPortamento,x
  lda porta1x_rates_lo-$10,y
  sta portaRateLo
  lda porta1x_rates_hi-$10,y
  sta portaRateHi
portamento_add:
  lda chPitchHi,x
  cmp notePitch,x
  bcs is_decrease
  lda chPitchLo,x
  adc portaRateLo
  sta chPitchLo,x
  lda chPitchHi,x
  adc portaRateHi
  cmp notePitch,x
  bcc have_pitchHi
  at_target:
    lda #0
    sta chPitchLo,x
    lda notePitch,x
  have_pitchHi:
  sta chPitchHi,x
  rts

is_decrease:
  lda chPitchLo,x
  sbc portaRateLo
  sta chPitchLo,x
  lda chPitchHi,x
  sbc portaRateHi
  cmp notePitch,x
  bcs have_pitchHi
  bcc at_target
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
