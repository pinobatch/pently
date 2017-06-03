;
; NES PPU common functions
;
; Copyright 2011 Damian Yerrick
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
.export ppu_clear_nt, ppu_clear_oam, ppu_screen_on

;;
; Clears a nametable to a given tile number and attribute value.
; (Turn off rendering in PPUMASK and set the VRAM address increment
; to 1 in PPUCTRL first.)
; @param A tile number
; @param X base address of nametable ($20, $24, $28, or $2C)
; @param Y attribute value ($00, $55, $AA, or $FF)
.proc ppu_clear_nt

  ; Set base PPU address to XX00
  stx PPUADDR
  ldx #$00
  stx PPUADDR

  ; Clear the 960 spaces of the main part of the nametable,
  ; using a 4 times unrolled loop
  ldx #960/4
loop1:
  .repeat 4
    sta PPUDATA
  .endrepeat
  dex
  bne loop1

  ; Clear the 64 entries of the attribute table
  ldx #64
loop2:
  sty PPUDATA
  dex
  bne loop2
  rts
.endproc

;;
; Moves all sprites starting at address X (e.g, $04, $08, ..., $FC)
; below the visible area.
; X is 0 at the end.
.proc ppu_clear_oam

  ; First round the address down to a multiple of 4 so that it won't
  ; freeze should the address get corrupted.
  txa
  and #%11111100
  tax
  lda #$FF  ; Any Y value from $EF through $FF will work
loop:
  sta OAM,x
  inx
  inx
  inx
  inx
  bne loop
  rts
.endproc

;;
; Sets the scroll position and turns PPU rendering on.
; @param A value for PPUCTRL ($2000) including scroll position
; MSBs; see nes.h
; @param X horizontal scroll position (0-255)
; @param Y vertical scroll position (0-239)
; @param C if true, sprites will be visible
.proc ppu_screen_on
  stx PPUSCROLL
  sty PPUSCROLL
  sta PPUCTRL
  lda #BG_ON
  bcc :+
  lda #BG_ON|OBJ_ON
:
  sta PPUMASK
  rts
.endproc

