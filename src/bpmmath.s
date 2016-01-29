;
; Pently beat fraction calculation
; Copyright 2009-2015 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

;
; This is very immature code, intended for a rhythm game that didn't
; pan out.  Don't rely on it.
;

.include "shell.inc"
.include "pently.inc"

;;
; Returns the Pently playing position as a fraction of a beat
; from 0 to 95.
.proc getCurBeatFraction
  ldx tvSystem
  beq isNTSC_1
  ldx #1
isNTSC_1:

  ; as an optimization in the music engine, tempoCounter is
  ; actually stored as a negative number: -3606 through -1
  clc
  lda pently_tempoCounterLo
  adc fpmLo,x
  sta 0
  lda pently_tempoCounterHi
  adc fpmHi,x

  ; at this point, A:0 = tempoCounter + fpm (which I'll
  ; call ptc for positive tempo counter)
  ; Divide by 16 by shifting bits 4-11 up into A
  .repeat 4
    asl 0
    rol a
  .endrepeat
  
  ldy reciprocal_fpm,x
  ; A = ptc / 16, Y = 65536*6/fpm
  jsr mul8

  ; A:0 = ptc * 4096*6 / fpm, in other words, A = ptc * 96 / fpm
  sta 0
  
  ; now shift rpb to the right in case it's a power of 2
  lda #32
  sta 3
  lda pently_rows_per_beat
rpbloop:
  lsr a
  bcs rpbdone
  lsr 3
  lsr 0
  bpl rpbloop
rpbdone:

  ; The supported values of rpb are 1<<n (simple meter) and
  ; 3<<n (compound meter).  Handle 1<<n quickly.
  bne rpb_not_one
  lda 3
  asl a
  adc 3
  sta 3
  lda 0
  bcc add_whole_rows
rpb_not_one:

  ; Otherwise, rpb is 3<<n, which is slightly slower because we
  ; have to divide by 3 by multiplying by 85/256.
  lda 0
  ldy #$55
  jsr mul8

add_whole_rows:
  ldy pently_row_beat_part
  beq no_add_simple
  clc
loop_add_simple:
  adc 3
  dey
  bne loop_add_simple
no_add_simple:  
  rts
.endproc


.segment "RODATA"

fpmLo: .byt <3606, <3000
fpmHi: .byt >3606, >3000
; Reciprocals of frames per second:
; int(round(65536*6/n)) for n in [3606, 3000]
reciprocal_fpm: .byt 109, 131

