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
  ; look like a text file
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
  lda #';'
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
  lda psg_sound_table+2,x
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
  sta psg_sound_table+2,x
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

.proc export_putbyte_dollar
  pha
  lda #'$'
  jsr export_putchar
  pla
  jmp export_putbyte
.endproc

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
str_tablelabel = * - export_puts_strs
  .byte "psg_sound_table:",0
str_16bitaddr = * - export_puts_strs
  .byte "  .addr ",0
str_labelpart1 = * - export_puts_strs
  .byte "sound",0
str_labelpart2 = * - export_puts_strs
  .byte "data",0
str_bytes = * - export_puts_strs
  .byte "  .byte ",0
.segment "CODE"

;;
; Some versions of my sound engine require bit 7 set in each volume
; byte of a triangle channel sound.
.proc correct_triangle_timbre
fxdata = 0
  asl a
  asl a
  tax
  lda psg_sound_table+2,x
  and #$0C
  cmp #$08
  bne not_triangle
  lda psg_sound_table+0,x
  sta fxdata
  lda psg_sound_table+1,x
  sta fxdata+1
  lda psg_sound_table+3,x
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
; Exports the sound header for sound A.
.proc export_sound_header

  ; Write the name of the sound (.addr sound1data)
  ldy #0
  pha
  ldx #str_16bitaddr
  jsr export_puts
  ldx #str_labelpart1
  jsr export_puts
  pla
  pha
  clc
  adc #'1'
  jsr export_putchar
  ldx #str_labelpart2
  jsr export_puts
  lda #LF
  jsr export_putchar
  
  ; Write the rate, channel, and length
  ldx #str_bytes
  jsr export_puts
  pla
  asl a
  asl a
  tax
  lda psg_sound_table+2,x
  and #$FE  ; muted bit doesn't matter in export
  jsr export_putbyte_dollar
  lda #','
  jsr export_putchar
  lda psg_sound_table+3,x
  jsr export_putbyte_dollar
  jmp export_eol_fix_y
.endproc

;;
; @param A number of bytes on this line (1-16)
; @param $00 source bytes pointer (modified)
.proc export_byte_line
srclo = $00
srchi = $01
bytesleft = $02
  sta bytesleft
  ldy #0
  ldx #str_bytes
  jsr export_puts
  ldx #0
bytesloop:
  lda (srclo,x)
  inc srclo
  bne :+
  inc srchi
:
  jsr export_putbyte_dollar
  dec bytesleft
  beq done
  lda #','
  jsr export_putchar
  jmp bytesloop
done:
.endproc
.proc export_eol_fix_y
  lda #LF
  jsr export_putchar
.endproc
.proc export_fix_y
  tya
  clc
  adc exportdst
  sta exportdst
  bcc :+
  inc exportdst+1
:
  rts
.endproc

.proc export_all_as_text
sound_num = gesture_x
bytes_left = gesture_y
srclo = $00
srchi = $01
  lday #textfilestart
  stay exportdst
  .if <::textfilestart <> 0
    ldy #0
  .endif
  ldx #str_tablelabel
  jsr export_puts
  jsr export_eol_fix_y
  lda #0
  sta sound_num
headerloop:
  ldx sound_num
  jsr update_sound_length
  lda sound_num
  jsr correct_triangle_timbre
  lda sound_num
  jsr export_sound_header
  inc sound_num
  lda sound_num
  cmp #NUM_SOUNDS
  bcc headerloop
  
  lda #0
  sta sound_num
data_soundloop:
  ldy #0
  ldx #str_labelpart1
  jsr export_puts
  lda sound_num
  clc
  adc #'1'
  jsr export_putchar
  ldx #str_labelpart2
  jsr export_puts
  lda #':'
  jsr export_putchar
  jsr export_eol_fix_y
  lda sound_num
  asl a
  asl a
  tax
  lda psg_sound_table+0,x
  sta srclo
  lda psg_sound_table+1,x
  sta srchi
  lda psg_sound_table+3,x
  beq no_bytes
  asl a
lineloop:
  sta bytes_left
  cmp #16
  bcc :+
  lda #16
:
  pha
  jsr export_byte_line
  
  pla
  eor #$FF
  sec
  adc bytes_left
  bne lineloop
no_bytes:
  inc sound_num
  lda sound_num
  cmp #NUM_SOUNDS
  bcc data_soundloop
  rts
.endproc
