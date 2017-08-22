; Configuration settings for Pently

; Disable features to save ROM space
PENTLY_USE_PAL_ADJUST = 1
PENTLY_USE_ROW_CALLBACK = 0
PENTLY_USE_VIBRATO = 1
PENTLY_USE_ARPEGGIO = 1
PENTLY_USE_PORTAMENTO = 1
PENTLY_USE_BPMMATH = 1
PENTLY_USE_ATTACK_TRACK = 1
PENTLY_USE_ATTACK_PHASE = 1
PENTLY_USE_SQUARE_POOLING = 1
PENTLY_USE_MUSIC_IF_LOUDER = 1
PENTLY_USE_CHANNEL_VOLUME = 1

; Should sound effects be selectable?
PENTLY_USE_NSF_SOUND_FX = 1

; 0-127; higher means quieter tri/noise
PENTLY_INITIAL_4011 = 64

; Five bytes of scratch space on zero page that need not be preserved
; across calls.  This needs to be either an = or an .importzp

pently_zptemp = $0000
; .importzp pently_zptemp

.define PENTLY_CODE "CODE"
.define PENTLY_RODATA "RODATA"
