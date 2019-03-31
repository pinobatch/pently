
ppu_clear_oam:
  txa
  and #$FC
  tax
  lda #$FF
  @loop:
    sta OAM,x
    inx
    inx
    inx
    inx
    bne @loop
  rts

ppu_screen_on:
  stx PPUSCROLL
  sty PPUSCROLL
  sta PPUCTRL
  lda #BG_ON
  bcc @no_sprites
    lda #BG_ON|OBJ_ON
  @no_sprites:
  sta PPUMASK
  rts
