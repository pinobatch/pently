;
; Pently audio engine
; Music interpreter and instrument renderer
;
; Copyright 2009-2016 Damian Yerrick
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
; 24  | Tri music pattern data ptr          Unused            Unused
; 28  | Noise music pattern data ptr        Conductor segno
; 32  | Attack music pattern data ptr       Conductor track position

; pentlyBSS:
;       +0                +1                +2                +3
;  0-15 Sound effect state for channels
;  0  | Effect rate       Rate counter      Last period MSB   Effect length
; 16-31 Instrument envelope state for channels
; 16  | Sustain vol       Note pitch        Attack length     Attack pitch
; 32-47 Instrument arpeggio state for channels
; 32  | Legato enable     Arpeggio phase    Arp interval 1    Arp interval 2
; 48-57 Instrument vibrato state for channels
; 50-67 Pattern reader state for tracks
; 48  | Vibrato depth     Vibrato phase     Note time left    Transpose amt
; 68  | Grace time        Instrument ID     Pattern ID        Conductor use
; 88 End of allocation
;
; Noise envelope is NOT unused.  Conductor track cymbals use it.

noteAttackPos   = pently_zp_state + 2
musicPatternPos = pently_zp_state + 16
noteEnvVol      = pentlyBSS + 16
notePitch       = pentlyBSS + 17
attack_remainlen= pentlyBSS + 18
attackPitch     = pentlyBSS + 19
noteLegato      = pentlyBSS + 32
arpPhase        = pentlyBSS + 33
arpInterval1    = pentlyBSS + 34
arpInterval2    = pentlyBSS + 35
vibratoDepth    = pentlyBSS + 48
vibratoPhase    = pentlyBSS + 49
noteRowsLeft    = pentlyBSS + 50
patternTranspose= pentlyBSS + 51
graceTime       = pentlyBSS + 68
noteInstrument  = pentlyBSS + 69
musicPattern    = pentlyBSS + 70

; Shared state

pently_music_playing    = pently_zp_state + 18
attackChannel           = pently_zp_state + 19
music_tempoLo           = pently_zp_state + 22
music_tempoHi           = pently_zp_state + 23
conductorSegnoLo        = pently_zp_state + 30
conductorSegnoHi        = pently_zp_state + 31
conductorPos            = pently_zp_state + 34

conductorWaitRows       = pentlyBSS + 71
pently_rows_per_beat    = pentlyBSS + 75
pently_row_beat_part    = pentlyBSS + 79
pently_tempoCounterLo   = pentlyBSS + 83
pently_tempoCounterHi   = pentlyBSS + 87

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
; bit 2: negate; bits 1-0: amplitude
vibratoPattern:
  .byt 6,7,7,7,6,0,2,3,3,3,2
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
    dex
    dex
    dex
    dex
    bpl channelLoop
  .if ::PENTLY_USE_ATTACK_TRACK
    lda #0
    sta attackChannel
  .endif
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
    .if ::PENTLY_USE_ATTACK_PHASE
      sta attack_remainlen,x
    .endif
    .if ::PENTLY_USE_ATTACK_TRACK
      cpx #ATTACK_TRACK
      bcs notKeyOff
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
  asl a
  bcc @notSilentPattern
    lda #<silentPattern
    sta musicPatternPos,x
    lda #>silentPattern
    sta musicPatternPos+1,x
    rts
  @notSilentPattern:
  tay
  lda pently_patterns,y
  sta musicPatternPos,x
  lda pently_patterns+1,y
  sta musicPatternPos+1,x
  rts

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
  lda (musicPatternPos,x)
  and #$07
  sta vibratoDepth,x
  jmp nextPatternByte
.else
  handle_vibrato = nextPatternByte 
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

.proc pently_update_music_ch
xsave        = pently_zptemp + 0
pitchadd_lo  = pently_zptemp + 1
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

.if ::PENTLY_USE_ATTACK_PHASE

  lda attack_remainlen,x
  beq noAttack
  dec attack_remainlen,x
  lda (noteAttackPos,x)
  inc noteAttackPos,x
  bne :+
  inc noteAttackPos+1,x
:
  sta out_volume
  lda (noteAttackPos,x)
  inc noteAttackPos,x
  bne :+
  inc noteAttackPos+1,x
:
  clc
  adc attackPitch,x
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
  .if ::PENTLY_USE_VIBRATO
    jmp calc_vibrato
  .else
    rts
  .endif
.else
storePitchWithArpeggio:
.endif

storePitchNoArpeggio:
  sta out_pitch
  .if ::PENTLY_USE_VIBRATO
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
  sta out_volume
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
  lda notePitch,x
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
calc_vibrato:
vibratoBits = xsave
  lda #0
  sta pitchadd_lo
  sta out_pitchadd
  lda vibratoDepth,x  ; Skip calculation if depth is 0
  beq not_vibrato

  ; Clock vibrato
  ldy vibratoPhase,x
  bne :+
    ldy #12
  :
  dey
  tya
  sta vibratoPhase,x
  cpy #11
  bcs not_vibrato
  .if ::PENTLY_USE_ATTACK_TRACK
    lda arpPhase,x      ; Suppress vibrato from injected attack
    bmi not_vibrato     ; (even though we still clock it)
  .endif

  ; Step 1: Calculate the delta to apply based on pitch
  lda vibratoPattern,y
  ldy notePitch,x
  lsr a
  sta vibratoBits
  bcc notvibratobit0  ; Bit 0: add P/2
    lda periodTableHi,y
    lsr a
    sta out_pitchadd
    lda periodTableLo,y
    ror a
    sta pitchadd_lo
  notvibratobit0:

  lsr vibratoBits
  bcc notvibratobit1  ; Bit 1: add P
    clc
    lda periodTableLo,y
    adc pitchadd_lo
    sta pitchadd_lo
    lda periodTableHi,y
    adc out_pitchadd
    sta out_pitchadd
  notvibratobit1:

  lsr vibratoBits
  bcc notvibratobit2  ; Bit 2: negate
    lda #$FF
    eor pitchadd_lo
    sta pitchadd_lo
    lda #$FF
    eor out_pitchadd
    sta out_pitchadd
  notvibratobit2:

  ldy vibratoDepth,x
  dey
  beq not_vibrato
  lda pitchadd_lo
  vibratodepthloop:
    asl a
    rol out_pitchadd
    dey
    bne vibratodepthloop
  cmp #$80
  bcc not_vibrato
    inc out_pitchadd
not_vibrato:
  rts
.endif

.endproc

