;
; Pently audio engine
; Beat fraction calculation
;
; Copyright 2009-2017 Damian Yerrick
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

; This can be used to calculate the song position down to a fraction
; of a beat, for use to synchronize a cut scene or a rhythm game.
; CAUTION:  Rhythm games will be a patent minefield until 2019.

.include "pentlyconfig.inc"
.include "pently.inc"
.import mul8  ; from math.s
.if ::PENTLY_USE_PAL_ADJUST
  .importzp tvSystem
.endif

;;
; Returns the Pently playing position as a fraction of a beat
; from 0 to 95.
.proc pently_get_beat_fraction

  ; If rows per beat is disabled, bpmmath will attempt to divide by
  ; zero.  So instead, just return the playing position as 0.
.if ::PENTLY_USE_BPMMATH = 0
  lda #0
.else

.if ::PENTLY_USE_PAL_ADJUST
  ldx tvSystem
  beq isNTSC_1
  ldx #1
isNTSC_1:
.else
  ldx #0
.endif

  ; As an optimization in the music engine, tempoCounter is
  ; actually stored as a negative number: -3606 through -1.
  clc
  lda pently_tempoCounterLo
  adc pently_fpmLo,x
  sta 0
  lda pently_tempoCounterHi
  adc pently_fpmHi,x

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
.endif
  rts
.endproc


.segment "RODATA"

; Reciprocals of frames per second:
; int(round(65536*6/n)) for n in [3606, 3000]
reciprocal_fpm: .byt 109, 131

_pently_get_beat_fraction = pently_get_beat_fraction
