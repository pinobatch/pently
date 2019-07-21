include "pentlyconfig.inc"
include "pently-asm6.inc"

; TODO: exploit pentlyconfig.inc
; to extract PENTLY_USE_MUSIC and PENTLY_USE_ATTACK_PHASE
; Until then, set size to maximum
PENTLYZP_SIZE = 32
pently_zp_state: dsb PENTLYZP_SIZE
pentlyi_sfx_datalo      = pently_zp_state + 0
pentlyi_sfx_datahi      = pently_zp_state + 1
pentlyi_chnPatternPos   = pently_zp_state + 2
pentlyi_noteAttackPos   = pently_zp_state + 16
pentlyi_conductorPos    = pently_zp_state + 22
pently_tempoCounterLo   = pently_zp_state + 26
pently_tempoCounterHi   = pently_zp_state + 27
pently_music_playing    = pently_zp_state + 30
pentlyi_attackChn       = pently_zp_state + 31
