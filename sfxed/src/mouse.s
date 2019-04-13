.export read_mouse, mouse_change_sensitivity, detect_mouse
.export read_mouse_ex
.exportzp cur_mbuttons, new_mbuttons, mouse_mask, mouse_port
.import read_pads
.segment "ZEROPAGE"
cur_mbuttons: .res 2
new_mbuttons: .res 2
mouse_mask: .res 1  ; $00: no mouse; $01: 7-pin; $02: 15-pin
mouse_port: .res 1  ; $00: port 1; $01: port 2; >=$80: no mouse

.segment "CODE"
;;
; Assumes that the first 8 bits of the report have already been
; read.
; @param X player number
; @return 1: buttons
.proc read_mouse
  lda #1
  sta 1
  sta 2
  sta 3
:
  lda $4016,x
  and mouse_mask
  cmp #1
  rol 1
  bcc :-
  lda cur_mbuttons,x
  eor #$FF
  and 1
  sta new_mbuttons,x
  lda 1
  sta cur_mbuttons,x
  ; Hyper Click requires a few extra cycles here to let its MCU refill
  ; what appears to be a 16-bit shift register
  jsr knownrts  ; burn a few cycles to let Hyper Click catch up
:
  lda $4016,x
  and mouse_mask
  cmp #1
  rol 2
  bcc :-
:
  lda $4016,x
  and mouse_mask
  cmp #1
  rol 3
  bcc :-
knownrts:
  rts
.endproc

.proc mouse_change_sensitivity
  lda #1
  sta $4016
  lda $4016,x
  lda #0
  sta $4016
  rts
.endproc

;;
; Looks for a Super NES Mouse on one of the 7-pin controller ports
; on the NES or AV Famicom ($4016/$4017 D0) or one of the DA15
; expansion ports on the Famicom ($4016/$4017 D1).  Doesn't attempt
; to detect having mice in both ports.
; Priority: DA15 port 1, NES port 1, DA15 port 2, 7-pin port 2
; Any detected mouse will start in medium sensitivity.  May confuse
; Four Score for mouse if player 3 or 4 is holding Right.
; @return mouse_mask is $01 for 7-pin or $02 for DA15;
; mouse_port is $00 for $4016, $01 for $4017, or >$80 for no mouse.
.proc detect_mouse
tries_left = $06

  ldx #0
portloop:
  stx mouse_port
  jsr mouse_change_sensitivity
  lda #$02  ; try famicom DA15 then try nes 7-pin
  sta mouse_mask
maskloop:
  jsr read_pads
  ldx mouse_port
  jsr read_mouse
  lda 1
  and #$0F
  cmp #$01  ; mouse signature nibble is 1
  beq found

  ; try the next bit on this port
  lsr mouse_mask
  bne maskloop

  ; try the next port
  ldx mouse_port
  bne not_found
  inx
  bne portloop
not_found:
  ; Set mouse_port bit 7 to show that no mouse is connected
  sec
  ror mouse_port
found:
  rts
.endproc

;;
; Reads the mouse in the detected port and mask, converts counts
; to two's complement, and copies current and new mouse buttons
; to port 1.
; @return X: horizontal; Y: vertical
.proc read_mouse_ex
ysmag = 2
xsmag = 3
  ldx mouse_port
  bpl :+
  ldy #0
  ldx #0
  stx cur_mbuttons+0
  stx new_mbuttons+0
  rts
:
  jsr read_mouse
  ldx mouse_port
  beq :+
  lda cur_mbuttons,x
  sta cur_mbuttons+0
  lda new_mbuttons,x
  sta new_mbuttons+0
:  
  ; Convert Y distance from sign+mag to two's complement
  lda ysmag
  bpl :+
  eor #$7F
  sec
  adc #0
:
  tay
  
  ; Convert X distance from sign+mag to two's complement
  lda xsmag
  bpl :+
  eor #$7F
  sec
  adc #0
:
  tax
  rts
.endproc

