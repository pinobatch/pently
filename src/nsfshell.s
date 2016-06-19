;
; Pently audio engine
; NSF player shell
;
; Copyright 2012-2016 Damian Yerrick
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

.import pently_init, pently_start_music, pently_update
.importzp NUM_SONGS
.exportzp psg_sfx_state, tvSystem

.segment "NSFHDR"
  .byt "NESM", $1A, $01  ; signature
  .byt NUM_SONGS
  .byt 1  ; first song to play
  .addr $C000  ; load address (should match link script)
  .addr init_sound_and_music
  .addr pently_update
names_start:
  .byt "argument turned on (inst.)"
  .res names_start+32-*, $00
  .byt "DJ Tepples"
  .res names_start+64-*, $00
  .byt "2015 Damian Yerrick"
  .res names_start+96-*, $00
  .word 16640  ; NTSC frame length (canonically 16666)
  .byt $00,$00,$00,$00,$00,$00,$00,$00  ; bankswitching disabled
  .word 19998  ; PAL frame length  (canonically 20000)
  .byt $02  ; NTSC/PAL dual compatible; NTSC preferred
  .byt $00  ; Famicom mapper sound not used

.segment "ZEROPAGE"
psg_sfx_state: .res 36
tvSystem: .res 1

.segment "CODE"
.proc init_sound_and_music
  stx tvSystem
  pha
  jsr pently_init
  pla
  jmp pently_start_music
.endproc

