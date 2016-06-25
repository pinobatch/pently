;
; Pently audio engine
; Public API
;
; Copyright 2015-2016 Damian Yerrick
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

; Configuration ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; These default values are used if pentlyconfig.inc is not included.

; Enable tvSystem-driven correction for PAL NES and Dendy
.ifndef PENTLY_USE_PAL_ADJUST
PENTLY_USE_PAL_ADJUST = 1
.endif

; Enable row callbacks
.ifndef PENTLY_USE_ROW_CALLBACK
PENTLY_USE_ROW_CALLBACK = 0
.endif

; Enable vibrato (sinusoidal pitch modulation with an LFO of
; period 12 frames)
.ifndef PENTLY_USE_VIBRATO
PENTLY_USE_VIBRATO = 1
.endif

; Enable arpeggio (rapid pitch modulation producing warbly chords of
; period 2 or 3 frames)
.ifndef PENTLY_USE_ARPEGGIO
PENTLY_USE_ARPEGGIO = 1
.endif

; Enable a fifth track that can inject attacks on top of the
; pulse 1, pulse 2, or triangle channel
.ifndef PENTLY_USE_ATTACK_TRACK
PENTLY_USE_ATTACK_TRACK = 1
.endif

; Nonfunctional
.ifndef PENTLY_USE_ATTACK
PENTLY_USE_ATTACK = 1
.endif

; Count rows per beat
.ifndef PENTLY_USE_BPMMATH
PENTLY_USE_BPMMATH = 1
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

;;
; Returns the playing position as a fraction of a beat from 0 to 95.
; (Implemented in bpmmath.s)
.global pently_get_beat_fraction

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

.global pently_fpmLo, pently_fpmHi
