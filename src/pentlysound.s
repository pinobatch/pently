;
; Pently audio engine
; Sound effect player and "mixer"
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

.include "pently.inc"
.if PENTLY_USE_MUSIC
  .import pentlyi_update_music, pentlyi_update_music_ch
.endif
.import periodTableLo, periodTableHi, pently_sfx_table
.if PENTLY_USE_PAL_ADJUST
  .importzp tvSystem
.endif
.export pentlyBSS
.exportzp pently_zp_state

.assert (pently_zptemp + 5) <= $100, error, "pently_zptemp must be within zero page"

PENTLY_PULSE1_CH = $00
PENTLY_PULSE2_CH = $04
PENTLY_TRI_CH = $08
PENTLY_NOISE_CH = $0C
PENTLY_SFX_CH_BITS = $0C
PENTLY_ATTACK_TRACK = $10

.zeropage
.if PENTLY_USE_MUSIC = 0
  PENTLYZP_SIZE = 16
.elseif PENTLY_USE_ATTACK_PHASE
  PENTLYZP_SIZE = 32
.else
  PENTLYZP_SIZE = 21
.endif
pently_zp_state: .res PENTLYZP_SIZE
pentlyi_sfx_datalo = pently_zp_state + 0
pentlyi_sfx_datahi = pently_zp_state + 1

.bss
; The statically allocated prefix of pentlyBSS
pentlyBSS: .res 18

pentlyi_sfx_rate = pentlyBSS + 0
pentlyi_sfx_ratecd = pentlyBSS + 1
pentlyi_ch_lastfreqhi = pentlyBSS + 2
pentlyi_sfx_remainlen = pentlyBSS + 3

.segment PENTLY_CODE
pentlysound_code_start = *

;;
; Initializes all sound channels.
; Call this at the start of a program or as a "panic button" before
; entering a long stretch of code where you don't call pently_update.
;
.proc pently_init
SNDCHN = $4015

  ; Turn on all channels
  lda #$0F
  sta SNDCHN
  ; Disable pulse sweep
  lda #8
  sta $4001
  sta $4005
  ; Invalidate last frequency high byte
  lda #$30
  sta pentlyi_ch_lastfreqhi+0
  sta pentlyi_ch_lastfreqhi+4
  ; Ignore length counters and use software volume
  sta $4000
  sta $4004
  sta $400C
  lda #$80
  sta $4008
  ; Clear high period, forcing a phase reset
  asl a
  sta $4003
  sta $4007
  sta $400F
  ; Clear sound effects state
  sta pentlyi_sfx_remainlen+0
  sta pentlyi_sfx_remainlen+4
  sta pentlyi_sfx_remainlen+8
  sta pentlyi_sfx_remainlen+12
  sta pentlyi_sfx_ratecd+0
  sta pentlyi_sfx_ratecd+4
  sta pentlyi_sfx_ratecd+8
  sta pentlyi_sfx_ratecd+12
  .if ::PENTLY_USE_MUSIC
    sta pently_music_playing
  .endif
  ; Set DAC value, which controls pulse vs. not-pulse balance
  lda #PENTLY_INITIAL_4011
  sta $4011
  rts
.endproc

;;
; Starts a sound effect.
; (Trashes pently_zptemp+0 through +4 and X.)
;
; @param A sound effect number (0-63)
;
.proc pently_start_sound
snddatalo = pently_zptemp + 0
snddatahi = pently_zptemp + 1
sndlen    = pently_zptemp + 3
sndrate   = pently_zptemp + 4

  asl a
  asl a
  tax
  lda pently_sfx_table,x
  sta snddatalo
  lda pently_sfx_table+1,x
  sta snddatahi
  lda pently_sfx_table+2,x
  lsr a
  lsr a
  lsr a
  lsr a
  sta sndrate
  lda pently_sfx_table+3,x
  sta sndlen
  lda pently_sfx_table+2,x
  and #PENTLY_SFX_CH_BITS
  tax

  ; Split up square wave sounds between pulse 1 ($4000) and
  ; pulse 2 ($4004) depending on which has less data left to play
  .if ::PENTLY_USE_SQUARE_POOLING
    bne not_ch0to4  ; if not ch 0, don't try moving it
      lda pentlyi_sfx_remainlen+4
      cmp pentlyi_sfx_remainlen
      bcs not_ch0to4
      ldx #4
    not_ch0to4:
  .endif 

  ; If this sound effect is no shorter than the existing effect
  ; on the same channel, replace the current effect if any
  lda sndlen
  cmp pentlyi_sfx_remainlen,x
  bcc ch_full
    sta pentlyi_sfx_remainlen,x
    lda snddatalo
    sta pentlyi_sfx_datalo,x
    lda snddatahi
    sta pentlyi_sfx_datahi,x
    lda sndrate
    sta pentlyi_sfx_rate,x
    sta pentlyi_sfx_ratecd,x
  ch_full:

  rts
.endproc

;;
; Updates sound effect channels.
;
.proc pently_update
  .if ::PENTLY_USE_MUSIC
    jsr pentlyi_update_music
  .endif
  ldx #PENTLY_NOISE_CH
loop:
  .if ::PENTLY_USE_MUSIC
    jsr pentlyi_update_music_ch
  .endif
  jsr pentlyi_mix_sfx
  dex
  dex
  dex
  dex
  bpl loop
  .if ::PENTLY_USE_ATTACK_TRACK
    ldx #PENTLY_ATTACK_TRACK
    jmp pentlyi_update_music_ch
  .else
    rts
  .endif
.endproc

pentlyi_out_volume   = pently_zptemp + 2
pentlyi_out_pitch    = pently_zptemp + 3
pentlyi_out_pitchadd = pently_zptemp + 4

.proc pentlyi_mix_sfx
srclo        = pently_zptemp + 0
srchi        = pently_zptemp + 1

  ; At this point, pently_update_music_ch should have left
  ; duty and volume in pentlyi_out_volume and pitch in pentlyi_out_pitch.
  lda pentlyi_sfx_remainlen,x
  bne ch_not_done
  
    ; Only music is playing on this channel, no sound effect
    .if ::PENTLY_USE_MUSIC
      lda pentlyi_out_volume
      .if ::PENTLY_USE_VIS
        sta pently_vis_dutyvol,x
      .endif
      bne pentlyi_write_psg_chn
    .endif

    ; Turn off the channel and force a reinit of the length counter.
    ; NSFID by Karmic uses this as part of its signature to detect
    ; Pently.
    cpx #PENTLY_TRI_CH
    beq not_triangle_kill
      lda #$30
    not_triangle_kill:
    sta $4000,x
    lda #$FF
    sta pentlyi_ch_lastfreqhi,x
    rts
  ch_not_done:

  ; Get the sound effect word's address
  lda pentlyi_sfx_datalo+1,x
  sta srchi
  lda pentlyi_sfx_datalo,x
  sta srclo

  ; Advance if playback rate divider says so
  ; NSFID by Karmic detected the version of this passage prior to the
  ; following commit in the 0.05wip10 cycle:
  ; 8ffefe9 fix dubious rate_divider_cancel behavior (2018-08-01)
  dec pentlyi_sfx_ratecd,x
  bpl no_next_word
    clc
    adc #2
    sta pentlyi_sfx_datalo,x
    bcc :+
      inc pentlyi_sfx_datahi,x
    :
    lda pentlyi_sfx_rate,x
    sta pentlyi_sfx_ratecd,x
    dec pentlyi_sfx_remainlen,x
  no_next_word:

  ; fetch the instruction
  ldy #0
  .if ::PENTLY_USE_MUSIC
    .if ::PENTLY_USE_MUSIC_IF_LOUDER
      lda pentlyi_out_volume
      pha
      and #$0F
      sta pentlyi_out_volume
      lda (srclo),y
      and #$0F

      ; At this point: A = sfx volume; pentlyi_out_volume = music volume
      cmp pentlyi_out_volume
      pla
      sta pentlyi_out_volume
      bcc pentlyi_write_psg_chn
    .endif
    .if ::PENTLY_USE_VIBRATO || ::PENTLY_USE_PORTAMENTO
      sty pentlyi_out_pitchadd  ; sfx don't support fine pitch adjustment
      .if ::PENTLY_USE_VIS
        tya
        sta pently_vis_pitchlo,x
      .endif
    .endif
  .endif
  lda (srclo),y
  sta pentlyi_out_volume
  iny
  lda (srclo),y
  sta pentlyi_out_pitch
  ; jmp pentlyi_write_psg_chn
.endproc

.proc pentlyi_write_psg_chn
  ; XXX vis does not work with no-music
  .if ::PENTLY_USE_VIS
    lda pentlyi_out_pitch
    sta pently_vis_pitchhi,x
  .endif
  lda pentlyi_out_volume
  .if ::PENTLY_USE_VIS
    sta pently_vis_dutyvol,x
  .endif
  ora #$30
  cpx #PENTLY_NOISE_CH
  bne notnoise
    sta $400C
    lda pentlyi_out_pitch
    sta $400E
    rts
  notnoise:

  ; If triangle, keep linear counter load (bit 7) on while playing
  ; so that envelopes don't terminate prematurely
  .if ::PENTLY_USE_TRIANGLE_DUTY_FIX
    cpx #PENTLY_TRI_CH
    bne nottri
    and #$0F
    beq nottri
      ora #$80  ; for triangle keep bit 7 (linear counter load) on
    nottri:
  .endif

  sta $4000,x
  ldy pentlyi_out_pitch
  .if ::PENTLY_USE_PAL_ADJUST
    ; Correct pitch for PAL NES only, not NTSC (0) or PAL famiclone (2)
    lda tvSystem
    lsr a
    bcc notpalnes
      iny
    notpalnes:
  .endif

  lda periodTableLo,y
  .if ::PENTLY_USE_VIBRATO || ::PENTLY_USE_PORTAMENTO
    clc
    adc pentlyi_out_pitchadd
    sta $4002,x
    lda pentlyi_out_pitchadd
    and #$80
    bpl pitchadd_positive
      lda #$FF
    pitchadd_positive:
    adc periodTableHi,y
  .else
    sta $4002,x
    lda periodTableHi,y
  .endif
  cpx #8
  beq always_write_high_period
  cmp pentlyi_ch_lastfreqhi,x
  beq no_change_to_hi_period
  sta pentlyi_ch_lastfreqhi,x
always_write_high_period:
  sta $4003,x
no_change_to_hi_period:

  rts
.endproc

PENTLYSOUND_SIZE = * - pentlysound_code_start

; aliases for cc65
_pently_init = pently_init
_pently_start_sound = pently_start_sound
_pently_update = pently_update
