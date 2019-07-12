;
; Pently audio engine
; Sequence data macro definitions
;
; Copyright 2010-2019 Damian Yerrick
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

.ifndef PENTLYSEQ_INC
PENTLYSEQ_INC = 1
.include "pentlyconfig.inc"

.global pently_sfx_table, pently_drums
.global pently_instruments, pently_patterns, pently_songs
.globalzp PENTLY_NUM_SONGS

; Sound effect/drum definitions
.macro sfxdef name, baseaddr, length, period, channel
.exportzp name
.assert * - pently_sfx_table < 256, error, "too many sound effects"
name = <((* - pently_sfx_table) / 4)
  .addr baseaddr
  .byt (channel<<2)|((period - 1)<<4)
  .byt length
.endmacro

; each entry in sound effect frames is four nibbles, big endian:
; FEDC BA98 7654 3210
; ||   |||| |||| ||||
; ||   |||| ++++-++++- pitch in semitones
; ||   ++++----------- volume (0=silent)
; ++------------------ duty (0=1/8, 1=1/4, 2=1/2); triangle must use 2
; "pitch" in sound effects is offset from low A
; for noise:
; FEDC BA98 7654 3210
;      |||| |    ||||
;      |||| |    ++++- noise period class (3=high, F=low)
;      |||| +--------- noise waveform (0=hiss, 1=buzz)
;      ++++----------- volume (0=silent)
.macro sfxframe duty, volume, pitch
  .byte ((duty)<<6|(volume))
  .byte (pitch)
.endmacro

; When using the ASM6 translation of this macro pack, all arguments
; are required, even those optional in ca65.  This is because ASM6
; lacks variadic macros.
; https://forums.nesdev.com/viewtopic.php?f=2&t=18610

; sfx2 is optional in ca65
.macro drumdef name, sfx1, sfx2
name = <(* - pently_drums) * 4
  .byte sfx1
  .ifnblank sfx2
    .byte sfx2
  .else
    .byte $80
  .endif
.endmacro

; Instrument definitions
; decayrate and later are optional in ca65
.macro instdef name, duty, volume, decayrate, earlycut, attackptr, attacklen
name = <(* - pently_instruments) / 5
  .scope
    .byte (((duty) << 6) | (volume))
    .ifnblank decayrate
      .byte decayrate
    .else
      .byte 0
    .endif

    .ifnblank earlycut
      .if (earlycut)
        earlycutbits = $80
      .else
        earlycutbits = $00
      .endif
    .else
      earlycutbits = $00
    .endif
    .ifnblank attacklen
      .byte earlycutbits|(attacklen)
      .addr attackptr
    .else
      .byte earlycutbits
      .addr 0
    .endif
  .endscope
.endmacro

; Song definition
.macro songdef name, conductor_addr
  .assert * - pently_songs < 128, error, "too many songs"
name = <((* - pently_songs) / 2)
  .addr (conductor_addr)
  PENTLY_NUM_SONGS_SO_FAR .set name + 1
.endmacro

; Pattern definition
.macro patdef name, pattern_addr
name = (* - pently_patterns) / 2
  .addr (pattern_addr)
.endmacro

; Conductor

PENTLY_CON_PLAYPAT = $00   ; next: pattern, transpose (ignored if drums), instrument (ignored if drums)
PENTLY_CON_WAITROWS = $20  ; next: number of rows to wait minus 1
PENTLY_CON_FINE = $21      ; stop music now
PENTLY_CON_SEGNO = $22     ; set loop point
PENTLY_CON_DALSEGNO = $23  ; jump to loop point. if no point was set, jump to start of song.
PENTLY_CON_ATTACK_SQ1 = $24
PENTLY_CON_ATTACK_SQ2 = $25
PENTLY_CON_ATTACK_TRI = $26
PENTLY_CON_NOTEON = $28
PENTLY_CON_SETTEMPO = $30  ; low bits: bits 10-8 of tempo in rows/min; next: bits 7-0 of tempo
PENTLY_CON_SETBEAT = $38  ; low bits: duration type (D_something) corresponding to one beat

; Conductor macros
.macro playPatSq1 patid, transpose, instrument
  .byt PENTLY_CON_PLAYPAT|0, patid, transpose, instrument
.endmacro
.macro playPatSq2 patid, transpose, instrument
  .byt PENTLY_CON_PLAYPAT|1, patid, transpose, instrument
.endmacro
.macro playPatTri patid, transpose, instrument
  .byt PENTLY_CON_PLAYPAT|2, patid, transpose, instrument
.endmacro
.macro playPatNoise patid, transpose, instrument
  .byt PENTLY_CON_PLAYPAT|3, patid, 0, 0
.endmacro
.macro playPatAttack patid, transpose, instrument
  .byt PENTLY_CON_PLAYPAT|4, patid, transpose, instrument
.endmacro
.macro stopPatSq1
  .byt PENTLY_CON_PLAYPAT|0, 255, 0, 0
.endmacro
.macro stopPatSq2
  .byt PENTLY_CON_PLAYPAT|1, 255, 0, 0
.endmacro
.macro stopPatTri
  .byt PENTLY_CON_PLAYPAT|2, 255, 0, 0
.endmacro
.macro stopPatNoise
  .byt PENTLY_CON_PLAYPAT|3, 255, 0, 0
.endmacro
.macro stopPatAttack
  .byt PENTLY_CON_PLAYPAT|4, 255, 0, 0
.endmacro
.macro waitRows n
  .byt PENTLY_CON_WAITROWS, (n)-1
.endmacro
.macro fine
  .byt PENTLY_CON_FINE
.endmacro
.macro segno
  .byt PENTLY_CON_SEGNO
.endmacro
.macro dalSegno
  .byt PENTLY_CON_DALSEGNO
.endmacro
.macro setTempo rowsPerMin
  .scope
  irpm = rowsPerMin
    .byt PENTLY_CON_SETTEMPO|>irpm, <irpm
  .endscope
.endmacro
.macro setBeatDuration durCode
  .byt PENTLY_CON_SETBEAT|(durCode)
.endmacro
.macro attackOnSq1
  .byt PENTLY_CON_ATTACK_SQ1
.endmacro
.macro attackOnSq2
  .byt PENTLY_CON_ATTACK_SQ2
.endmacro
.macro attackOnTri
  .byt PENTLY_CON_ATTACK_TRI
.endmacro
.macro noteOnSq1 notenum, instrument
  .byt PENTLY_CON_NOTEON|0, notenum, instrument
.endmacro
.macro noteOnSq2 notenum, instrument
  .byt PENTLY_CON_NOTEON|1, notenum, instrument
.endmacro
.macro noteOnTri notenum, instrument
  .byt PENTLY_CON_NOTEON|2, notenum, instrument
.endmacro
.macro noteOnNoise notenum, instrument
  .byt PENTLY_CON_NOTEON|3, notenum, instrument
.endmacro


; Pattern note/rest commands
PENTLY_N_C  =  0*8
PENTLY_N_CS =  1*8
PENTLY_N_D  =  2*8
PENTLY_N_DS =  3*8
PENTLY_N_E  =  4*8
PENTLY_N_F  =  5*8
PENTLY_N_FS =  6*8
PENTLY_N_G  =  7*8
PENTLY_N_GS =  8*8
PENTLY_N_A  =  9*8
PENTLY_N_AS = 10*8
PENTLY_N_B  = 11*8
PENTLY_N_DB = PENTLY_N_CS
PENTLY_N_EB = PENTLY_N_DS
PENTLY_N_GB = PENTLY_N_FS
PENTLY_N_AB = PENTLY_N_GS
PENTLY_N_BB = PENTLY_N_AS
PENTLY_N_CH  = PENTLY_N_C  + 12*8
PENTLY_N_CSH = PENTLY_N_CS + 12*8
PENTLY_N_DBH = PENTLY_N_DB + 12*8
PENTLY_N_DH  = PENTLY_N_D  + 12*8
PENTLY_N_DSH = PENTLY_N_DS + 12*8
PENTLY_N_EBH = PENTLY_N_EB + 12*8
PENTLY_N_EH  = PENTLY_N_E  + 12*8
PENTLY_N_FH  = PENTLY_N_F  + 12*8
PENTLY_N_FSH = PENTLY_N_FS + 12*8
PENTLY_N_GBH = PENTLY_N_GB + 12*8
PENTLY_N_GH  = PENTLY_N_G  + 12*8
PENTLY_N_GSH = PENTLY_N_GS + 12*8
PENTLY_N_ABH = PENTLY_N_AB + 12*8
PENTLY_N_AH  = PENTLY_N_A  + 12*8
PENTLY_N_ASH = PENTLY_N_AS + 12*8
PENTLY_N_BBH = PENTLY_N_BB + 12*8
PENTLY_N_BH  = PENTLY_N_B  + 12*8
PENTLY_N_CHH = PENTLY_N_CH + 12*8
PENTLY_N_TIE = 25*8
PENTLY_REST  = 26*8

; pattern effects
PENTLY_INSTRUMENT = $D8
PENTLY_ARPEGGIO = $D9
PENTLY_LEGATO_OFF = $DA
PENTLY_LEGATO_ON = $DB
PENTLY_TRANSPOSE = $DC
PENTLY_GRACE = $DD
PENTLY_VIBRATO = $DE
PENTLY_CHVOLUME = $DF
PENTLY_BEND = $E0
PENTLY_RESERVEDFX1 = $E1
PENTLY_FASTARP = $E2
PENTLY_SLOWARP = $E3
PENTLY_PATEND = $FF

; The default duration is one row (a sixteenth note in the tracker).
; OR the pitch with one of these constants.
PENTLY_D_8  = 1
PENTLY_D_D8 = 2
PENTLY_D_4  = 3
PENTLY_D_D4 = 4
PENTLY_D_2  = 5
PENTLY_D_D2 = 6
PENTLY_D_1  = 7

; Enable shortcuts for prefixed data only on request
.ifndef PENTLY_USE_PREFIXED_DATA
PENTLY_USE_PREFIXED_DATA = 0
.endif
.if PENTLY_USE_PREFIXED_DATA = 0

CON_PLAYPAT    = PENTLY_CON_PLAYPAT
CON_WAITROWS   = PENTLY_CON_WAITROWS
CON_FINE       = PENTLY_CON_FINE
CON_SEGNO      = PENTLY_CON_SEGNO
CON_DALSEGNO   = PENTLY_CON_DALSEGNO
CON_ATTACK_SQ1 = PENTLY_CON_ATTACK_SQ1
CON_ATTACK_SQ2 = PENTLY_CON_ATTACK_SQ2
CON_ATTACK_TRI = PENTLY_CON_ATTACK_TRI
CON_NOTEON     = PENTLY_CON_NOTEON
CON_SETTEMPO   = PENTLY_CON_SETTEMPO
CON_SETBEAT    = PENTLY_CON_SETBEAT
N_C   = PENTLY_N_C
N_CS  = PENTLY_N_CS
N_DB  = PENTLY_N_CS
N_D   = PENTLY_N_D
N_DS  = PENTLY_N_DS
N_EB  = PENTLY_N_DS
N_E   = PENTLY_N_E
N_F   = PENTLY_N_F
N_FS  = PENTLY_N_FS
N_GB  = PENTLY_N_FS
N_G   = PENTLY_N_G
N_GS  = PENTLY_N_GS
N_AB  = PENTLY_N_GS
N_A   = PENTLY_N_A
N_AS  = PENTLY_N_AS
N_BB  = PENTLY_N_AS
N_B   = PENTLY_N_B
N_CH  = PENTLY_N_CH
N_CSH = PENTLY_N_CSH
N_DBH = PENTLY_N_CSH
N_DH  = PENTLY_N_DH
N_DSH = PENTLY_N_DSH
N_EBH = PENTLY_N_DSH
N_EH  = PENTLY_N_EH
N_FH  = PENTLY_N_FH
N_FSH = PENTLY_N_FSH
N_GBH = PENTLY_N_FSH
N_GH  = PENTLY_N_GH
N_GSH = PENTLY_N_GSH
N_ABH = PENTLY_N_GSH
N_AH  = PENTLY_N_AH
N_ASH = PENTLY_N_ASH
N_BBH = PENTLY_N_ASH
N_BH  = PENTLY_N_BH
N_CHH = PENTLY_N_CHH
N_TIE = PENTLY_N_TIE
REST  = PENTLY_REST
D_8  = PENTLY_D_8
D_D8 = PENTLY_D_D8
D_4  = PENTLY_D_4
D_D4 = PENTLY_D_D4
D_2  = PENTLY_D_2
D_D2 = PENTLY_D_D2
D_1  = PENTLY_D_1
INSTRUMENT  = PENTLY_INSTRUMENT
ARPEGGIO    = PENTLY_ARPEGGIO
LEGATO_OFF  = PENTLY_LEGATO_OFF
LEGATO_ON   = PENTLY_LEGATO_ON
TRANSPOSE   = PENTLY_TRANSPOSE
GRACE       = PENTLY_GRACE
VIBRATO     = PENTLY_VIBRATO
CHVOLUME    = PENTLY_CHVOLUME
BEND        = PENTLY_BEND
RESERVEDFX1 = PENTLY_RESERVEDFX1
FASTARP     = PENTLY_FASTARP
SLOWARP     = PENTLY_SLOWARP
PATEND      = PENTLY_PATEND


.endif

.endif
