;
; Pently NSF shell
; Copyright 2009-2015 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
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

