_INESPRG = 1    ; 16384 byte units
_INESCHR = 1    ; 8192 byte units
_INESMIR = $01  ; 0: VRAM A10=PA11; 1: VRAM A10=PA10
_INESMAP = 0    ; NROM

PPUCTRL      = $2000
  VRAM_DOWN  = $04
  OBJ_0000   = $00
  OBJ_1000   = $08
  OBJ_8X16   = $20
  BG_0000    = $00
  BG_1000    = $10
  VBLANK_NMI = $80
PPUMASK      = $2001
  LIGHTGRAY  = $01
  BG_CLIP    = $08
  BG_ON      = $0A
  OBJ_CLIP   = $10
  OBJ_ON     = $14
  TINT_R     = $20
  TINT_G     = $40
  TINT_B     = $80
PPUSTATUS    = $2002
OAMADDR      = $2003
PPUSCROLL    = $2005
PPUADDR      = $2006
PPUDATA      = $2007
OAM_DMA      = $4014
P1           = $4016
P2           = $4017


; Zero page variables
enum $0010
  nmis: dsb 1
  tvSystem: dsb 1
  oam_used: dsb 1
  cur_keys: dsb 2
  new_keys: dsb 2
  include "pentlyzp.inc"
ende

enum $0200
  OAM: dsb 256
  include "pentlybss.inc"
ende

; iNES header
  db "NES",$1A
  db _INESPRG, _INESCHR
  db _INESMIR | ((_INESMAP & $0F) << 4)
  db (_INESMAP & $F0)
  dsb 8, $00

; Code start
  .base $C000
nmi_handler:
  inc nmis
irq_handler:
  rti
reset_handler:
  sei
  cld
  ldx #$40
  stx $4017  ; disable APU frame IRQ
  ldx #$FF
  txs        ; init stack
  inx
  stx $2000  ; disable vblank NMI
  stx $2001  ; disable rendering
  stx $4010  ; disable DMC IRQ
  bit $2002  ; acknowledge NMI if reset during vblank

@vblankwait1:
  bit $2002
  bpl @vblankwait1
@vblankwait2:
  bit $2002
  bpl @vblankwait2

  ; fall through

main:
  lda #VBLANK_NMI
  sta PPUCTRL
  lda #$3F
  sta PPUADDR
  ldx #$00
  stx PPUADDR
  @loadpalloop:
    lda initial_palette,x
    sta PPUDATA
    inx
    cpx #32
    bcc @loadpalloop

  ; Load initial nametable
  stx PPUADDR
  ldy #0
  sty PPUADDR
  @load_iso_nt_row:
    tya
    and #$01
    asl a
    ldx #32
    @load_iso_nt_cell:
      ora #$0C
      sta PPUDATA
      adc #1
      and #3
      dex
      bne @load_iso_nt_cell
    iny
    cpy #30
    bne @load_iso_nt_row
  txa
  ldx #64
  @load_iso_nt_attr:
    sta PPUDATA
    dex
    bne @load_iso_nt_attr
  stx tvSystem

  jsr pently_init
  lda #PS_arp_waltz
  jsr pently_start_music

forever:
  jsr pently_update
  ldx #0
  stx oam_used

  lda #112
  sta msprXLo
  lda #128
  sta msprYLo
  lda #0
  sta msprYHi
  sta msprXHi
  sta msprAttr
  lda #$60
  sta msprBaseTile
  ldx #0
  lda #4
  jsr draw_metasprite

  lda #64
  sta msprXLo
  lda #104
  sta msprYLo
  lda #0
  sta msprYHi
  sta msprXHi
  lda #$40
  sta msprAttr
  lda #$60
  sta msprBaseTile
  ldx #0
  lda #2
  jsr draw_metasprite

  lda #160
  sta msprXLo
  lda #104
  sta msprYLo
  lda #0
  sta msprYHi
  sta msprXHi
  sta msprAttr
  lda #$60
  sta msprBaseTile
  ldx #0
  lda #2
  jsr draw_metasprite

  lda #112
  sta msprXLo
  lda #80
  sta msprYLo
  lda #0
  sta msprYHi
  sta msprXHi
  sta msprAttr
  lda #$60
  sta msprBaseTile
  ldx #0
  lda #0
  jsr draw_metasprite

  ldx oam_used
  jsr ppu_clear_oam

  lda nmis
  @nmiwait:
    cmp nmis
    beq @nmiwait
  lda #>OAM
  sta OAM_DMA
  ldx #0
  ldy #0
  lda #VBLANK_NMI
  sec
  jsr ppu_screen_on
  jmp forever

initial_palette:
  hex 0f202a1a 0f242424 0f242424 0f242424
  hex 0f27180f 0f381202 0f242424 0f242424

include "ppuclear.asm"
include "metasprite.asm"
include "pently-asm6.asm"
include "musicseq.asm"

; Vectors
  org $FFFA
  dw nmi_handler, reset_handler, irq_handler

  base $0000
  incbin "asm6shelltiles.chr"
