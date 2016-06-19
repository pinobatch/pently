;
; Pently music engine public API
; Copyright 2009-2015 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

; Configuration ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.ifndef PENTLY_NTSC_ONLY
PENTLY_NTSC_ONLY = 0
.endif
.ifndef PENTLY_USE_ROW_CALLBACK
PENTLY_USE_ROW_CALLBACK = 0
.endif


; Methods ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;
; Initializes the sound channels and stops all sound effects
; and music.
.global pently_init

;;
; Updates sound registers.  Call this once each frame.
; Overwrites: ???
.global pently_update

;;
; Starts a sound effect.
; @param A the sound effect ID
.global pently_start_sound

;;
; Starts a piece of music.
; @param A the music ID
.global pently_start_music

;;
; Stops the music.
.global pently_stop_music

;;
; Resumes the stopped music.
.global pently_resume_music

;;
; Plays note A on channel X (0, 4, 8, 12) with instrument Y.
; Trashes 0-1 and preserves X.
.global pently_play_note

; Fields ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; It's highly discouraged to write to any of these.
; Use the methods above instead.

;;
; Nonzero if music is currently playing
.global pently_music_playing

;;
; The number of rows per beat set by the current music track.
.global pently_rows_per_beat

;;
; The row within a beat, in the range 0 to pently_rows_per_beat
.global pently_row_beat_part

;;
; The fraction of a row until the next row is processed.
; Will range from -3000 to 0 on PAL or -3606 to 0 on NTSC.
.global pently_tempoCounterLo, pently_tempoCounterHi

; Pently requires 5 bytes of temporary zero page scratch space
; that need not be preserved from one call to the next.
pently_zptemp = $0000


