;
; Pently audio engine
; Music interpreter and instrument renderer
;
; Copyright 2009-2016 Damian Yerrick
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

.importzp pently_zp_state, PENTLYBSS_SIZE
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

.if PENTLY_USE_ATTACK_TRACK
  LAST_TRACK = ATTACK_TRACK
.else
  LAST_TRACK = DRUM_TRACK
.endif

; pently_zp_state:
;       +0                +1                +2                +3
;  0  | Sq1 sound effect data ptr           Sq1 envelope data ptr
;  4  | Sq2 sound effect data ptr           Sq2 envelope data ptr
;  8  | Tri sound effect data ptr           Tri envelope data ptr
; 12  | Noise sound effect data ptr         Noise envelope data ptr
; 16  | Sq1 music pattern data ptr          Play/Pause        Attack channel
; 20  | Sq2 music pattern data ptr          Tempo
; 24  | Tri music pattern data ptr          Tempo counter
; 28  | Noise music pattern data ptr        Conductor segno
; 32  | Attack music pattern data ptr       Conductor track position

; pentlyBSS:
;       +0                +1                +2                +3
;  0-15 Sound effect state for channels
;  0  | Effect rate       Rate counter      Last period MSB   Effect length
; 16-31 Instrument envelope state for channels
; 16  | Sustain vol       Note pitch        Attack length     Attack pitch
; 32-47 Portamento state for channels
; 32  | Current pitch/256 Current pitch     Portamento rate   (conductor)
; 48-63 Instrument arpeggio state for channels
; 48  | Legato enable     Arpeggio phase    Arp interval 1    Arp interval 2
; 64-83 Instrument vibrato state for channels
; 67-103 Pattern reader state for tracks
; 64  | Vibrato depth     Vibrato phase     Channel volume    Note time left
; 84  | Grace time        Instrument ID     Pattern ID        Transpose amt
; 104 End of allocation
;
; Noise envelope is NOT unused.  Conductor track cymbals use it.

noteAttackPos   = pently_zp_state + 2
musicPatternPos = pently_zp_state + 16
noteEnvVol      = pentlyBSS + 16
notePitch       = pentlyBSS + 17
attack_remainlen= pentlyBSS + 18
attackPitch     = pentlyBSS + 19
chPitchLo       = pentlyBSS + 32
chPitchHi       = pentlyBSS + 33
chPortamento    = pentlyBSS + 34
chPortaUnused   = pentlyBSS + 35
noteLegato      = pentlyBSS + 48
arpPhase        = pentlyBSS + 49
arpInterval1    = pentlyBSS + 50
arpInterval2    = pentlyBSS + 51
vibratoDepth    = pentlyBSS + 64
vibratoPhase    = pentlyBSS + 65
channelVolume   = pentlyBSS + 66
noteRowsLeft    = pentlyBSS + 67
graceTime       = pentlyBSS + 84
noteInstrument  = pentlyBSS + 85
musicPattern    = pentlyBSS + 86
patternTranspose= pentlyBSS + 87

; Shared state

pently_music_playing    = pently_zp_state + 18
attackChannel           = pently_zp_state + 19
music_tempoLo           = pently_zp_state + 22
music_tempoHi           = pently_zp_state + 23
pently_tempoCounterLo   = pently_zp_state + 26
pently_tempoCounterHi   = pently_zp_state + 27
conductorSegnoLo        = pently_zp_state + 30
conductorSegnoHi        = pently_zp_state + 31
conductorPos            = pently_zp_state + 34

conductorWaitRows       = chPortaUnused + 0
pently_rows_per_beat    = chPortaUnused + 4
pently_row_beat_part    = chPortaUnused + 8

.segment PENTLY_RODATA

FRAMES_PER_MINUTE_PAL = 3000
FRAMES_PER_MINUTE_NTSC = 3606
pently_fpmLo:
  .byt <FRAMES_PER_MINUTE_NTSC, <FRAMES_PER_MINUTE_PAL
pently_fpmHi:
  .byt >FRAMES_PER_MINUTE_NTSC, >FRAMES_PER_MINUTE_PAL

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
.proc pently_start_music
  asl a
  tax
  lda pently_songs,x
  sta conductorPos
  sta conductorSegnoLo
  lda pently_songs+1,x
  sta conductorPos+1
  sta conductorSegnoHi

  ldy #PENTLYBSS_SIZE - 17
  lda #0
  .if ::PENTLY_USE_ATTACK_TRACK
    sta attackChannel
  .endif
  :
    sta pentlyBSS+16,y
    dey
    bpl :-

  ldx #LAST_TRACK
  channelLoop:
    lda #<silentPattern
    sta musicPatternPos,x
    lda #>silentPattern
    sta musicPatternPos+1,x
    lda #$FF
    sta musicPattern,x
    .if ::PENTLY_USE_CHANNEL_VOLUME
      lda #MAX_CHANNEL_VOLUME
      sta channelVolume,x
    .endif
    dex
    dex
    dex
    dex
    bpl channelLoop

  lda #$FF
  sta pently_tempoCounterLo
  sta pently_tempoCounterHi
  .if ::PENTLY_USE_BPMMATH
    sta pently_row_beat_part
    lda #4
    sta pently_rows_per_beat
  .endif
  lda #<300
  sta music_tempoLo
  lda #>300
  sta music_tempoHi
.endproc
.proc pently_resume_music
  lda #1
  sta pently_music_playing
  rts
.endproc

.proc pently_stop_music
  lda #0
  sta pently_music_playing
  rts
.endproc

.proc pently_update_music
  lda pently_music_playing
  beq music_not_playing
  lda music_tempoLo
  clc
  adc pently_tempoCounterLo
  sta pently_tempoCounterLo
  lda music_tempoHi
  adc pently_tempoCounterHi
  sta pently_tempoCounterHi
  bcs new_tick
music_not_playing:
  rts
new_tick:

.if ::PENTLY_USE_PAL_ADJUST
  ldy tvSystem
  beq is_ntsc_1
  ldy #1
is_ntsc_1:
.else
  ldy #0
.endif

  ; Subtract tempo
  lda pently_tempoCounterLo
  sbc pently_fpmLo,y
  sta pently_tempoCounterLo
  lda pently_tempoCounterHi
  sbc pently_fpmHi,y
  sta pently_tempoCounterHi

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

  lda conductorWaitRows
  beq doConductor
  dec conductorWaitRows
  jmp skipConductor

doConductor:
conbyte = pently_zptemp + 0

  ldy #0
  lda (conductorPos),y
  inc conductorPos
  bne :+
    inc conductorPos+1
  :
;  sta conbyte
  cmp #CON_SETTEMPO
  bcc @notTempoChange
  cmp #CON_SETBEAT
  bcc @isTempoChange
    .if ::PENTLY_USE_BPMMATH
      and #%00000111
      tay
      lda durations,y
      sta pently_rows_per_beat
      ldy #0
      sty pently_row_beat_part
    .endif
    jmp doConductor
  @isTempoChange:
    and #%00000111
    sta music_tempoHi
  
    lda (conductorPos),y
    inc conductorPos
    bne :+
      inc conductorPos+1
    :
    sta music_tempoLo
    jmp doConductor
  @notTempoChange:
  cmp #CON_WAITROWS
  bcc conductorPlayPattern
  bne @notWaitRows
    jmp conductorDoWaitRows
  @notWaitRows:

  cmp #CON_ATTACK_SQ1
  bcc @notAttackSet
  cmp #CON_NOTEON
  bcs @handleNoteOn
    .if ::PENTLY_USE_ATTACK_TRACK
      and #%00000011
      asl a
      asl a
      sta attackChannel
    .endif
    jmp doConductor
  @handleNoteOn:
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
    inc conductorPos
    bne :+
      inc conductorPos+1
    :
    tay
    pla
    jsr pently_play_note
    jmp doConductor

  @notAttackSet:

  cmp #CON_FINE
  bne @notFine
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
  @notFine:

  cmp #CON_SEGNO
  bne @notSegno
    lda conductorPos
    sta conductorSegnoLo
    lda conductorPos+1
    sta conductorSegnoHi
    jmp doConductor
  @notSegno:

  cmp #CON_DALSEGNO
  bne @notDalSegno
    lda conductorSegnoLo
    sta conductorPos
    lda conductorSegnoHi
    sta conductorPos+1
.if ::PENTLY_USE_ROW_CALLBACK
    sec
    jsr pently_dalsegno_callback
.endif
    jmp doConductor
  @notDalSegno:
  
  jmp skipConductor

conductorPlayPattern:
  and #$07
  asl a
  asl a
  tax

  lda #0
  cpx #ATTACK_TRACK
.if ::PENTLY_USE_ATTACK_TRACK
  bcs skipClearLegato
.else
  bcc isValidTrack
    lda #2
    bcs skipAplusCconductor
  isValidTrack:
.endif
    sta noteLegato,x  ; start all patterns with legato off
  skipClearLegato:
  sta noteRowsLeft,x
  lda (conductorPos),y
  sta musicPattern,x
  iny
  lda (conductorPos),y
  sta patternTranspose,x
  iny
  lda (conductorPos),y
  sta noteInstrument,x
  tya
  sec
skipAplusCconductor:
  adc conductorPos
  sta conductorPos
  bcc :+
    inc conductorPos+1
  :
  jsr startPattern
  jmp doConductor

  ; this should be last so it can fall into skipConductor
conductorDoWaitRows:
  lda (conductorPos),y
  inc conductorPos
  bne :+
    inc conductorPos+1
  :
  sta conductorWaitRows

skipConductor:

  ldx #4 * (NUM_CHANNELS - 1)
  channelLoop:
    jsr processTrackPattern
    dex
    dex
    dex
    dex
    bpl channelLoop

  ; Process attack track last
  .if ::PENTLY_USE_ATTACK_TRACK
    ldx #ATTACK_TRACK
  .else
    rts
  .endif

processTrackPattern:
  lda noteRowsLeft,x
  beq anotherPatternByte
skipNote:
  dec noteRowsLeft,x
  rts

anotherPatternByte:
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
  lsr a
  lsr a
  lsr a
  cmp #25
  bcc isTransposedNote
  beq notKeyOff
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

startPattern:
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

; Effect handlers

.pushseg
.segment PENTLY_RODATA
patcmdhandlers:
  .addr handle_instrument-1
  .addr handle_arpeggio-1
  .addr handle_legato-1
  .addr handle_legato-1
  .addr handle_transpose-1
  .addr handle_grace-1
  .addr handle_vibrato-1
  .addr handle_ch_volume-1

  .addr handle_portamento-1

num_patcmdhandlers = (* - patcmdhandlers) / 2
.popseg

handle_instrument:
  lda (musicPatternPos,x)
  sta noteInstrument,x
nextPatternByte:
  inc musicPatternPos,x
  bne :+
    inc musicPatternPos+1,x
  :
  jmp anotherPatternByte

.if ::PENTLY_USE_ARPEGGIO
handle_arpeggio:
  cpx #12
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
.else
  handle_arpeggio = nextPatternByte
.endif

handle_legato:
  cpx #12
  bcs :+
    tya
    and #$02
    sta noteLegato,x
  :
  jmp anotherPatternByte

handle_grace:
  lda (musicPatternPos,x)
  sta graceTime,x
  jmp nextPatternByte

handle_transpose:
  lda patternTranspose,x
  adc (musicPatternPos,x)
  sta patternTranspose,x
  jmp nextPatternByte

.if ::PENTLY_USE_VIBRATO
handle_vibrato:
  cpx #12
  bcs :+
    lda (musicPatternPos,x)
    and #$07
    sta vibratoDepth,x
  :
  jmp nextPatternByte
.else
  handle_vibrato = nextPatternByte 
.endif

.if ::PENTLY_USE_PORTAMENTO
handle_portamento:
  cpx #12
  bcs :+
    lda (musicPatternPos,x)
    sta chPortamento,x
  :
  jmp nextPatternByte
.else
  handle_portamento = nextPatternByte 
.endif

.if ::PENTLY_USE_CHANNEL_VOLUME
handle_ch_volume:
  lda (musicPatternPos,x)
  sta channelVolume,x
  jmp nextPatternByte
.else
  handle_ch_volume = nextPatternByte 
.endif

.endproc

;;
; Plays note A on channel X (0, 4, 8, 12) with instrument Y.
; Trashes 0-1 and preserves X.
.proc pently_play_note
notenum       = pently_zptemp + 0
instrument_id = pently_zptemp + 1

  sta notenum
  sty instrument_id
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
.endif
      lda notenum
      sta attackPitch,x
    dont_legato_injected_attack:
    lda notenum
    sta notePitch,x
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
      .if ::PENTLY_USE_ATTACK_TRACK || ::PENTLY_USE_ARPEGGIO
        lda #0
        sta arpPhase,x  ; bits 2-0: arp phase; 7: is attack injected
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
      bcc notAttackChannel
        ldx attackChannel
        lda #$80  ; Disable arpeggio, vibrato, and legato until sustain
        sta arpPhase,x
      notAttackChannel:
    .endif
    lda notenum
    sta attackPitch,x
    
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

;;
; Calculates the pitch, detune amount, and volume for channel X.
; @return out_volume: value for $4000/$4004/$4008/$400C
;   out_pitch: semitone number
;   out_pitchadd: amount to add to semitone
;   X: preserved
.proc pently_update_music_ch
xsave        = pently_zptemp + 0
unused       = pently_zptemp + 1
out_volume   = pently_zptemp + 2
out_pitch    = pently_zptemp + 3
out_pitchadd = pently_zptemp + 4

  lda pently_music_playing
  beq silenced
  lda graceTime,x
  beq nograce
  dec graceTime,x
  bne nograce
    jsr pently_update_music::processTrackPattern
  nograce:
  
.if ::PENTLY_USE_PORTAMENTO
  jsr update_portamento
.endif

.if ::PENTLY_USE_ATTACK_PHASE

  lda attack_remainlen,x
  beq noAttack
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

  .if ::PENTLY_USE_PORTAMENTO
    ; Use portamento pitch if not injected
    cpx #12
    bcs attack_not_pitched_ch
      lda arpPhase,x
      asl a
      lda chPitchHi,x
      bcc porta_not_injected
    attack_not_pitched_ch:
  .endif  
  lda attackPitch,x
porta_not_injected:
  clc
  adc (noteAttackPos,x)
  inc noteAttackPos,x
  bne :+
    inc noteAttackPos+1,x
  :
.else
  jmp noAttack
.endif

  ; At this point, A is the note pitch with envelope modification.
  ; Arpeggio still needs to be applied, but not to injected attacks.
  ; Because bit 7 of arpPhase tells the rest of Pently (particularly
  ; legato and vibrato) whether an attack is injected,
  ; storePitchWithArpeggio still clears this bit during sustain phase
  ; even if arpeggio is disabled at build time.
  ; But if both arpeggio and attack injection are disabled, treat
  ; "with arpeggio" and "no arpeggio" the same.
.if ::PENTLY_USE_ATTACK_TRACK
  ldy arpPhase,x
  bmi storePitchNoArpeggio
.endif
.if ::PENTLY_USE_ARPEGGIO || ::PENTLY_USE_ATTACK_TRACK
storePitchWithArpeggio:
  sta out_pitch

.if ::PENTLY_USE_ARPEGGIO
  stx xsave
  lda #$7F
  and arpPhase,x
  tay
  beq bumpArpPhase

  ; So we're in a nonzero phase.  Load the interval.
  clc
  adc xsave
  tax
  lda arpInterval1-1,x

  ; If phase 2's interval is 0, cycle through two phases (1, 2)
  ; instead of three (0, 1, 2).
  bne bumpArpPhase
  cpy #2
  bcc bumpArpPhase
  ldy #0
bumpArpPhase:
  iny
  cpy #3
  bcc noArpRestart
  ldy #0
noArpRestart:

  ; At this point, A is the arpeggio interval and Y is the next phase
  clc
  adc out_pitch
  sta out_pitch
  ldx xsave
  tya
.else
  ; If arpeggio is off, just clear the attack injection flag
  lda #0
.endif
  sta arpPhase,x
  .if ::PENTLY_USE_VIBRATO || ::PENTLY_USE_PORTAMENTO
    jmp calc_vibrato
  .else
    rts
  .endif
.else
storePitchWithArpeggio:
.endif

storePitchNoArpeggio:
  sta out_pitch
  .if ::PENTLY_USE_VIBRATO || ::PENTLY_USE_PORTAMENTO
    jmp calc_vibrato
  .else
    rts
  .endif

noAttack:
  lda noteEnvVol,x
  lsr a
  lsr a
  lsr a
  lsr a
  bne notSilenced
silenced:
  lda #0
  sta out_volume
  rts
notSilenced:
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
  and #$0F
  eor pently_instruments,y
  sta out_volume
  lda noteEnvVol,x
  sec
  sbc pently_instruments+1,y
  bcc silenced
  sta noteEnvVol,x
  tya
  pha
  .if ::PENTLY_USE_PORTAMENTO
    lda chPitchHi,x
    cpx #12
    bcc noattack_is_pitched_ch
  .endif
    lda notePitch,x
  noattack_is_pitched_ch:
  jsr storePitchWithArpeggio
  pla
  tay

  ; bit 7 of attribute 2: cut note when half a row remains
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
  beq yesCutNote
  and #$F8
  cmp #N_TIE
  beq notCutNote
  lda noteLegato,x
  bne notCutNote
yesCutNote:
  lda #0
  sta noteEnvVol,x
notCutNote:
  rts

.if ::PENTLY_USE_VIBRATO
VIBRATO_PERIOD = 12

calc_vibrato:
  .if ::PENTLY_USE_PORTAMENTO
    ; Don't apply portamento to injected attacks
    lda arpPhase,x
    bmi is_injected
      lda chPitchLo,x
      jmp not_injected
    is_injected:
  .endif
  lda #0
not_injected:
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
  .if ::PENTLY_USE_ATTACK_TRACK
    lda arpPhase,x      ; Suppress vibrato from injected attack
    bmi not_vibrato     ; (even though we still clock it)
  .endif

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

; This simplified version of calc_vibrato is used if portamento but
; not vibrato is enabled
.elseif ::PENTLY_USE_PORTAMENTO
calc_vibrato:
  lda arpPhase,x
  bpl not_injected
    lda #0
    beq have_pitchadd
  not_injected:
  lda chPitchLo,x
  beq have_pitchadd
  jsr calc_frac_pitch
  eor #$FF
  clc
  adc #1
have_pitchadd:
  sta out_pitchadd
  rts
.endif

.if ::PENTLY_USE_CHANNEL_VOLUME
write_out_volume:
  ldy channelVolume,x
  bne chvol_nonzero
  and #$F0
chvol_unchanged:
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
  sta out_volume
  rts
.endif

.endproc

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

  cpx #12
  bcs not_pitched_ch
  lda chPortamento,x
  bne not_instant  ; $00: portamento disabled
    sta chPitchLo,x
    lda notePitch,x
    sta chPitchHi,x
    rts
  not_instant:

  and #$30
  lsr a
  lsr a
  lsr a
  tay
  lda portamentocalc_funcs+1,y
  pha
  lda portamentocalc_funcs+0,y
  pha
not_pitched_ch:
  rts

; These functions calculate the instantaneous portamento rate

portamentocalc_funcs:
  .addr calc_whole_semitone-1
  .addr calc_fraction-1
  .addr calc_tb303-1
  .addr calc_tb303-1
num_portamentocalc_funcs = (* - portamentocalc_funcs) / 2

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
  jmp portamento_add

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

  ; Scale based on approach time setting
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