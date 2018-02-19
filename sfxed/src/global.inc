.globalzp doc_yscroll, cursor_x, cursor_y, mouse_x, mouse_y
.globalzp changed_things
.global play_all_sounds, update_sound_length, get_scrollthumb_y
; vwf_draw
.global vwfPutTile, vwfPuts, vwfPuts0
.global vwfGlyphWidth, vwfStrWidth, vwfStrWidth0
.global clearLineImg, copyLineImg, invertTiles
; bg
.globalzp nmis, dirty_areas, debughex
.global bg_init, scroll_to_cursor, prepare_something, present
.global one_shl_x
; pads
.globalzp cur_keys, new_keys, das_keys, das_timer
.global read_pads, autorepeat
; mouse
.globalzp cur_mbuttons, new_mbuttons, mouse_mask, mouse_port
.global mouse_change_sensitivity, read_mouse_ex, detect_mouse
KEY_LMB = KEY_B
KEY_RMB = KEY_A
; sound
.globalzp psg_sfx_state
.global init_sound, start_sound
.global init_sound, start_sound, update_sound
.global psg_sound_table, psg_sound_data
; paldetect
.globalzp tvSystem
.global getTVSystem
; ppuclear
.global OAM
.global ppu_clear_oam, ppu_clear_nt, ppu_screen_on
; editactions/mouseactions
.globalzp held_keys, action_release_keys
.globalzp mouse_gesture, gesture_x, gesture_y, gesture_z
.global handle_keys, change_cell_at_cursor, seek_to_xy
.global cancel_release_action
.global handle_mouse
; bcd
.global bcd8bit
; random (used by save)
.globalzp CRCHI, CRCLO
.global rand_crc, crc16_update
; export
.global save_to_sram, load_from_sram

NUM_SOUNDS = 4
MAX_ROWS_PER_SOUND = 64
BYTES_PER_SOUND = 2 * MAX_ROWS_PER_SOUND
SCREEN_HT = 20

DIRTY_SCROLL = 1 << NUM_SOUNDS
DIRTY_RATE_LINE = DIRTY_SCROLL << 1
DIRTY_TOP_BAR = DIRTY_RATE_LINE << 1

CHANGED_PLAYROW = 1 << 0

GESTURE_DEFAULT = 0
GESTURE_SCROLLTHUMB = 2
GESTURE_SCROLLLINE = 4
GESTURE_SCROLLPAGE = 6
GESTURE_CELLDRAG = 8

.macro lday arg
  .local argvalue
  .if (.match (.left (1, {arg}), #))
    argvalue = .right(.tcount({arg})-1, {arg})
    lda #>argvalue
    .if .const(argvalue) && (>argvalue = <argvalue)
      tay
    .else
      ldy #<argvalue
    .endif
  .else
    argvalue = arg
    lda arg+1
    ldy arg
  .endif
.endmacro

.macro stay arg
  .local argvalue
  argvalue = arg
  sty arg
  sta arg+1
.endmacro

.macro axs arg
  .local argvalue
  .assert (.match (.left (1, {arg}), #)), error, "AXS requires an immediate operand"
  argvalue = .right(.tcount({arg})-1, {arg})
  .byte $CB, argvalue
.endmacro



