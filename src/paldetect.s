;
; NES TV system detection code
;
; Copyright 2011 Damian Yerrick
; 
; Permission is hereby granted, free of charge, to any person
; obtaining a copy of this software and associated documentation
; files (the "Software"), to deal in the Software without
; restriction, including without limitation the rights to use, copy,
; modify, merge, publish, distribute, sublicense, and/or sell copies
; of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
; 
; The above copyright notice and this permission notice shall be
; included in all copies or substantial portions of the Software.
; 
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
; THE SOFTWARE.
;

.export getTVSystem
.importzp nmis

.align 32  ; ensure that branches do not cross a page boundary

;;
; Detects which of NTSC, PAL, or Dendy is in use by counting cycles
; between NMIs.
;
; NTSC NES produces 262 scanlines, with 341/3 CPU cycles per line.
; PAL NES produces 312 scanlines, with 341/3.2 CPU cycles per line.
; Its vblank is longer than NTSC, and its CPU is slower.
; Dendy is a Russian famiclone distributed by Steepler that uses the
; PAL signal with a CPU as fast as the NTSC CPU.  Its vblank is as
; long as PAL's, but its NMI occurs toward the end of vblank (line
; 291 instead of 241) so that cycle offsets from NMI remain the same
; as NTSC, keeping Balloon Fight and any game using a CPU cycle-
; counting mapper (e.g. FDS, Konami VRC) working.
;
; nmis is a variable that the NMI handler modifies every frame.
; Make sure your NMI handler finishes within 1500 or so cycles (not
; taking the whole NMI or waiting for sprite 0) while calling this,
; or the result in A will be wrong.
;
; @return A: TV system (0: NTSC, 1: PAL, 2: Dendy; 3: unknown
;         Y: high byte of iterations used (1 iteration = 11 cycles)
;         X: low byte of iterations used
.proc getTVSystem
  ldx #0
  ldy #0
  lda nmis
nmiwait1:
  cmp nmis
  beq nmiwait1
  lda nmis

nmiwait2:
  ; Each iteration takes 11 cycles.
  ; NTSC NES: 29780 cycles or 2707 = $A93 iterations
  ; PAL NES:  33247 cycles or 3022 = $BCE iterations
  ; Dendy:    35464 cycles or 3224 = $C98 iterations
  ; so we can divide by $100 (rounding down), subtract ten,
  ; and end up with 0=ntsc, 1=pal, 2=dendy, 3=unknown
  inx
  bne :+
  iny
:
  cmp nmis
  beq nmiwait2
  tya
  sec
  sbc #10
  cmp #3
  bcc notAbove3
  lda #3
notAbove3:
  rts
.endproc

