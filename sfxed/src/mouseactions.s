.include "nes.inc"
.include "global.inc"

.zeropage
last_sensitivity: .res 1

.code

;;
; @param X, Y mouse
; @param cur_mbuttons, new_mbuttons
.proc handle_mouse
  stx 0
  sty 1
  
  ; copy right mouse button to B, as they're equivalent
  ; in all current gestures
  .assert KEY_RMB >> 1 = KEY_B, error, "KEY_B and KEY_RMB assumption violated"
  lda cur_mbuttons
  and #KEY_RMB
  lsr a
  ora cur_keys
  sta cur_keys
  lda new_mbuttons
  and #KEY_RMB
  lsr a
  ora new_keys
  sta new_keys

  ; If sensitivity changed, schedule redraw
  lda cur_mbuttons
  and #$30
  cmp last_sensitivity
  beq sensitivity_not_changed
    sta last_sensitivity
    lda #DIRTY_MOUSE_STATUS
    ora dirty_areas
    sta dirty_areas
  sensitivity_not_changed:

  ; check for play/cancel command (L+R)
  lda cur_mbuttons
  and #KEY_LMB|KEY_RMB
  cmp #KEY_LMB|KEY_RMB
  bne not_play
  and new_mbuttons
  beq not_play
  jsr move_mouse_pointer
  jsr play_all_sounds
  lda #0
  sta mouse_gesture
  lda #KEY_B|KEY_A
  jmp cancel_release_action

not_play:
  ldx mouse_gesture
  lda gesture_handlers+1,x
  pha
  lda gesture_handlers+0,x
  pha
  ldx 0
gesture_nop:
  rts
gesture_handlers:
; Gestures are called with X = $0000 = delta X
; and Y = $0001 = delta Y
  .addr mouse_gesture_default-1
  .addr mouse_gesture_scroll_thumb-1
  .addr mouse_gesture_scroll_line-1
  .addr mouse_gesture_scroll_page-1
  .addr mouse_gesture_celldrag-1
.endproc

;;
; Converts mouse_y to cursor_y.
; @return C clear if mouse_y in bounds; A = new cursor_y
.proc mouse_y_to_cursor_y
  lda mouse_y
  lsr a
  lsr a
  lsr a
  beq oob
  cmp #TOPBAR_HT + SCREEN_HT
  bcc inbounds
oob:
  sec
  rts
inbounds:
  adc #<-TOPBAR_HT
  bcc is_topbar
  clc
  adc doc_yscroll
is_topbar:
  rts
.endproc

;;
; Converts mouse_x to cursor_x.
; @return C clear if mouse_x in range; A = new cursor_y
.proc mouse_x_to_cursor_x
  ; mouse_tile = (mouse_x >> 3 - 16)
  ; mouse_tile += (mouse_tile >= 21)
  ; mouse_tile += (mouse_tile >= 14)
  ; mouse_tile += (mouse_tile >= 7)
  ; return mouse_tile >> 1
  lda mouse_x
  sec
  sbc #16
  cmp #56 * NUM_SOUNDS - 8
  bcs have_inbounds
  lsr a
  lsr a
  lsr a
  cmp #21
  adc #0
  cmp #14
  adc #0
  cmp #7
  adc #0
  lsr a
  ; At this point, bits 3-2 are the sound and bits 1-0 are the
  ; subcolumn.  Subcolumn 3 represents the space between columns,
  ; which is out of bounds.
  pha
  and #$03
  cmp #$03
  pla
have_inbounds:
  rts
.endproc


;;
; Moves the cursor under the mouse.
; @return C clear if in bounds
.proc mouse_place_cursor
  jsr mouse_y_to_cursor_y
  bcs ob
  sta $03
  jsr mouse_x_to_cursor_x
  bcs ob
  sta $02

  ; Write back cursor X, but play the current row only if
  ; it has moved into another sound
  eor cursor_x
  cmp #4
  lda $02
  sta cursor_x
  bcs lmb_isnewrow
  lda $03
  eor cursor_y
  beq lmb_notnewrow
lmb_isnewrow:
  lda #CHANGED_PLAYROW
  ora changed_things
  sta changed_things
lmb_notnewrow:
  lda $03
  sta cursor_y
  clc
ob:
  rts
.endproc

.proc mouse_gesture_default

  ; If in a B-drag, just move the cursor and be done with it.
  bit action_release_keys
  bvc not_bdrag
  cpy #0
  bne bdrag_moved
  cpx #0
  beq not_lmb
bdrag_moved:
  jsr move_mouse_pointer
  jmp mouse_place_cursor

not_bdrag:
  jsr move_mouse_pointer
  bit new_mbuttons
  bpl not_rmb
  jmp mouse_place_cursor
  
not_rmb:
  bvc not_lmb

  ; Status bar click changes mouse sensitivity
  lda mouse_y
  sec
  sbc #8 * (TOPBAR_HT + SCREEN_HT)
  bcs mouse_footer_click

  ; In left margin: Do nothing
  lda mouse_x
  cmp #16
  bcc not_lmb

  ; In right margin and below header: Start a scrolling gesture
  cmp #240
  bcc not_scrollbar
  lda mouse_y
  cmp #8 * TOPBAR_HT
  bcs start_scrollbar_gesture
not_scrollbar:

  ; Within a clickable area of the client area or header
  jsr mouse_place_cursor
  bcs not_lmb

  ; If in a toggle-now area (Y=-3, Y=-1, X&3=2), send A+Right.
  ; Otherwise enter cell drag
  lda cursor_y
  bpl lmb_in_pattern
  cmp #<-2
  bne do_toggle
begin_celldrag:
  lda #GESTURE_CELLDRAG
  sta mouse_gesture
  lda #$80
  sta gesture_x
  sta gesture_y
  rts
lmb_in_pattern:
  lda cursor_x
  and #$02
  beq begin_celldrag
do_toggle:
  lda #KEY_RIGHT
  jmp change_cell_at_cursor

not_lmb:
  rts
.endproc

.proc start_scrollbar_gesture
  jsr get_scrollthumb_y
  sec
  sbc #15  ; A = scrollthumb in mouse coordinate space
  eor #$FF
  adc mouse_y  ; A = distance from scrollthumb to top of mouse
  cmp #45
  bcs not_scrollthumb
  lda #GESTURE_SCROLLTHUMB
  sta mouse_gesture
  lda doc_yscroll
  sta gesture_z
  lda mouse_y
  sta gesture_y
  rts
not_scrollthumb:
  lda mouse_y
  lsr a
  lsr a
  lsr a
  ldy #GESTURE_SCROLLLINE
  cmp #4
  beq have_gesture
  cmp #SCREEN_HT+3
  beq have_gesture
  ldy #GESTURE_SCROLLPAGE
have_gesture:
  sty mouse_gesture
  lda #0
  sta gesture_z
  rts
.endproc


;;
; @param A height of click below top of footer in pixels
; @param mouse_x horizontal position of click
.proc mouse_footer_click
  lsr a
  lsr a
  lsr a
  bne not_row_0
    ; Right half of row 0: Change sensitivity
    lda mouse_x
    bpl unknown_footer_click
    ldx mouse_port
    jmp mouse_change_sensitivity
  not_row_0:

  unknown_footer_click:
  rts
.endproc

.proc mouse_gesture_celldrag
keystosend = $00
  lda #0
  sta keystosend
  
  txa
  clc
  adc gesture_x
  sta gesture_x
  cmp #128-8
  bcs notL
  adc #8
  sta gesture_x
  lda #KEY_LEFT
  bne haveLRkey
notL:
  cmp #128+9
  bcc notR
  sbc #8
  sta gesture_x
  lda #KEY_RIGHT
haveLRkey:
  ora keystosend
  sta keystosend
notR:

  tya
  clc
  adc gesture_y
  sta gesture_y
  cmp #128-8
  bcs notU
  adc #8
  sta gesture_y
  lda #KEY_UP
  bne haveUDkey
notU:
  cmp #128+9
  bcc notD
  sbc #8
  sta gesture_y
  lda #KEY_DOWN
haveUDkey:
  ora keystosend
  sta keystosend
notD:

  lda keystosend
  beq :+
    jsr change_cell_at_cursor
  :
  jmp end_gesture_if_lmb_up
.endproc

;;
; Gesture: Dragging scrollbar thumb
; gesture_y = starting Y coordinate
; gesture_z = starting scroll position
.proc mouse_gesture_scroll_thumb
  jsr move_mouse_pointer
  lda #128
  ldx mouse_x
  cpx #192
  bcc have_cursor_dist
  lda mouse_y
  sec
  sbc gesture_y  ; C = inverted sign bit of result
  ror a
  bmi have_cursor_dist
  clc  ; round down when going down but round normally going up
have_cursor_dist:

  ; Here, 128 means no change, <128 means up, and >128 means down
  adc gesture_z
  ; so carry set means overflow, and bit 7 clear means underflow
  eor #$80
  bpl :+
  lda #0
:
  bcs is_overflow
  cmp #MAX_ROWS_PER_SOUND - SCREEN_HT
  bcc not_overflow
is_overflow:
  lda #MAX_ROWS_PER_SOUND - SCREEN_HT
not_overflow:
  cmp doc_yscroll
  beq yscroll_unchanged
  sta doc_yscroll
  lda #DIRTY_SCROLL
  ora dirty_areas
  sta dirty_areas
yscroll_unchanged:
  bit cur_mbuttons
  bvs still_scrolling
  lda #GESTURE_DEFAULT
  sta mouse_gesture
still_scrolling:
  rts
.endproc
writeback_while_lmb_down = mouse_gesture_scroll_thumb::not_overflow
end_gesture_if_lmb_up = mouse_gesture_scroll_thumb::yscroll_unchanged

;;
; Handle 15 Hz autorepeat with mouse gestures
; @return C true if autorepeated action should be taken
.proc autorepeat_gesture_z
  inc gesture_z
  lda gesture_z
  cmp #1
  beq have_c
  cmp #16
  bcc have_c
  lda #12
  sta gesture_z
have_c:
  rts
.endproc

;;
; Z: autorepeat time
.proc mouse_gesture_scroll_line
  jsr move_mouse_pointer
  jsr autorepeat_gesture_z
  bcc nope
  lda mouse_x
  cmp #240
  bcc nope
  lda mouse_y
  sbc #32
  lsr a
  lsr a
  lsr a
  lsr a
  beq neg
  cmp #(SCREEN_HT / 2) - 1
  beq pos
nope:
  jmp end_gesture_if_lmb_up
pos:
  lda doc_yscroll
  cmp #MAX_ROWS_PER_SOUND - SCREEN_HT
  bcs nope
  clc
  adc #1
  jmp writeback_while_lmb_down
neg:
  lda doc_yscroll
  beq nope
  sec
  sbc #1
  jmp writeback_while_lmb_down
.endproc

;;
; Z: autorepeat time
.proc mouse_gesture_scroll_page
  jsr move_mouse_pointer
  jsr autorepeat_gesture_z
  bcc nope
  lda mouse_x
  cmp #240
  bcc nope
  ; is it still not overlapping the thumb?
  jsr get_scrollthumb_y
  sec
  sbc #15  ; A = scrollthumb in mouse coordinate space
  eor #$FF
  adc mouse_y  ; A = distance from scrollthumb to top of mouse
  bcc neg
  cmp #45
  bcs pos
nope:
  jmp end_gesture_if_lmb_up
pos:
  lda doc_yscroll
  clc
  adc #SCREEN_HT-4
  cmp #MAX_ROWS_PER_SOUND - SCREEN_HT
  bcc :+
  lda #MAX_ROWS_PER_SOUND - SCREEN_HT
:
  jmp writeback_while_lmb_down
neg:
  lda doc_yscroll
  sec
  sbc #SCREEN_HT-4
  bcs :+
  lda #0
:
  jmp writeback_while_lmb_down
.endproc

;;
; Moves the mouse pointer by a distance if it wouldn't leave
; (0, 0)-(255, 255).
; @param X two's complement horizontal displacement
; @param Y two's complement vertical displacement
.proc move_mouse_pointer
  stx 0
  lda mouse_x
  clc
  eor #$80
  adc 0
  eor #$80
  bvs :+
    sta mouse_x
  :
  sty 0
  lda mouse_y
  clc
  eor #$80
  adc 0
  eor #$80
  bvs :+
    sta mouse_y
  :
  rts
.endproc
