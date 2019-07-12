;
; Pently audio engine
; NSF player shell
;
; Copyright 2012-2019 Damian Yerrick
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

;
; Include this to emit all NSFE chunks except INFO, DATA, BANK
;


  ; auth chunk contains up to four UTF8-encoded, NUL-terminated
  ; strings in this order: title, artist, year and publisher, ripper
  .dword auth_end-auth_start
  .byt "auth"
auth_start:
  PENTLY_WRITE_NSFE_TITLE
  .byt $00
  PENTLY_WRITE_NSFE_AUTHOR
  .byt $00
  PENTLY_WRITE_NSFE_COPYRIGHT
  .byt $00
auth_end:

  ; tlbl, taut: NUL-terminated song titles and authors
  .dword tlbl_end-tlbl_start
  .byt "tlbl"
tlbl_start:
  PENTLY_WRITE_SONG_TITLES $00
  .if PENTLY_USE_NSF_SOUND_FX
    PENTLY_WRITE_SFX_TITLES $00
  .endif
tlbl_end:

  .dword taut_end-taut_start
  .byt "taut"
taut_start:
  PENTLY_WRITE_SONG_AUTHORS $00
taut_end:

  ; time: 4-byte durations in milliseconds of end of song (if not
  ; looping) or end of second loop
  .dword time_end-time_start
  .byt "time"
time_start:
  PENTLY_WRITE_NSFE_DURATIONS
  .if PENTLY_USE_NSF_SOUND_FX
    PENTLY_WRITE_NSFE_SFX_DURATIONS
  .endif
time_end:

  ; fade: 4-byte durations in milliseconds of fade after end of song.
  ; Convention is -1 (player-specified fade duration) for looping
  ; tracks or 0 (no fade) for tracks that end
  .dword fade_end-fade_start
  .byt "fade"
fade_start:
  PENTLY_WRITE_NSFE_FADES
  .if PENTLY_USE_NSF_SOUND_FX
    PENTLY_WRITE_NSFE_SFX_FADES
  .endif
fade_end:

  ; Mark sound effects as such so that a player can construct "all
  ; songs" and "all sound effects" playlists
  ; TODO once pentlyas gains nsfshelldata output, as the length of
  ; this chunk depends on the score, which is currently .import'd
  ; as opposed to being a constant
  .if PENTLY_USE_NSF_SOUND_FX
    .dword PENTLY_NUM_SOUNDS
    .byt "psfx"
    .repeat PENTLY_NUM_SOUNDS, I
      .byte PENTLY_NUM_SONGS + I
    .endrepeat
  .endif

  ; Show off Dendy compatibility if enabled
  .if PENTLY_USE_PAL_ADJUST
    .dword 2
    .byt "regn"
    .byt $07, $00
  .endif
