;
; Pently audio engine
; Profiler to measure CPU use
;
; Copyright 2018 Damian Yerrick
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

.include "nes.inc"
.include "shell.inc"
.include "pently.inc"

; these values in 12-cycle units were tuned against FCEUX 2.2.3 new PPU
EXPECTED_TIME_NTSC = 1827
EXPECTED_TIME_PAL = 1713

.bss
cycleslo: .res 1
cycleshi: .res 1
cyc_digits: .res 5
cyclespeaklo: .res 1
cyclespeakhi: .res 1
peak_digits: .res 5

.rodata
expected_time_lo:
  .lobytes EXPECTED_TIME_NTSC, EXPECTED_TIME_PAL, EXPECTED_TIME_NTSC
expected_time_hi:
  .hibytes EXPECTED_TIME_NTSC, EXPECTED_TIME_PAL, EXPECTED_TIME_NTSC

.code

; Binary to decimal conversion ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Constants
; BCD_BITS
;   The highest possible number of bits in the BCD output. Should
;   roughly equal 4 * log10(2) * x, where x is the width in bits
;   of the largest binary number to be put in bcdNum.
; bcdTableLo[y], bcdTableHi[y]
;   Contains (1 << y) converted from BCD to binary.
BCD_BITS = 19

; Variables:
; bcdNum (input)
;   Number to be converted to decimal (16-bit little endian).
;   Overwritten.
; bcdResult (output)
;   Decimal digits of result (5-digit little endian).
; X
;   Offset of current digit being worked on.
; Y
;   Offset into bcdTable*.
; curDigit
;   The lower holds the digit being constructed.
;   The upper nibble contains a sentinel value; when a 1 is shifted
;   out, the byte is complete and should be copied to result.
;   (This behavior is called a "ring counter".)
;   Overwritten.
; b
;   Low byte of the result of trial subtraction.
;   Overwritten.
bcdNum = $00
bcdResult = $02
curDigit = $07
b = $02

;;
; Converts a 16-bit number to 5 decimal digits.
;
; For each value of n from 4 to 1, it compares the number to 8*10^n,
; then 4*10^n, then 2*10^n, then 1*10^n, each time subtracting if
; possible. After finishing all the comparisons and subtractions in
; each decimal place value, it writes the digit to the output array
; as a byte value in the range [0, 9].  Finally, it writes the
; remainder to element 0.
;
; Extension to 24-bit and larger numbers is straightforward:
; Add a third bcdTable, increase BCD_BITS, and extend the
; trial subtraction.
;
; Completes within 670 cycles.
.proc bcdConvert
  lda #$80 >> ((BCD_BITS - 1) & 3)
  sta curDigit
  ldx #(BCD_BITS - 1) >> 2
  ldy #BCD_BITS - 5

@loop:
  ; Trial subtract this bit to A:b
  sec
  lda bcdNum
  sbc bcdTableLo,y
  sta b
  lda bcdNum+1
  sbc bcdTableHi,y

  ; If A:b > bcdNum then bcdNum = A:b
  bcc @trial_lower
  sta bcdNum+1
  lda b
  sta bcdNum
@trial_lower:

  ; Copy bit from carry into digit and pick up 
  ; end-of-digit sentinel into carry
  rol curDigit
  dey
  bcc @loop

  ; Copy digit into result
  lda curDigit
  sta bcdResult,x
  lda #$10  ; Empty digit; sentinel at 4 bits
  sta curDigit
  ; If there are digits left, do those
  dex
  bne @loop
  lda bcdNum
  sta bcdResult
  rts
.endproc

.rodata
bcdTableLo:
  .byt <10, <20, <40, <80
  .byt <100, <200, <400, <800
  .byt <1000, <2000, <4000, <8000
  .byt <10000, <20000, <40000

bcdTableHi:
  .byt >10, >20, >40, >80
  .byt >100, >200, >400, >800
  .byt >1000, >2000, >4000, >8000
  .byt >10000, >20000, >40000
  
; Profiling Pently ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.align 16
.proc run_profiler
  ; Wait for vblank time to end (scanline -1), when the sprite 0 and
  ; sprite overflow bits turn off
  lda #$60
  waits0end:
    bit PPUSTATUS
    bvs waits0end

  ; Run the music engine
  jsr pently_update
  bit is_fast_forward
  bpl noff
    jsr pently_update
    jsr pently_update
    jsr pently_update
  noff:

  ; Count 12-cycle units
  lda #$C0
  ldx #0
  ldy #0
  twelveloop:
    inx
    bne :+
      iny
    :
    bit PPUSTATUS
    beq twelveloop
  .assert >* = >twelveloop, error, "twelveloop crosses a page boundary"

  ; Subtract from expected time for this region
  stx cycleslo
  sty cycleshi
  ldy tvSystem
  sec
  lda expected_time_lo,y
  sbc cycleslo
  tax
  lda expected_time_hi,y
  sbc cycleshi
  bcs :+
    lda #0
    tax
  :
  tay

  ; Multiply YX by 12 (or 3 if fast forwarded)
  ; (this'd probably be faster on Z80/LR35902)
  stx cycleslo
  sty cycleshi
  asl cycleslo
  rol cycleshi  ; cycleshi:lo = 2 * cycles
  clc
  txa
  adc cycleslo
  sta cycleslo
  tya
  adc cycleshi  ; A:cycleslo = 3 * cycles

  ; Multiply by 4 unless select was held
  bit is_fast_forward
  bmi nomul4
    asl cycleslo
    rol a
    asl cycleslo
    rol a
  nomul4:
  sta cycleshi  ; A:cycleslo = 12 * cycles

  ; Print cycles
  sta bcdNum+1
  lda cycleslo
  sta bcdNum+0
  jsr bcdConvert
  ldy #4
  jsr bcd_spaceify

  lda cycleslo
  cmp cyclespeaklo
  lda cycleshi
  sbc cyclespeakhi
  bcc notnewpeak
    lda cycleslo
    sta cyclespeaklo
    lda cycleshi
    sta cyclespeakhi
  notnewpeak:
  
  lda cyclespeaklo
  sta bcdNum+0
  lda cyclespeakhi
  sta bcdNum+1
  jsr bcdConvert
  ldy #peak_digits-cyc_digits+4

bcd_spaceify:
  ldx #' '
  stx bcdNum
  ldx #4
  bcd_spaceify_loop:
    lda bcdResult,x
    beq :+
      lda #'0'
      sta bcdNum
      lda bcdResult,x
    :
    ora bcdNum
    sta cyc_digits,y
    dey
    dex
    bne bcd_spaceify_loop
  lda #'0'
  ora bcdResult+0
  sta cyc_digits,y
  
waste12:
  rts
.endproc
