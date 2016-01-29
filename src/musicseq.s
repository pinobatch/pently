;
; Music sequence data for Pently demo
; Copyright 2009-2015 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
; Translation: Go ahead and make your ReMixes, but credit me.

.include "pentlyseq.inc"
.segment "RODATA"

; Sound effects and drum kits ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

pently_sfx_table:
  sfxdef SFX_KICK,      kick_snd,       9, 1, 3
  sfxdef SFX_SNARE,     snare_snd,      9, 1, 3
  sfxdef SFX_HIHAT,     hihat_snd,      4, 1, 3
  sfxdef SFX_OPENHAT,   openhat_snd,   15, 1, 3
  sfxdef SFX_TRIKICK,   trikick_snd,    5, 1, 2
  sfxdef SFX_TRISNARE,  trisnare_snd,   4, 1, 2
  sfxdef SFX_SNAREHAT,  snarehat_snd,  15, 1, 3

kick_snd:
  .dbyt $0C05,$0A0F,$080F,$060F,$040F,$030F,$020F,$010F,$010F
snare_snd:
  .dbyt $0C0B,$0A05,$0805,$0605,$0405,$0305,$0205,$0105,$0105
hihat_snd:
  .dbyt $0403,$0283,$0203,$0183
openhat_snd:
  .dbyt $0603,$0583,$0403,$0483,$0303,$0383,$0203,$0383,$0203,$0283
  .dbyt $0103,$0183,$0103,$0183,$0103
snarehat_snd:
  .dbyt $0C0B,$0A05,$0805,$0483,$0303,$0383,$0203,$0383,$0203,$0283
  .dbyt $0103,$0183,$0103,$0183,$0103

trikick_snd:
  .dbyt $8F1F,$8F1B,$8F18,$8215,$8213
trisnare_snd:
  .dbyt $8F25,$8F23,$8222,$8221

pently_drums:
  drumdef KICK,   SFX_KICK
  drumdef SNARE,  SFX_SNARE
  drumdef CLHAT,  SFX_HIHAT
  drumdef OHAT,   SFX_OPENHAT
  drumdef TKICK,  SFX_KICK, SFX_TRIKICK
  drumdef TSNARE, SFX_SNARE, SFX_TRISNARE
  drumdef TSOHAT, SFX_SNAREHAT, SFX_TRISNARE

; Pitched instruments ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

pently_instruments:
  instdef I_BASS,       2, 8
  instdef I_1FPOP,      2, 0, 0, 0, oneframe_attack, 1
  instdef I_BANJO,      0, 2, 1, 0, banjo_attack, 8
  instdef I_LATEBANJO,  0, 2, 1, 0, latebanjo_attack, 9
  instdef I_TUB,        2, 4, 2, 0, tub_attack, 6
  instdef I_FEAT_VDUTY, 0, 3, 1, 0, feat_vduty_attack, 12
  instdef I_FEAT_POWER, 0, 8
  instdef I_BF98_FLUTE, 2, 5, 0, 0, bf98_wind_attack, 7
  instdef I_BF98_FLUTE2,2, 4, 0, 0, bf98_wind_attack, 7
  instdef I_BF98_OSTI,  0, 5, 0, 1, bf98_osti_attack, 4
  instdef I_ORCHHIT,    0, 0, 0, 0, bf98_orchhit_attack, 24
  instdef I_CRASHCYMBAL,0, 7, 2
  instdef I_2ND_FIDDLE, 1, 4, 0, 1, second_fiddle_attack, 5

oneframe_attack:
  .dbyt $8E00

latebanjo_attack:
  .dbyt $0000
  ; overlaps banjo_attack, delaying it by 1 frame
banjo_attack:
  .dbyt $0C00,$0800,$0600,$0500,$0400,$0400,$0300,$0300
tub_attack:
  .dbyt $4C06,$4A04,$8802,$8701,$8600,$8500

feat_vduty_attack:
  .dbyt $8800,$8800,$8700,$8700,$8600,$8600,$4500,$4500
  .dbyt $4500,$4400,$4400,$4400

bf98_wind_attack:
  .dbyt $8400,$8600,$8700,$8600,$8500,$8500,$8500
bf98_osti_attack:
  .dbyt $0300,$0600,$0700,$0600
bf98_orchhit_attack:
  .repeat 8, I
  .dbyt $480C-(I<<8),$4800-(I<<8),$48F4-(I<<8)
  .endrepeat

second_fiddle_attack:
  .dbyt $4300,$4500,$4600,$4500,$4500


; Song pointers ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

pently_songs:
  songdef SONG_CANON, canon_conductor
  songdef SONG_BF98, bf98_conductor
  songdef SONG_FEATURES, allfeatures_conductor
  songdef SONG_LBJ, lbj_conductor
  songdef SONG_ATTACKTEST, attacktest_conductor

NUM_SONGS = NUM_SONGS_SO_FAR

pently_patterns:
  patdef AT_BASS,         attacktest_bass
  patdef AT_ATK,          attacktest_attack
  patdef AT_DRUMS,        attacktest_drums
  patdef LBJ_LEAD1,       lbj_lead1
  patdef LBJ_LEAD1END,    lbj_lead1end
  patdef LBJ_LEAD2,       lbj_lead2
  patdef LBJ_LEAD2END,    lbj_lead2end
  patdef LBJ_INTROG,      lbj_introg
  patdef LBJ_BASS,        lbj_bass
  patdef FEAT_DRUMS,      allfeatures_drums
  patdef FEAT_DRUMFILL,   allfeatures_drumfill
  patdef FEAT_BASS,       allfeatures_bass
  patdef FEAT_CHORDS,     allfeatures_chords
  patdef FEAT_BETWEEN,    allfeatures_between
  patdef BF98_MELA,       bf98_melA
  patdef BF98_MELB1,      bf98_melB1
  patdef BF98_MELB2,      bf98_melB2
  patdef BF98_THIRDSA,    bf98_thirdsA
  patdef BF98_COUNTERB1,  bf98_counterB1
  patdef BF98_COUNTERB2,  bf98_counterB2
  patdef BF98_BASSA,      bf98_bassA
  patdef BF98_BASSB1,     bf98_bassB1
  patdef BF98_BASSB2,     bf98_bassB2
  patdef BF98_DRUM,       bf98_drum_main
  patdef BF98_DRUMRESUME, bf98_drum_resumefill
  patdef BF98_DRUMTRIPLET,bf98_drum_tripletfill
  patdef BF98_BREAKFILL,  bf98_drum_break_fill
  patdef BF98_DRUMBREAK,  bf98_drum_break
  patdef BF98_OSTI_CH1,   bf98_osti_ch1
  patdef BF98_OSTI_CH2,   bf98_osti_ch2
  patdef BF98_ORCHHITS,   bf98_orchhits
  patdef CANON_BASS,      canon_bass
  patdef CANON_MEL,       canon_mel

;________________________________________
; Attack channel demo
; by Damian Yerrick
; If anything the bass line is inspired by "The Big One", the theme
; from "The People's Court".

attacktest_conductor:
  setTempo 3606/7
  setBeatDuration D_D4
  attackOnTri
  playPatNoise   AT_DRUMS
  playPatTri     AT_BASS,   3+12, I_BASS
  playPatAttack  AT_ATK,    3+48, I_1FPOP
  waitRows 72
  playPatAttack  AT_ATK,    1+48, I_1FPOP
  waitRows 24
  dalSegno

attacktest_attack:
  .byte N_F|D_8, N_AB, N_CH|D_8, N_AB, N_CH|D_8, N_EBH, N_CH|D_8, N_EBH
  .byte N_GH|D_8, N_EBH, N_CH|D_8, N_EBH, N_CH|D_8, N_AB, N_CH|D_8, N_AB
  .byte PATEND

attacktest_bass:
  .byte N_EB|D_4,REST, N_F|D_8, REST|D_2, REST|D_D4, N_C|D_8, REST
  .byte N_EB|D_4,REST, N_F|D_8, REST|D_8, N_AB|D_2, REST|D_4, N_C|D_8, REST
  .byte N_EB|D_4,REST, N_F|D_8, REST|D_2, REST|D_D4, N_C|D_8, REST
  .byte N_EB|D_4,REST, N_F|D_8, REST|D_8, N_GB|D_2, REST|D_4, N_C|D_8, REST
  .byte PATEND

attacktest_drums:
  .byte KICK|D_D8, CLHAT|D_D8, SNARE|D_D8, CLHAT|D_8, KICK
  .byte CLHAT|D_D8, KICK|D_D8, SNARE|D_D8, CLHAT|D_D8
  .byte KICK|D_D8, CLHAT|D_D8, SNARE|D_D8, CLHAT|D_8, SNARE
  .byte CLHAT|D_D8, KICK|D_D8, SNARE|D_D8, OHAT|D_D8
  .byte KICK|D_D8, CLHAT|D_D8, SNARE|D_D8, CLHAT|D_8, KICK
  .byte CLHAT|D_D8, KICK|D_D8, SNARE|D_D8, CLHAT|D_D8
  .byte KICK|D_D8, CLHAT|D_D8, SNARE|D_D8, CLHAT|D_8, SNARE
  .byte CLHAT|D_D8, KICK|D_D8, SNARE|D_8, OHAT, SNARE, SNARE, SNARE
  .byte PATEND

;_____________________
; Music from stairs video
; If anything this is a sound-alike for "Little Brown Jug"

lbj_conductor:
  setTempo 300
  setBeatDuration D_D8

  playPatSq2 LBJ_LEAD1,     3+12, I_BANJO
  waitRows 4*12+3
  playPatSq1 LBJ_INTROG,    3+24, I_LATEBANJO
  waitRows 3*12-3
  playPatSq2 LBJ_LEAD1END,  3+12, I_BANJO
  waitRows 6
  stopPatSq1  ; (brief silence)
  waitRows 6

  segno
  playPatSq2 LBJ_BASS,      3, I_TUB
  playPatSq1 LBJ_LEAD1,     3+12, I_BANJO
  waitRows 7*12
  playPatSq1 LBJ_LEAD1END,  3+12, I_BANJO
  waitRows 6
  playPatSq2 LBJ_INTROG,    3, I_TUB
  waitRows 6

  ; Now the same thing with a roll replacing the melody
  playPatSq2 LBJ_BASS,      3, I_TUB
  playPatSq1 LBJ_LEAD2,     3+12, I_BANJO
  waitRows 7*12
  playPatSq1 LBJ_LEAD2END,  3+12, I_BANJO
  waitRows 6
  playPatSq2 LBJ_INTROG,    3, I_TUB
  waitRows 6
  dalSegno

lbj_lead1:
  .byte N_G|D_D8, N_B|D_D8, N_B|D_D8, REST|D_8, N_G
  .byte N_E|D_D8, N_G|D_D8, N_G|D_D8, REST|D_D8
  .byte N_A|D_D8, N_B|D_8, N_CH, N_DH|D_8, N_CH, N_A|D_D8
  .byte N_B|D_D8, N_DH|D_D8, N_DH|D_D8, REST|D_D8
  .byte PATEND
lbj_lead1end:
  .byte N_B|D_D8, N_A|D_D8, N_G|D_D8, REST|D_D8
  .byte PATEND
lbj_lead2:
  .byte N_G|D_8, N_B, N_D|D_8, N_DH, N_G|D_8, N_B, N_D|D_8, N_DH
  .byte N_G|D_8, N_CH, N_E|D_8, N_EH, N_G|D_8, N_CH, N_E|D_8, N_EH
  .byte N_A|D_8, N_CH, N_D|D_8, N_DH, N_A|D_8, N_CH, N_D|D_8, N_DH
  .byte N_B|D_8, N_DH, N_G|D_8, N_DH, N_B|D_8, N_DH, N_G|D_8, N_DH
  .byte PATEND
lbj_lead2end:
  .byte N_B|D_8, N_DH, N_A|D_8, N_DH, N_G|D_D8, REST|D_D8
  .byte PATEND
lbj_introg:
  .byte N_G|D_D8, REST|D_D8
  .byte PATEND
lbj_bass:
  .byte INSTRUMENT, I_TUB, N_G|D_D8, TRANSPOSE, 12
  .byte INSTRUMENT, I_LATEBANJO, N_GH|D_D8, TRANSPOSE, <-12
  .byte INSTRUMENT, I_TUB, N_D|D_D8, TRANSPOSE, 12
  .byte INSTRUMENT, I_LATEBANJO, N_GH|D_D8, TRANSPOSE, <-12
  .byte INSTRUMENT, I_TUB, N_C|D_D8, TRANSPOSE, 12
  .byte INSTRUMENT, I_LATEBANJO, N_GH|D_D8, TRANSPOSE, <-12
  .byte INSTRUMENT, I_TUB, N_G|D_D8, TRANSPOSE, 12
  .byte INSTRUMENT, I_LATEBANJO, N_GH|D_D8, TRANSPOSE, <-12
  .byte INSTRUMENT, I_TUB, N_D|D_D8, TRANSPOSE, 12
  .byte INSTRUMENT, I_LATEBANJO, N_GH|D_D8, TRANSPOSE, <-12
  .byte INSTRUMENT, I_TUB, N_A|D_D8, TRANSPOSE, 12
  .byte INSTRUMENT, I_LATEBANJO, N_GH|D_D8, TRANSPOSE, <-12
  .byte INSTRUMENT, I_TUB, N_G|D_D8, TRANSPOSE, 12
  .byte INSTRUMENT, I_LATEBANJO, N_GH|D_D8, TRANSPOSE, <-12
  .byte INSTRUMENT, I_TUB, N_D|D_D8, TRANSPOSE, 12
  .byte INSTRUMENT, I_LATEBANJO, N_GH|D_D8, TRANSPOSE, <-12
  .byte PATEND

;______________________
; All features
; by Damian Yerrick
; Very simple demo of what is easier to do in Pently than in FT

allfeatures_conductor:
  setTempo 720
  setBeatDuration D_D4
  playPatSq1   FEAT_BETWEEN, 6,    I_FEAT_POWER
  playPatSq2   FEAT_BETWEEN, 1+12, I_FEAT_POWER
  playPatTri   FEAT_BETWEEN, 6+24, I_BASS
  stopPatNoise
  waitRows 12
  stopPatSq1
  stopPatSq2
  stopPatTri
  playPatNoise FEAT_DRUMS
  waitRows 36
  playPatNoise FEAT_DRUMFILL
  waitRows 12
  playPatNoise FEAT_DRUMS
  playPatSq1   FEAT_CHORDS,  3+24, I_FEAT_VDUTY
  playPatTri   FEAT_BASS,    1+24, I_BASS
  waitRows 48+36
  playPatNoise FEAT_DRUMFILL
  waitRows 12
  dalSegno

allfeatures_drums:
  .byte TKICK|D_8, CLHAT|D_8, CLHAT|D_8, TSNARE|D_8, CLHAT|D_8, OHAT|D_8
  .byte TKICK|D_8, CLHAT|D_8, CLHAT|D_8, TSNARE|D_8, CLHAT|D_8, TKICK|D_8
  .byte PATEND
allfeatures_drumfill:
  .byte TKICK|D_8, CLHAT|D_8, TKICK|D_8, TSNARE|D_8, TSNARE|D_8, TSNARE|D_8
  .byte PATEND
allfeatures_bass:
  .byte N_F|D_4, REST|D_8, N_AB|D_D4, REST|D_4, N_AB|D_8, N_F|D_4, N_AB|D_8
  .byte N_BB|D_4, N_EB|D_4, REST|D_8, N_EB|D_4, REST|D_4, N_C|D_4, REST|D_8
  .byte PATEND
allfeatures_chords:
  .byte REST|D_D4, ARPEGGIO, $37, N_EB|D_1, REST|D_8
  .byte REST|D_D4, ARPEGGIO, $47, N_DB|D_1, ARPEGGIO, 0, REST|D_8
  .byte PATEND
allfeatures_between:
  .byte N_C|D_D4, REST|D_D4, PATEND

;________________________
; happy flappy crappy
; by Damian Yerrick
; sort of inspired by Balloon Trip

bf98_conductor:
  setTempo 400
  setBeatDuration D_D8
  playPatSq2 BF98_ORCHHITS, 7+24, I_ORCHHIT
  waitRows 36
  playPatTri BF98_BASSA, 3+12, I_BASS
  playPatNoise BF98_DRUM
  noteOnNoise $05, I_CRASHCYMBAL
  waitRows 36
  segno
  ; a section
  playPatNoise BF98_DRUM
  playPatSq2 BF98_MELA, 3+24, I_BF98_FLUTE
  waitRows 36
  playPatSq1 BF98_THIRDSA, 3+24, I_BF98_FLUTE2
  waitRows 36
  playPatSq2 BF98_OSTI_CH2, 7+24, I_ORCHHIT
  playPatSq1 BF98_OSTI_CH1, 7+24, I_BF98_OSTI
  waitRows 72
  playPatSq2 BF98_MELA, 3+24, I_BF98_FLUTE
  playPatSq1 BF98_THIRDSA, 3+24, I_BF98_FLUTE2
  waitRows 72
  ; the b section
  playPatSq2 BF98_MELB1, 3+24, I_BF98_FLUTE
  playPatSq1 BF98_COUNTERB1, 3+24, I_BF98_FLUTE2
  playPatTri BF98_BASSB1, 3+12, I_BASS
  waitRows 72-7
  playPatNoise BF98_DRUMTRIPLET, 0, 0
  waitRows 7
  playPatNoise BF98_DRUM
  waitRows 18
  playPatSq2 BF98_MELB2, 3+24, I_BF98_FLUTE
  playPatSq1 BF98_COUNTERB2, 3+24, I_BF98_FLUTE2
  playPatTri BF98_BASSB2, 3+12, I_BASS
  waitRows 45
  stopPatSq1
  stopPatSq2
  playPatNoise BF98_BREAKFILL, 0, 0
  waitRows 9
  ; the break
  playPatNoise BF98_DRUM
  playPatTri BF98_BASSA, 3+12, I_BF98_FLUTE
  waitRows 36
  playPatNoise BF98_DRUMBREAK, 0, 0
  waitRows 36-9
  playPatNoise BF98_DRUMRESUME, 0, 0
  waitRows 9
  dalSegno
  
bf98_melA:
  .byte REST|D_D8, N_GS|D_8, REST, N_B|D_8, REST
  .byte N_A|D_8, N_B, N_A|D_8, REST, N_FS|D_8, REST
  .byte N_GS|D_8, N_A, N_B|D_8, REST, N_EH|D_8, REST
  .byte GRACE, 5, N_DH, N_EH|D_D8, N_DH|D_D8, N_TIE|D_8, REST
  .byte PATEND
bf98_melB1:
  .byte REST|D_8, N_A, N_CSH|D_8, N_EH, N_CSH|D_8, REST
  .byte N_DSH|D_8, N_CSH, N_B|D_8, REST, N_B|D_8, N_A
  .byte N_GS|D_8, REST, N_B|D_8, REST, N_A|D_8, N_CSH
  .byte N_B|D_D8, REST|D_D8, N_EH|D_8, N_DSH
  .byte N_CSH|D_8, N_B, N_A|D_8, N_B, N_CSH|D_8, REST
  .byte N_DSH|D_8, REST, N_B|D_8, REST, N_A|D_8, REST
  .byte N_GS|D_8, REST, N_B|D_D8, N_TIE|D_8, REST|D_4, REST|D_D4
  .byte PATEND
bf98_melB2:
  .byte N_G|D_8, REST, N_B|D_8, REST, N_CSH|D_D8
  .byte N_DH|D_D8, REST|D_D8, N_DH|D_8, N_CH
  .byte N_B|D_8, N_CH, N_DH|D_8, REST, N_B|D_8, REST
  .byte N_CSH|D_8, N_B, N_A|D_8, N_B, N_CSH|D_8, N_DSH
  .byte GRACE, 4, N_DSH, N_EH|D_D8, N_DSH|D_D8, N_TIE|D_8, REST
  .byte PATEND

bf98_thirdsA:
  .byte REST|D_D8, N_E|D_8, REST, N_GS|D_8, REST
  .byte N_FS|D_8, N_GS, N_FS|D_8, REST, N_D|D_8, REST
  .byte N_E|D_8, N_FS, N_GS|D_8, REST, N_B|D_8, REST
  .byte N_A|D_2, REST
  .byte PATEND
bf98_counterB1:
  .byte N_CS|D_8, REST, N_E|D_8, REST, N_A|D_8, REST
  .byte N_FS|D_8, REST, N_DS|D_8, REST, N_FS|D_8, REST
  .byte N_E|D_8, REST, N_GS|D_8, REST, N_FS|D_8, REST
  .byte N_GS|D_D8, REST|D_D4
  .byte N_A|D_8, REST, N_E|D_8, REST, N_CS|D_8, REST
  .byte N_DS|D_8, REST, N_FS|D_8, REST, N_DS|D_8, REST
  .byte N_E|D_8, REST, N_GS|D_D8, N_TIE|D_8, REST|D_4, REST|D_D4
  .byte PATEND
bf98_counterB2:
  .byte N_E|D_8, REST, N_G|D_8, REST, N_A|D_D8
  .byte N_FS|D_8, REST, N_D|D_8, REST, N_FS|D_8, REST
  .byte N_D|D_8, REST, N_G|D_8, REST, N_D|D_8, REST
  .byte N_E|D_8, REST, N_CS|D_8, REST, N_E|D_8, REST
  .byte N_FS|D_2, REST
  .byte PATEND

bf98_bassA:
  .byte N_E|D_8, REST, N_GS|D_8, REST, N_B|D_8, N_AS
  .byte N_A|D_8, REST, N_D|D_8, REST, N_FS|D_8, REST
  .byte N_E|D_8, N_GS, N_B|D_8, REST, N_EH|D_8, N_DSH
  .byte N_DH|D_8, REST, N_A|D_8, N_AS|D_8, N_B|D_8
  .byte PATEND
bf98_bassB1:
  .byte N_A|D_8, REST, N_B|D_8, REST, N_CSH|D_8, REST
  .byte N_B|D_8, REST, N_FS|D_8, REST, N_DS|D_8, REST
  .byte N_E|D_8, REST, N_E|D_8, REST, N_B|D_8, REST
  .byte N_EH|D_8, REST, N_E|D_8, N_FS|D_8, N_GS|D_8
  .byte PATEND
bf98_bassB2:
  .byte N_E|D_8, REST, N_E|D_8, REST, N_A|D_8, REST
  .byte N_DH|D_8, REST, N_D|D_8, N_E|D_8, N_FS|D_8
  .byte N_G|D_8, REST, N_B|D_8, REST, N_DH|D_8, N_EH
  .byte N_A|D_8, REST, N_EH|D_8, N_DH, N_CSH|D_8, REST
  .byte N_B|D_8, REST, N_DSH|D_8, REST, N_FS|D_8, REST
  .byte N_B|D_8, REST, REST|D_D4
  .byte PATEND

bf98_drum_main:
  .byte TKICK|D_D8, CLHAT|D_8, TKICK, TSNARE|D_D8
  .byte TKICK|D_D8, CLHAT|D_8, TKICK, TSNARE|D_D8
  .byte TKICK|D_D8, CLHAT|D_8, TKICK, TSNARE|D_D8
bf98_drum_resumefill:
  .byte TKICK|D_8, TSNARE, CLHAT|D_8, TKICK, TSNARE|D_8, TSNARE
  .byte PATEND
bf98_drum_tripletfill:
  .byte CLHAT, TSNARE|D_8, TKICK|D_8, TSNARE|D_8
  .byte PATEND
bf98_drum_break_fill:
  .byte TKICK|D_D8, CLHAT|D_D8, CLHAT|D_D8
  .byte PATEND
bf98_drum_break:
  .byte TKICK|D_D4, CLHAT|D_8, TKICK
  .byte PATEND

bf98_osti_ch2:
  .byte INSTRUMENT, I_ORCHHIT, N_E|D_8
  .byte INSTRUMENT, I_BF98_OSTI, N_GH, N_CHH, N_CHH, N_CHH, N_CHH|D_8, N_GH
  .byte INSTRUMENT, I_ORCHHIT, N_D|D_8
  .byte INSTRUMENT, I_BF98_OSTI, N_FH, N_ASH, N_ASH, N_ASH, N_ASH|D_8, N_FH
  .byte INSTRUMENT, I_ORCHHIT, N_C|D_8
  .byte INSTRUMENT, I_BF98_OSTI, N_EH, N_GH, N_GH, N_GH, N_GH|D_8, N_EH
  .byte INSTRUMENT, I_ORCHHIT, N_F|D_8
  .byte INSTRUMENT, I_BF98_OSTI, N_DH, N_FH, N_FH, N_FH, N_FH|D_8, N_DH
  .byte PATEND
bf98_osti_ch1:
  .byte REST|D_8, N_EH, N_GH, N_GH, N_GH, N_GH|D_8, N_EH
  .byte REST|D_8, N_DH, N_FH, N_FH, N_FH, N_FH|D_8, N_DH
  .byte REST|D_8, N_CH, N_EH, N_EH, N_EH, N_EH|D_8, N_CH
  .byte REST|D_8, N_AS, N_DH, N_DH, N_DH, N_DH|D_8, N_AS
  .byte PATEND
bf98_orchhits:
  .byte N_E|D_D8, N_E|D_8, N_C|D_4
  .byte N_D|D_D8, N_D|D_8, N_F|D_4
  .byte PATEND

;______________________
; Canon in D
; by Johann Pachelbel
; arr by Damian Yerrick

canon_conductor:
  setTempo 450  ; 32nd notes
  setBeatDuration D_2
  playPatTri CANON_BASS, 3+12, I_BASS
  waitRows 2*32
  playPatSq2 CANON_MEL,  3+24, I_BF98_OSTI
  waitRows 2*32
  playPatSq1 CANON_MEL,  3+24, I_2ND_FIDDLE
  waitRows 6*32
  waitRows 8*32
  waitRows 8*32
  waitRows 8*32
  waitRows 8*32
  waitRows 8*32
  waitRows 5*32+8
  setTempo 400
  waitRows 8
  setTempo 350
  waitRows 8
  setTempo 300
  waitRows 8
  setTempo 250
  playPatSq1 CANON_MEL,  3+24, I_2ND_FIDDLE
  waitRows 8
  fine

canon_bass:
  .byte N_DH|D_2, N_A|D_2, N_B|D_2, N_FS|D_2
  .byte N_G|D_2, N_D|D_2, N_G|D_2, N_A|D_2
  ; And everybody say, Yatta!
  .byte PATEND

canon_mel:
  ; 2 lines of code per measure
  ; 3
  .byte N_FSH|D_2, N_EH|D_2
  .byte N_DH|D_2, N_CSH|D_2
  .byte N_B|D_2, N_A|D_2
  .byte N_B|D_2, N_CSH|D_2
  .byte N_DH|D_2, N_CSH|D_2
  .byte N_B|D_2, N_A|D_2
  .byte N_G|D_2, N_FS|D_2
  .byte N_G|D_2, N_E|D_2
  ; 7
  .byte N_D|D_4, N_FS|D_4, N_A|D_4, N_G|D_4
  .byte N_FS|D_4, N_D|D_4, N_FS|D_4, N_E|D_4
  .byte TRANSPOSE, <-12, N_DH|D_4, N_B|D_4, N_DH|D_4, N_AH|D_4
  .byte TRANSPOSE, 12, N_G|D_4, N_B|D_4, N_A|D_4, N_G|D_4
  .byte N_FS|D_4, N_D|D_4, N_E|D_4, N_CSH|D_4
  .byte N_DH|D_4, N_FSH|D_4, N_AH|D_4, N_A|D_4
  .byte N_B|D_4, N_G|D_4, N_A|D_4, N_FS|D_4
  .byte N_D|D_4, N_DH|D_4, N_DH|D_D4, N_CSH|D_8
  ; 11
  .byte N_DH|D_8, N_CSH|D_8, N_DH|D_8, N_D|D_8, N_CS|D_8, N_A|D_8, N_E|D_8, N_FS|D_8
  .byte N_D|D_8, N_DH|D_8, N_CSH|D_8, N_B|D_8, N_CSH|D_8, N_FSH|D_8, N_AH|D_8, N_BH|D_8
  .byte N_GH|D_8, N_FSH|D_8, N_EH|D_8, N_GH|D_8, N_FSH|D_8, N_EH|D_8, N_DH|D_8, N_CSH|D_8
  .byte N_B|D_8, N_A|D_8, N_G|D_8, N_FS|D_8, N_E|D_8, N_G|D_8, N_FS|D_8, N_E|D_8
  .byte N_D|D_8, N_E|D_8, N_FS|D_8, N_G|D_8, N_A|D_8, N_E|D_8, N_A|D_8, N_G|D_8
  .byte N_FS|D_8, N_B|D_8, N_A|D_8, N_G|D_8, N_A|D_8, N_G|D_8, N_FS|D_8, N_E|D_8
  .byte N_D|D_8, TRANSPOSE, <-12, N_B|D_8, TRANSPOSE, 12, N_B|D_8, N_CSH|D_8, N_DH|D_8, N_CSH|D_8, N_B|D_8, N_A|D_8
  .byte N_G|D_8, N_FS|D_8, N_E|D_8, N_B|D_8, N_A|D_8, N_B|D_8, N_A|D_8, N_G|D_8
  ; 15 the calm before the storm
  .byte N_FS|D_4, N_FSH|D_4, N_EH|D_2
  .byte REST|D_4, N_DH|D_4, N_FSH|D_2
  .byte TRANSPOSE, 12, N_B|D_2, N_A|D_2
  .byte N_B|D_2, N_CSH|D_2
  .byte N_DH|D_4, N_D|D_4, N_CS|D_2
  .byte TRANSPOSE, <-12, REST|D_4, N_B|D_4, N_DH|D_2
  .byte N_DH|D_D2, N_DH|D_4
  .byte N_DH|D_4, N_GH|D_4
  .byte N_EH|D_4, N_AH|D_4
  ; 19 this is where it becomes as hellish for the
  ; violinist as it is monotonous for the cellist
  ; because of 32nd notes, the next four measures
  ; have four lines of code per measure
  .byte N_AH|D_8, N_FSH, N_GH, N_AH|D_8, N_FSH, N_GH
  .byte N_AH, N_A, N_B, N_CSH, N_DH, N_EH, N_FSH, N_GH
  .byte N_FSH|D_8, N_DH, N_EH, N_FSH|D_8, N_FS, N_G
  .byte N_A, N_B, N_A, N_G, N_A, N_FS, N_G, N_A
  .byte N_G|D_8, N_B, N_A, N_G|D_8, N_FS, N_E
  .byte N_FS, N_E, N_D, N_E, N_FS, N_G, N_A, N_B
  .byte N_G|D_8, N_B, N_A, N_B|D_8, N_CSH, N_DH
  .byte N_A, N_B, N_CSH, N_DH, N_EH, N_FSH, N_GH, N_AH
  .byte N_FSH|D_8, N_DH, N_EH, N_FSH|D_8, N_EH, N_DH
  .byte N_EH, N_CSH, N_DH, N_EH, N_FSH, N_EH, N_DH, N_CSH
  .byte N_DH|D_8, N_B, N_CSH, N_DH|D_8, N_D, N_E
  .byte N_FS, N_G, N_FS, N_E, N_FS, N_DH, N_CSH, N_DH
  .byte N_B|D_8, N_DH, N_CSH, N_B|D_8, N_A, N_G
  .byte N_A, N_G, N_FS, N_G, N_A, N_B, N_CSH, N_DH
  .byte N_B|D_8, N_DH, N_CSH, N_DH|D_8, N_CSH, N_B
  .byte N_CSH, N_DH, N_EH, N_DH, N_CSH, N_DH, N_B, N_CSH
  ; 23 whew. back to normal
  .byte N_DH|D_4, REST|D_4, N_CSH|D_4, REST|D_4
  .byte N_B|D_4, REST|D_4, N_DH|D_4, REST|D_4
  .byte N_D|D_4, REST|D_4, N_D|D_4, REST|D_4
  .byte N_D|D_4, REST|D_4, N_E|D_4, REST|D_2
  .byte   N_A|D_4, REST|D_4, N_A|D_4
  .byte REST|D_4, N_FS|D_4, REST|D_4, N_A|D_4
  .byte REST|D_4, N_G|D_4, REST|D_4, N_FS|D_4
  .byte REST|D_4, N_G|D_4, REST|D_4, N_EH|D_4
  ; 27
  .byte N_FSH|D_8, N_FS|D_8, N_G|D_8, N_FS|D_8, N_E|D_8, N_EH|D_8, N_FSH|D_8, N_EH|D_8
  .byte N_DH|D_8, N_FS|D_8, N_D|D_8, N_B|D_8, N_A|D_8, TRANSPOSE, <-5, N_D|D_8, N_C|D_8, N_D|D_8
  .byte N_E|D_8, N_EH|D_8, N_FSH|D_8, N_EH|D_8, N_DH|D_8, N_D|D_8, N_C|D_8, N_D|D_8
  .byte N_E|D_8, N_EH|D_8, N_DH|D_8, N_EH|D_8, N_FSH|D_8, N_FS|D_8, N_E|D_8, N_FS|D_8
  .byte N_G|D_8, N_GH|D_8, N_AH|D_8, N_GH|D_8, N_FSH|D_8, N_FS|D_8, N_G|D_8, N_FS|D_8
  .byte N_E|D_8, TRANSPOSE, 5, N_B|D_8, N_A|D_8, N_B|D_8, N_CSH|D_8, N_CS|D_8, N_FS|D_8, N_E|D_8
  .byte N_D|D_8, N_DH|D_8, N_EH|D_8, N_GH|D_8, N_FSH|D_8, N_FS|D_8, N_A|D_8, N_FSH|D_8
  .byte N_DH|D_8, N_GH|D_8, N_FSH|D_8, N_GH|D_8, N_EH|D_8, N_A|D_8, N_G|D_8, N_A|D_8
  ; 31
  .byte N_FS|D_8, N_A|D_8, N_A|D_8, N_A|D_8, N_A|D_8, N_A|D_8, N_A|D_8, N_A|D_8
  .byte N_FS|D_8, N_FS|D_8, N_FS|D_8, N_FS|D_8, N_FS|D_8, N_FS|D_8, N_A|D_8, N_A|D_8
  .byte N_G|D_8, N_G|D_8, N_G|D_8, N_DH|D_8, N_DH|D_8, N_DH|D_8, N_DH|D_8, N_DH|D_8
  .byte N_DH|D_8, N_DH|D_8, N_B|D_8, N_B|D_8, N_A|D_8, N_A|D_8, N_EH|D_8, N_CSH|D_8
  .byte N_A|D_8, N_FSH|D_8, N_FSH|D_8, N_FSH|D_8, N_EH|D_8, N_EH|D_8, N_EH|D_8, N_EH|D_8
  .byte N_DH|D_8, N_DH|D_8, N_DH|D_8, N_DH|D_8, N_AH|D_8, N_AH|D_8, N_AH|D_8, N_AH|D_8
  .byte N_BH|D_8, N_BH|D_8, N_BH|D_8, N_BH|D_8, N_AH|D_8, N_AH|D_8, N_AH|D_8, N_AH|D_8
  .byte N_BH|D_8, N_BH|D_8, N_BH|D_8, N_BH|D_8, TRANSPOSE, 7, N_FSH|D_8, N_FS|D_8, N_FS|D_8, N_FS|D_8
  ; 35
  .byte TRANSPOSE, <-12, N_GH|D_8, N_G, N_A, N_B|D_8, N_G|D_8, N_FS|D_8, N_FSH, N_GH, N_AH|D_8, N_FSH|D_8
  .byte N_EH|D_8, N_E, N_FS, N_G|D_8, N_E|D_8, TRANSPOSE, 5, N_CS|D_8, N_A, N_G, N_FS|D_8, N_E|D_8
  .byte N_D|D_8, N_G, N_FS, N_E|D_8, N_G|D_8, N_FS|D_8, N_D, N_E, N_FS|D_8, N_A|D_8
  .byte N_G|D_8, N_B, N_A, N_G|D_8, N_FS|D_8, N_E|D_8, N_A, N_G, N_FS|D_8, N_E|D_8
  .byte N_FS|D_8, N_FSH, N_EH, N_FSH|D_8, N_FS|D_8, N_A|D_8, N_A, N_B, N_CSH|D_8, N_A|D_8
  .byte N_FS|D_8, N_DH, N_EH, N_FSH|D_8, N_DH|D_8, N_FSH|D_8, N_FSH, N_EH, N_DH|D_8, N_CSH|D_8
  .byte N_B|D_8, N_B, N_A, N_B|D_8, N_CSH|D_8, N_DH|D_8, N_FSH, N_EH, N_DH|D_8, N_FSH|D_8
  .byte N_GH|D_8, N_DH, N_CSH, N_B|D_8, N_B|D_8, N_A|D_8, N_E|D_8, N_A|D_8, N_A|D_8
  ; 39
  .byte N_A|D_D2, N_A|D_4
  .byte N_D|D_D2, N_A|D_4
  .byte N_G|D_2, N_A|D_2
  .byte N_G|D_4, N_D|D_4, N_D|D_D4, N_CS|D_8
  .byte N_D|D_4, N_DH|D_4, N_CSH|D_2
  .byte N_B|D_2, N_A|D_2
  .byte N_D|D_D4, N_E|D_8, N_FS|D_2
  .byte N_B|D_2, N_E|D_D4, N_E|D_8
  ; 43
  .byte N_FS|D_D4, N_FSH|D_8, N_FSH|D_8, N_GH|D_8, N_FSH|D_8, N_EH|D_8
  .byte N_DH|D_D4, N_DH|D_8, N_DH|D_8, N_EH|D_8, N_DH|D_8, N_CSH|D_8
  .byte N_B|D_2, N_DH|D_2
  .byte N_DH|D_8, N_CH|D_8, N_B|D_8, N_CH|D_8, N_A|D_D4, N_A|D_8
  .byte N_A|D_D4, N_AH|D_8, N_AH|D_8, N_BH|D_8, N_AH|D_8, N_GH|D_8
  .byte N_FSH|D_D4, N_FSH|D_8, N_FSH|D_8, N_GH|D_8, N_FSH|D_8, N_EH|D_8
  .byte N_DH|D_8, N_CH|D_8, N_B|D_8, N_CH|D_8, N_A|D_D4, N_A|D_8
  .byte N_G|D_4, N_DH|D_4, N_CSH|D_D4, N_CSH|D_8
  ; 47
  .byte N_DH|D_4, N_DH|D_2, N_CSH|D_2
  .byte   N_B|D_2, N_A|D_2
  .byte   N_G|D_2, N_FS|D_4
  .byte N_TIE|D_D4, N_E|D_8, N_E|D_2
  .byte N_FS|D_4, N_FSH|D_2, N_EH|D_4
  .byte TRANSPOSE, 12, N_D|D_4, N_DH|D_2, N_CH|D_4
  .byte N_B|D_2, N_DH|D_4, N_A|D_4
  .byte N_B|D_2, N_A|D_2, TRANSPOSE, <-12
  ; 51
  .byte N_AH|D_2, N_A|D_D4, N_G|D_8
  .byte N_FS|D_2, N_FSH|D_D4, N_EH|D_8
  .byte N_DH|D_D2, N_DH|D_4
  .byte N_DH|D_2, N_CSH|D_2
  .byte N_DH|D_4, N_D|D_4, N_CS|D_4, N_CSH|D_4
  .byte N_B|D_4, TRANSPOSE, <-12, N_B|D_4, N_A|D_4, TRANSPOSE, 12, N_A|D_4
  .byte N_G|D_4, N_GH|D_4, N_FSH|D_4, N_FS|D_4
  .byte N_E|D_4, N_B|D_4, N_E|D_4, N_EH|D_4
  ; 55
  .byte N_FSH|D_4, N_FS|D_4, N_E|D_4, N_EH|D_4
  .byte N_DH|D_4, N_D|D_4, N_CS|D_4, N_CSH|D_4
  .byte N_B|D_4, N_BH|D_4, N_AH|D_4, N_A|D_4
  .byte N_G|D_D4, N_EH|D_8, N_A|D_4, N_A|D_4
  .byte N_A|D_2, REST|D_2, REST|D_1
  .byte PATEND
