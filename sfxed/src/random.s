;
; crc16 routine
; presumed PD
;
.exportzp CRCLO, CRCHI
.export rand_crc, crc16_update

; This is based on a routine by Greg Cook that implements
; a CRC-16 cycle in constant time, without tables.
; 39 bytes, 66 cycles, AXP clobbered, Y preserved.
; http://www.6502.org/source/integers/crc-more.html
; Setting seed to $FFFF and then taking
; CRC([$01 $02 $03 $04]) should evaluate to $89C3.

.segment "ZEROPAGE"
; Current value of CRC, not necessarily contiguous
CRCLO: .res 1
CRCHI: .res 1

.segment "CODE"

; If using CRC as a PRNG, use this entry point
.proc rand_crc
  lda #$00
.endproc
.proc crc16_update
        EOR CRCHI       ; A contained the data
        STA CRCHI       ; XOR it into high byte
        LSR             ; right shift A 4 bits
        LSR             ; to make top of x^12 term
        LSR             ; ($1...)
        LSR
        TAX             ; save it
        ASL             ; then make top of x^5 term
        EOR CRCLO       ; and XOR that with low byte
        STA CRCLO       ; and save
        TXA             ; restore partial term
        EOR CRCHI       ; and update high byte
        STA CRCHI       ; and save
        ASL             ; left shift three
        ASL             ; the rest of the terms
        ASL             ; have feedback from x^12
        TAX             ; save bottom of x^12
        ASL             ; left shift two more
        ASL             ; watch the carry flag
        EOR CRCHI       ; bottom of x^5 ($..2.)
        STA CRCHI       ; save high byte
        TXA             ; fetch temp value
        ROL             ; bottom of x^12, middle of x^5!
        EOR CRCLO       ; finally update low byte
        LDX CRCHI       ; then swap high and low bytes
        STA CRCHI
        STX CRCLO
        RTS
.endproc

