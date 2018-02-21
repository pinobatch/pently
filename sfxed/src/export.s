.include "nes.inc"
.include "global.inc"

LF = $0A
SPACE = $20
nibblesavestart = $7BC0
textfilestart = $6000
psg_sound_data_end = psg_sound_data + BYTES_PER_SOUND * NUM_SOUNDS

.segment "ZEROPAGE"
exportdst: .res 2

.segment "CODE"

; SAVE SOUNDS AS HEX ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc save_to_sram
srclo = $00
srchi = $01
dstlo = exportdst+0
dsthi = exportdst+1

  ; First fill most of SRAM with lines of spaces to make the .sav
  ; look like a text file with UNIX line endings
  lday #$6000
  stay dstlo
  ldx #($8000-$6000)/64
clearloop:
  ldy #63
  lda #LF
  sta (dstlo),y
  lda #SPACE
:
  dey
  sta (dstlo),y
  bne :-
  clc
  lda #64
  adc dstlo
  sta dstlo
  bcc :+
  inc dsthi
:
  dex
  bne clearloop

  jsr export_all_as_text
  
  ; Start calculating the CRC while it's being saved  
  lda #$FF
  sta CRCHI
  sta CRCLO
  lday #nibblesavestart
  stay dstlo

  ; First save the sound data itself
  lday #psg_sound_data
  stay srclo
  
  ; which is all commented out
  ldy #0
  lda #'#'
  jsr export_putchar
  lda #' '
  jsr export_putchar

byteloop:
  ldx #0
  lda (srclo,x)
  jsr putbytewithcrc
  inc srclo
  bne :+
  inc srchi
:
  lda srclo
  cmp #<psg_sound_data_end
  lda srchi
  sbc #>psg_sound_data_end
  bcc byteloop
  
  ; write the mode bytes
  ldx #0
loop:
  stx srclo
  lda pently_sfx_table+2,x
  jsr putbytewithcrc
  lda srclo
  clc
  adc #4
  tax
  cpx #4 * NUM_SOUNDS
  bcc loop
  lda CRCHI
  jsr export_putbyte
  lda CRCLO
  jsr export_putbyte
  lda #LF
  sta (dstlo),y
  rts
  
putbytewithcrc:
  pha
  jsr crc16_update
  pla
.endproc

; Writes two hexadecimal digits at exportdst+Y
.proc export_putbyte
  pha
  lsr a
  lsr a
  lsr a
  lsr a
  jsr putnibble
  pla
  and #$0F
putnibble:
  ora #'0'
  cmp #'0'+10
  bcc export_putchar
  adc #'a'-('0'+10)-1
.endproc
.proc export_putchar
  sta (exportdst),y
  iny
  bne :+
    inc exportdst+1
  :
  rts
.endproc

; LOAD SOUNDS AS HEX ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;
; resulting CRC
; @return A zero and Z flag set iff loaded data is valid
.proc load_from_sram
importsrc = exportdst
importdst = $00
nibbletmp = $02
  ; Start calculating the CRC while it's being loaded  
  lda #$FF
  sta CRCHI
  sta CRCLO
  lday #nibblesavestart + 2
  stay importsrc
  lday #psg_sound_data
  stay importdst
  ldy #0
byteloop:
  jsr read2nibbles
  ldx #0
  sta (importdst,x)
  jsr crc16_update
  inc importdst
  bne :+
  inc importdst+1
:
  lda importdst
  cmp #<psg_sound_data_end
  lda importdst+1
  sbc #>psg_sound_data_end
  bcc byteloop

  ; read the mode bytes
  ; write the mode bytes
  lda #0
loop:
  sta importdst
  jsr read2nibbles
  ldx importdst
  sta pently_sfx_table+2,x
  jsr crc16_update
  lda importdst
  clc
  adc #4
  cmp #4 * NUM_SOUNDS
  bcc loop

  ; now compare the crc in the sram to the expected crc
  jsr read2nibbles
  eor CRCHI
  bne done
  jsr read2nibbles
  eor CRCLO
done:
  rts
.endproc

.proc read2nibbles
nibbletmp = $02
  jsr readnibble
  asl a
  asl a
  asl a
  asl a
  sta nibbletmp
  jsr readnibble
  ora nibbletmp
  rts
.endproc

.proc readnibble
  lda (exportdst),y
  iny
  bne :+
  inc exportdst+1
:
  cmp #'A'
  bcc :+
  sbc #'A'-10
:
  and #$0F
  rts
.endproc

; HUMAN READABLE EXPORT ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc export_puts
  lda export_puts_strs,x
  beq done
  jsr export_putchar
  inx
  bne export_puts
done:
  rts
.endproc

.segment "RODATA"
export_puts_strs:
str_header1 = * - export_puts_strs
  .byte LF,LF,"sfx sfxed_",0
str_header2 = * - export_puts_strs
  .byte " on ",0
str_rateheader = * - export_puts_strs
  .byte LF,"  rate",0
str_volumeheader = * - export_puts_strs
  .byte LF,"  volume",0
str_pitchheader = * - export_puts_strs
  .byte LF,"  pitch",0
str_dutyheader = * - export_puts_strs
  .byte LF,"  timbre",0
str_pulse = * - export_puts_strs
  .byte "pulse",0
str_triangle = * - export_puts_strs
  .byte "triangle",0
str_noise = * - export_puts_strs
  .byte "noise",0

export_puts_chnames:
  .byte str_pulse, str_pulse, str_triangle, str_noise

lilypond_pitchnames:
  .byte 'c', 'c'|$80, 'd', 'd'|$80, 'e'
  .byte 'f', 'f'|$80, 'g', 'g'|$80, 'a', 'a'|$80, 'h'

.segment "CODE"

;;
; Pently with PENTLY_USE_TRIANGLE_DUTY_FIX turned off requires
; bit 7 set in each volume byte of a triangle channel sound effect.
.proc correct_triangle_timbre
fxdata = 0
  asl a
  asl a
  tax
  lda pently_sfx_table+2,x
  and #$0C
  cmp #$08
  bne not_triangle
  lda pently_sfx_table+0,x
  sta fxdata
  lda pently_sfx_table+1,x
  sta fxdata+1
  lda pently_sfx_table+3,x
  beq not_triangle
  tax  ; X = length in rows
  ldy #0
loop:
  lda (fxdata),y
  and #$0F
  ora #$80
  sta (fxdata),y
  iny
  iny
  dex
  bne loop
not_triangle:
  rts
.endproc

;;
; Writes a space then a pitch in Lilypond's variant of Helmholtz
; notation using export_putchar.
; A-0 to B-0 are a,, to h,,
; C-1 to B-1 are c, to h,
; C-2 to B-2 are c to h
; C-3 to B-3 are c' to h'
; C-4 to B-4 are c'' to h''
; etc.
; @param Y low byte of destination position
.proc export_write_pitch
octavenum = $05
xsave = $04

  stx xsave
  ; C-2 is c but the loop adds 1 unconditionally
  ldx #<-3
  stx octavenum

  clc
  adc #9  ; shift octave to multiple of 12
  sec
  octaveloop:
    inx
    sbc #12
    bcs octaveloop
  adc #12
  stx octavenum

  ; A = note number
  tax
  lda #' '
  jsr export_putchar
  lda lilypond_pitchnames,x
  and #$7F
  jsr export_putchar
  lda lilypond_pitchnames,x
  bpl not_sharp
    lda #'#'
    jsr export_putchar
  not_sharp:

  ldx octavenum
  beq no_octave_difference
  bpl write_apostrophes
    ; Write commas for octaves below C-2
    lda #','
    :
      jsr export_putchar
      inx
      bne :-
    beq no_octave_difference  
  write_apostrophes:
    ; Write apostrophes for octaves above B-2
    lda #$27
    :
      jsr export_putchar
      dex
      bne :-
  no_octave_difference:
  ldx xsave
  rts
.endproc
;;
; Writes a space and then a decimal value 0-255
; @param A decimal value
; @param Y used by export_putchar
.proc export_putbyte_decimal
highdigits = $00
  jsr bcd8bit
  pha
  lda #' '
  jsr export_putchar
  lda highdigits
  beq nohighdigits
    cmp #$10
    bcc nohundreds
      jsr export_putbyte
      jmp nohighdigits
    nohundreds:
    lda highdigits
    and #$0F
    ora #'0'
    jsr export_putchar
  nohighdigits:
  pla
  ora #'0'
  jmp export_putchar
.endproc


sound_num = $08

;;
; Writes one sound effect.
; @param sound_num sound number (0 to NUM_SOUNDS - 1)
.proc export_write_sound
sound_ch = $09
sound_pos = $0A
sound_ptr = $0C
sound_rate = $0E
sound_len = $0F

  ; "sfx sfxedN"
  ldx #str_header1
  jsr export_puts
  lda #'1'
  clc
  adc sound_num
  jsr export_putchar

  ; "on CHNAME"
  ldx #str_header2
  jsr export_puts
  lda sound_num
  asl a
  asl a
  tax
  lda pently_sfx_table+0,x
  sta sound_ptr
  lda pently_sfx_table+1,x
  sta sound_ptr+1
  lda pently_sfx_table+3,x
  sta sound_len
  lda pently_sfx_table+2,x
  lsr a
  lsr a
  lsr a
  lsr a
  sta sound_rate
  lda pently_sfx_table+2,x
  lsr a
  lsr a
  and #$03
  sta sound_ch
  tax
  lda export_puts_chnames,x
  tax
  jsr export_puts

  ; "rate x"
  lda sound_rate
  beq implicit_rate_1
    ldx #str_rateheader
    jsr export_puts
    inc sound_rate
    lda sound_rate
    jsr export_putbyte_decimal
  implicit_rate_1:
  ; No longer need sound_rate

sound_lenleft = sound_rate

  ; "volume x x x x x"
  ldx #str_volumeheader
  jsr puts_and_rewind
  volloop:
    jsr read1byte
    jsr skip1byte
    and #$0F
    jsr export_putbyte_decimal
    dec sound_lenleft
    bne volloop

  ; "pitch x x x x x"
  ldx #str_pitchheader
  jsr puts_and_rewind
  pitchloop:
    jsr skip1byte
    jsr read1byte
    ldx sound_ch
    cpx #3
    bne pitchloop_notnoise
      and #$0F
      jsr export_putbyte_decimal
      jmp pitchloop_continue
    pitchloop_notnoise:
      and #$7F
      jsr export_write_pitch
    pitchloop_continue:
    dec sound_lenleft
    bne pitchloop

  ldx sound_ch
  cpx #2
  beq no_duty_envelope

  ; "timbre x x x x x"
  bcs noise_duty_envelope
    ldx #str_dutyheader
    jsr puts_and_rewind
    dutyloop:
      jsr read1byte
      jsr skip1byte
      and #$C0
      asl a
      rol a
      rol a
      jsr export_putbyte_decimal
      dec sound_lenleft
      bne dutyloop
    beq no_duty_envelope
  noise_duty_envelope:
    ldx #str_dutyheader
    jsr puts_and_rewind
    ndutyloop:
      jsr skip1byte
      jsr read1byte
      and #$80
      asl a
      rol a
      jsr export_putbyte_decimal
      dec sound_lenleft
      bne ndutyloop
  no_duty_envelope:
  rts

puts_and_rewind:
  lda sound_ptr+0
  sta sound_pos+0
  lda sound_ptr+1
  sta sound_pos+1
  lda sound_len
  sta sound_lenleft
  jmp export_puts

read1byte:
  ldx #0
  lda (sound_pos,x)
skip1byte:
  inc sound_pos
  bne :+
    inc sound_pos+1
  :
  rts
.endproc

.proc export_all_as_text
  ; Step 1: Tidy all sounds, trimming trailing silence
  ; and changing triangle duty to 2.
  lda #>textfilestart
  sta exportdst+1
  ldy #0
  sty exportdst+0
  .if <::textfilestart <> 0
    ldy #<textfilestart
  .endif

  ldx #NUM_SOUNDS-1
  tidyloop:
    jsr update_sound_length
    txa
    pha
    jsr correct_triangle_timbre
    pla
    tax
    dex
    bpl tidyloop

  inx
  exportloop:
    stx sound_num
    txa
    asl a
    asl a
    tax
    lda pently_sfx_table+3,x
    beq absent_sound
      jsr export_write_sound
    absent_sound:
    ldx sound_num
    inx
    cpx #NUM_SOUNDS
    bcc exportloop
  rts
.endproc