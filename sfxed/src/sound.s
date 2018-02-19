; sound.s
; part of sound engine for Concentration Room, Thwaite, Zap Ruder,
; and RHDE
; Copyright 2009-2014 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
.import periodTableLo, periodTableHi
;.import update_music, update_music_ch, music_playing
.import psg_sound_table
.export init_sound, start_sound, update_sound, soundBSS

; as of the implementation of "attacks" in the instrument engine,
; this is a 36 byte buffer
.importzp psg_sfx_state

SNDCHN = $4015

; Ordinarily, the effect engine will move a pulse sound effect from
; $4000 to $4004 if $4004 is idle and $4000 is not, or if $4004 has
; less sfx data left to play than $4000.  Turn this off to force all
; pulse sfx to be played on $4000.
SQUARE_POOLING = 1

; As of 2011-03-10, a sound effect interrupts a musical instrument on
; the same channel only if the volume of the sfx is greater than that
; of the instrument.  Turn this off to force sound fx to interrupt
; the music whenever sfx data remains on that channel, even if the
; music is louder.
KEEP_MUSIC_IF_LOUDER = 0

.segment "BSS"
soundBSS: .res 80

psg_sfx_datalo = psg_sfx_state + 0
psg_sfx_datahi = psg_sfx_state + 1
psg_sfx_rate = soundBSS + 0
psg_sfx_ratecd = soundBSS + 1
psg_sfx_lastfreqhi = soundBSS + 2
psg_sfx_remainlen = soundBSS + 3

.ifndef SOUND_NTSC_ONLY
SOUND_NTSC_ONLY = 0
.endif
.if (!SOUND_NTSC_ONLY)
.importzp tvSystem
.endif

.segment "CODE"

;;
; Initializes all sound channels.
; Call this at the start of a program or as a "panic button" before
; entering a long stretch of code where you don't call update_sound.
;
.proc init_sound
  lda #$0F
  sta SNDCHN
  lda #$30
  sta $4000
  sta $4004
  sta $400C
  sta psg_sfx_lastfreqhi+0
  sta psg_sfx_lastfreqhi+8
  sta psg_sfx_lastfreqhi+4
  lda #$80
  sta $4008
  lda #8
  sta $4001
  sta $4005
  lda #0
  sta $4003
  sta $4007
  sta $400F
  sta psg_sfx_remainlen+0
  sta psg_sfx_remainlen+4
  sta psg_sfx_remainlen+8
  sta psg_sfx_remainlen+12
  sta psg_sfx_ratecd+0
  sta psg_sfx_ratecd+4
  sta psg_sfx_ratecd+8
  sta psg_sfx_ratecd+12
;  sta music_playing
  lda #64
  sta $4011
  rts
.endproc

;;
; Starts a sound effect.
; (Trashes $0000-$0004 and X.)
;
; The table format is
; 0-1: pointer to start of sfx data
; 2: d7-d4: rate; d3-d2: channel number; d1-d0: ignored
; 3: length in 2-byte rows
;
; @param A sound effect number (0-63)
;
.proc start_sound
snddatalo = 0
snddatahi = 1
sndchno = 2
sndlen = 3
sndrate = 4

  asl a
  asl a
  tax
  lda psg_sound_table,x
  sta snddatalo
  lda psg_sound_table+1,x
  sta snddatahi
  lda psg_sound_table+2,x
  and #$0C
  sta sndchno
  lda psg_sound_table+2,x
  lsr a
  lsr a
  lsr a
  lsr a
  sta sndrate
  
  lda psg_sound_table+3,x
  sta sndlen

  ; split up square wave sounds between $4000 and $4004
  .if ::SQUARE_POOLING
    lda sndchno
    bne not_ch0to4  ; if not ch 0, don't try moving it
      lda psg_sfx_remainlen+4
      cmp psg_sfx_remainlen
      bcs not_ch0to4
      lda #4
      sta sndchno
    not_ch0to4:
  .endif 

  ldx sndchno
  lda sndlen
  cmp psg_sfx_remainlen,x
  bcc ch_full
  lda snddatalo
  sta psg_sfx_datalo,x
  lda snddatahi
  sta psg_sfx_datahi,x
  lda sndlen
  sta psg_sfx_remainlen,x
  lda sndrate
  sta psg_sfx_rate,x
  lda #0
  sta psg_sfx_ratecd,x
ch_full:
  rts
.endproc


;;
; Updates sound effect channels.
;
.proc update_sound
;  jsr update_music
  ldx #12
loop:
;  jsr update_music_ch
  lda #0
  sta 2  ; the null music engine
  jsr update_one_ch
  dex
  dex
  dex
  dex
  bpl loop
  rts
.endproc

.proc update_one_ch

  ; At this point, the music engine should have left duty and volume
  ; in 2 and pitch in 3.
  lda psg_sfx_remainlen,x
  ora psg_sfx_ratecd,x
  bne ch_not_done
  lda 2
  bne update_channel_hw

  ; Turn off the channel and force a reinit of the length counter.
  cpx #8
  beq not_triangle_kill
    lda #$30
  not_triangle_kill:
  sta $4000,x
  lda #$FF
  sta psg_sfx_lastfreqhi,x
  rts
ch_not_done:

  ; playback rate divider
  dec psg_sfx_ratecd,x
  bpl rate_divider_cancel
  lda psg_sfx_rate,x
  sta psg_sfx_ratecd,x

  ; fetch the instruction
  lda psg_sfx_datalo+1,x
  sta 1
  lda psg_sfx_datalo,x
  sta 0
  clc
  adc #2
  sta psg_sfx_datalo,x
  bcc :+
  inc psg_sfx_datahi,x
:
  ldy #0
  .if ::KEEP_MUSIC_IF_LOUDER
    lda 2
    and #$0F
    sta 4
    lda (0),y
    and #$0F
    
    ; At this point: A = sfx volume; 4 = musc volume
    cmp 4
    bcc music_was_louder
  .endif
  lda (0),y
  sta 2
  iny
  lda (0),y
  sta 3
music_was_louder:
  dec psg_sfx_remainlen,x

update_channel_hw:
  lda 2
  ora #$30
  cpx #12
  bne notnoise
  sta $400C
  lda 3
  sta $400E
rate_divider_cancel:
  rts

notnoise:
  cpx #8
  bne :+
  and #$0F
  beq :+
    ora #$80  ; for triangle keep bit 7 (linear counter load) on
  :
  sta $4000,x
  ldy 3
.if ::SOUND_NTSC_ONLY = 0
  lda tvSystem
  lsr a
  bcc :+
  iny
:
.endif
  lda periodTableLo,y
  sta $4002,x
  lda periodTableHi,y
  cmp psg_sfx_lastfreqhi,x
  beq no_change_to_hi_period
  sta psg_sfx_lastfreqhi,x
  sta $4003,x
no_change_to_hi_period:

  rts
.endproc

