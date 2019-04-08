;
; The cel data is of the following form
; (Y, X, attributes, tile+)+, $00
; where:
; Y is excess-128 offset of sprite top down from hotspot (128 is center)
; X is excess-128 offset to right of hotspot (128 is center)
; attributes is a bitfield, where bits 4-0 go to OAM attribute 3
; and 7-5 are the number of tiles to follow minus 1
; 7654 3210
;    | ||++- Palette ID
;    +-++--- Length of strip (0: 1 sprite/8 pixels; 7: 8 sprites/64 pixels)
; tile bits 7-6 are flip, and 5-0 are data
; 7654 3210
; ||++-++++- offset from msprBaseTile
; |+-------- Flip this sprite horizontally
; +--------- Flip this tile vertically
; and "+" means something is repeated 1 or more times
;
; @param hmsprYHi, hmsprYLo 16-bit Y coordinate of hotspot
; @param hmsprXHi, hmsprXLo 16-bit Y coordinate of hotspot
; @param hmsprAttr palette and horizontal flip
; @param X (even) offset into sheet_msprtables, a list of pointers
; to cel lists
; @param A index into the cel list, a list of pointers to
; cel data
; @param hmsprBaseTile index of this sprite sheet in VRAM
; Uses 6 bytes of locals for arguments and 9 bytes for scratch

locals = $0000

enum locals
msprYLo      dsb 1
msprYHi      dsb 1
msprXLo      dsb 1
msprXHi      dsb 1
msprAttr     dsb 1
msprBaseTile dsb 1

mspr_ptr     dsb 2
mspr_xadd    dsb 1  ; 8 for normal; -8 for hflipped
mspr_xxor    dsb 1  ; 0 for normal; $FF for hflipped
mspr_sylo    dsb 1  ; Y position of strip
mspr_sxlo    dsb 1  ; X position within strip
mspr_sxhi    dsb 1  ;   high byte
mspr_swidcd  dsb 1  ; number of sprites left in strip minus 1
mspr_sattr   dsb 1  ; attributes of strip (msprAttr xor strip palette)
ende

draw_metasprite:
  ; Seek to start of frame
  asl a
  tay
  lda sheet_msprtables+1,x
  sta mspr_ptr+1
  lda sheet_msprtables+0,x
  sta mspr_ptr+0
  lda (mspr_ptr),y
  iny
  tax
  lda (mspr_ptr),y
  sta mspr_ptr+1
  stx mspr_ptr+0

  ; Set up variables used for horizontal flipping, and compensate for
  ; offset-128 representation of X coordinates
  lda #<-128
  ldy #0
  ldx #8
  bit msprAttr
  bvc @notflip1
    ; Subtract 7 more if horizontally flipped, taking into account
    ; the width of the sprite
    
    lda #<-135  ; take into account the width 
    dey
    ldx #<-8
  @notflip1:
  sty mspr_xxor
  stx mspr_xadd
  clc
  adc msprXLo
  sta msprXLo
  bcs @nodecxhi
    dec msprXHi
    sec
  @nodecxhi:

  ; Compensate for offset-128 representation of Y coordinates
  ; and the 1-line delay of secondary OAM
  lda msprYLo
  sbc #129
  sta msprYLo
  bcs @nodecyhi
    dec msprYHi
  @nodecyhi:

  ldy #0
  ldx oam_used
  @next_strip:
    ; Get Y position of strip
    lda (mspr_ptr),y
    bne @not_done
      stx oam_used
      rts
    @not_done:
    iny  ; [mspr_ptr]+Y points at X coordinate
    clc
    adc msprYLo
    sta mspr_sylo

    ; Ensure in Y=0 to 256
    lda #0
    adc msprYHi
    bne @is_offscreen_y

    ; Ensure in Y=0 to 238 (change this value for status bars, etc.)
    lda mspr_sylo
    cmp #239
    bcc @not_offscreen_y
    @is_offscreen_y:
      ; Skip this strip entirely
      iny  ; points at palette and length
      lda (mspr_ptr),y  ; bits 4-2
      iny  ; points at first tile ID coordinate
      lsr a
      lsr a
      sty mspr_swidcd
      sec
      and #$07
      adc mspr_swidcd
      tay
      jmp @next_strip
    @not_offscreen_y:

    ; Get starting X position of strip
    lda (mspr_ptr),y
    eor mspr_xxor
    iny  ; points at palette and length
    clc
    adc msprXLo
    sta mspr_sxlo
    lda #0
    adc msprXHi
    sta mspr_sxhi

    ; Get attributes and length
    lda (mspr_ptr),y
    and #$E3
    eor msprAttr
    sta mspr_sattr
    lda (mspr_ptr),y
    lsr a
    lsr a
    and #$07
    sta mspr_swidcd
    iny

    @next_sprite:
      lda mspr_sxhi
      bne @is_offscreen_x
        lda mspr_sylo
        sta OAM,x  ; 0: Y position minus 1
        inx
        lda (mspr_ptr),y
        and #$3F
        clc
        adc msprBaseTile
        sta OAM,x  ; 1: Tile number
        inx
        lda (mspr_ptr),y
        and #$C0
        eor mspr_sattr  ; 2: Strip palette and tile flips
        sta OAM,x
        inx
        lda mspr_sxlo
        sta OAM,x  ; 3: X position
        inx
      @is_offscreen_x:

      iny  ; Advance to next tile
      clc  ; Move to next X coordinate
      lda mspr_sxlo
      adc mspr_xadd
      sta mspr_sxlo
      lda mspr_sxhi
      adc mspr_xxor
      sta mspr_sxhi

      ; Do sprites remain in this strip?
      dec mspr_swidcd
      bpl @next_sprite
    jmp @next_strip

sheet_msprtables:
  dw bell_girl_cels
  dw shadow_cels

bell_girl_cels:
  dw @bell_girl_s
  dw @bell_girl_sw
  dw @bell_girl_w
  dw @bell_girl_nw
  dw @bell_girl_n

@bell_girl_s:
  db 128-28,128- 4,$00,$2B          ; head
  db 128-24,128- 8,$05,$00,$40      ; shoulders
  db 128-16,128-12,$09,$10,$11,$50  ; arms and belt
  db 128- 8,128-12,$09,$20,$21,$60  ; bottom of apron
  db 128- 0,128-12,$09,$29,$2A,$69  ; hem
  db 0

@bell_girl_sw:
  db 128-28,128- 4,$00,$2C          ; head
  db 128-24,128- 8,$05,$01,$02      ; shoulders
  db 128-16,128-12,$09,$12,$13,$14  ; arms and belt
  db 128- 8,128-12,$09,$22,$23,$24  ; bottom of apron
  db 128- 0,128-12,$09,$29,$2A,$69  ; hem
  db 0

@bell_girl_w:
  db 128-28,128- 4,$00,$2D          ; head
  db 128-24,128- 4,$01,$03          ; shoulders
  db 128-16,128-12,$09,$15,$16,$17  ; arms and belt
  db 128- 8,128-12,$09,$25,$26,$27  ; bottom of apron
  db 128- 0,128-12,$09,$29,$2A,$69  ; hem
  db 0

@bell_girl_nw:
  db 128-28,128- 4,$00,$2E          ; head
  db 128-24,128- 8,$05,$04,$05      ; shoulders
  db 128-16,128-12,$09,$18,$19,$1a  ; arms and belt
  db 128- 8,128-12,$09,$28,$26,$27  ; bottom of apron
  db 128- 0,128-12,$09,$29,$2A,$69  ; hem
  db 0

@bell_girl_n:
  db 128-28,128- 4,$00,$2F          ; head
  db 128-24,128- 8,$05,$06,$46      ; shoulders
  db 128-16,128-12,$09,$1B,$1C,$5B  ; arms and belt
  db 128- 8,128-12,$09,$67,$26,$27  ; bottom of apron
  db 128- 0,128-12,$09,$29,$2A,$69  ; hem
  db 0

shadow_cels:
  dw @shadow_28
  dw @shadow_24
  dw @shadow_20
  dw @shadow_16

@shadow_28:
  db 128- 8,128-16,$0C,$09,$0A,$4A,$49
  db 128- 0,128-16,$0C,$89,$8A,$CA,$C9
  db $00

@shadow_24:
  db 128- 8,128-12,$08,$0B,$0C,$4B
  db 128- 0,128-12,$08,$8B,$8C,$CB
  db $00

@shadow_20:
  db 128- 4,128-12,$00,$0D
  db 128- 8,128- 4,$00,$0E
  db 128+ 0,128- 4,$00,$8E
  db 128- 4,128+ 4,$00,$4D
  db $00

@shadow_16:
  db 128- 4,128- 8,$0F,$0F
  db $00
