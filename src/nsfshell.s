;
; Pently audio engine
; NSF player shell
;
; Copyright 2012-2017 Damian Yerrick
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

.import pently_init, pently_start_sound, pently_start_music, pently_update
.import __ROM7_START__
.importzp NUM_SONGS, NUM_SOUNDS
.exportzp psg_sfx_state, tvSystem

.include "pentlyconfig.inc"

.segment "NSFHDR"
  .byt "NESM", $1A, $01  ; signature
  .if PENTLY_USE_NSF_SOUND_FX
    .byt NUM_SONGS+NUM_SOUNDS
  .else
    .byt NUM_SONGS
  .endif
  .byt 1  ; first song to play
  .addr __ROM7_START__  ; load address (should match link script)
  .addr init_sound_and_music
  .addr pently_update
names_start:
  .byt "Pently demo"
  .res names_start+32-*, $00
  .byt "DJ Tepples"
  .res names_start+64-*, $00
  .byt "2017 Damian Yerrick"
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
  .if ::PENTLY_USE_NSF_SOUND_FX
    cmp #NUM_SONGS
    bcc is_music
      sbc #NUM_SONGS
      jmp pently_start_sound
    is_music:
  .endif
  jmp pently_start_music
.endproc

