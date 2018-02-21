.include "nes.inc"
.include "global.inc"
.segment "ZEROPAGE"
action_release_keys: .res 1
held_keys: .res 1
mouse_x: .res 1  ; 8-249
mouse_y: .res 1  ; 0-203 (add 15 before displaying)
mouse_gesture: .res 1
gesture_x: .res 1
gesture_y: .res 1
gesture_z: .res 1

.segment "CODE"

.proc handle_keys
  ; A key being held down can be in one of three states:
  ; "action release": Releasing the key will do something
  ; (e.g. A in timbre subcolumn or top bar)
  ; "held": Pressing another key while this is held will do something
  ; (e.g. A + Control Pad to change a value)
  ; "repress": Treat as unpressed until released and pressed again
  ; (e.g. B and A after pressing B+A to play)
  ; Pressing a key puts it into action release and held
  jsr check_release_actions

  lda new_keys
  and cur_keys  ; cancel virtual keys pressed by release actions
  sta new_keys
  ora action_release_keys
  and cur_keys
  sta action_release_keys
  lda new_keys
  ora held_keys
  and cur_keys
  sta held_keys
  and das_keys  ; if a key needs to be repressed,
  sta das_keys  ; don't allow it to trigger autorepeat

  ; Actions that can't be autorepeated:
  ; B+A to play, Start to save, etc.
  lda cur_keys
  and #KEY_B|KEY_A
  cmp #KEY_B|KEY_A
  bne not_play
  and new_keys
  beq not_play
  jsr play_all_sounds
  lda #KEY_B|KEY_A
  jsr cancel_release_action
not_play:

  lda new_keys
  and #KEY_START
  beq not_save
  jsr save_to_sram
not_save:
  

  ldx #0
  jsr autorepeat

  lda held_keys
  bpl not_heldA
  jmp hold_A_move
not_heldA:

  ; If B is pressed while cursor is in patterns, set the old cursor
  ; position as the origin for a copy gesture.  Otherwise cancel B
  ; release action.
  lda new_keys
  and #KEY_B
  beq not_pressB
  lda #0
  sta das_keys  ; The B button should not be autorepeatable
  ldy cursor_y
  bpl start_copy_gesture
  jmp cancel_release_action

start_copy_gesture:
  sta debughex+0
  lda nmis
  sta debughex+1
  sty gesture_y
  lda cursor_x
  and #$FC  ; B gestures don't depend on subcolumn position
  sta gesture_x
  rts
not_pressB:
  jmp move_cursor
.endproc

;;
; Requires specific keys to be released and repressed before they
; will again be recognized as held.
; @param A key bits
.proc require_repress
  eor #$FF
  and held_keys
  sta held_keys
  rts
.endproc

;;
; Cancels the release action for specific keys.
; @param A key bits
.proc cancel_A_release_action
  lda #KEY_A
.endproc
.proc cancel_release_action
  eor #$FF
  and action_release_keys
  sta action_release_keys
  rts
.endproc

;;
; Moves the cursor based on the Control Pad directions in new_keys.
.proc move_cursor
  lda new_keys
  lsr a
  bcc notRight

  ; if in copy gesture or in top bar, move a sound at a time
  bit action_release_keys
  bvs rightNextSound
  bit cursor_y
  bpl rightNextSubcolumn
rightNextSound:
  lda cursor_x
  clc
  adc #4
writebackIfXInbound:
  cmp #4 * NUM_SOUNDS
  bcs rightbail1
have_cursor_x:
  sta cursor_x
rightbail1:
  rts
rightNextSubcolumn:
  lda cursor_x
  cmp #(NUM_SOUNDS-1)*4+2
  bcs already_at_side
  and #$03
  cmp #2  ; carry set iff the cursor would leave the column
  bcc :+
  lda #CHANGED_PLAYROW
  ora changed_things
  sta changed_things
:
  lda cursor_x
  adc #1  ; add 2 if leaving column or 1 otherwise
  jmp writebackIfXInbound
notRight:

  lsr a
  bcc notLeft
  ; if in copy gesture or in top bar, move a sound at a time
  bit action_release_keys
  bvs leftPreviousSound
  bit cursor_y
  bpl leftPreviousSubcolumn
leftPreviousSound:
  lda cursor_x
  sec
  sbc #4
  bcs have_cursor_x
  rts
leftPreviousSubcolumn:
  lda cursor_x
  beq already_at_side
  and #$03
  cmp #1  ; carry set iff the cursor would stay in the column
  bcs :+
  lda #CHANGED_PLAYROW
  ora changed_things
  sta changed_things
:
  lda cursor_x
  sbc #1  ; subtract 2 if leaving column or 1 otherwise
  bcs have_cursor_x
already_at_side:
  rts
notLeft:

  lsr a
  bcc notDown
  lda cursor_y
  bmi downYes
  cmp #MAX_ROWS_PER_SOUND-1
  bcs rightbail1
downYes:
  inc cursor_y
play_and_scroll_to_cursor:
  lda #CHANGED_PLAYROW
  ora changed_things
  sta changed_things
  jmp scroll_to_cursor
notDown:

  lsr a
  bcc notUp
  lda cursor_y
  bpl upYes
  cmp #<-2
  bcc rightbail1
upYes:
  dec cursor_y
  jmp play_and_scroll_to_cursor
notUp:
  rts
.endproc

.proc check_release_actions
  lda cur_keys
  eor #$FF
  and action_release_keys
  asl a
  bcc notA
  lda cursor_y  ; If in channel or mute, A then release = A+Right
  bpl Arel_in_pattern
  and #%11111101
  cmp #%11111101
  beq simulate_A_right
  bne nothing
Arel_in_pattern:
  lda cursor_x  ; If in timbre, A then release = change timbre
  and #$02
  beq nothing
simulate_A_right:
  lda #KEY_RIGHT
  jmp change_cell_at_cursor
notA:

  asl a
  bcc nothing

  ; If B was released in a different column, copy the column
  lda cursor_x
  eor gesture_x
  and #$FC
  beq B_same_column
  jmp copy_sound_gtoc
B_same_column:

  ; If B was released in a different row of the same column, do an
  ; insert or delete
  lda cursor_y
  bmi nothing
  eor gesture_y
  beq nothing
  jmp insert_rows
nothing:
  rts
.endproc

;;
; Seeks to the data that the handler is going to modify.
; @param X cursor X
; @param Y cursor Y (unchanged)
; @return $00: pointer to row;
;         $02: sound's hardware channel (0, 8, or 12);
;         $03: sound number times 4
.proc seek_to_xy
datalo = $00
datahi = $01
channel = $02
xbase = $03
  txa
  and #$FC
  sta xbase
  tax
  lda pently_sfx_table+2,x
  and #$0C
  sta channel
  ; A = mode byte; X = sound number * 4; Y = row number
  cpy #MAX_ROWS_PER_SOUND
  bcc within_pattern

  ; If Y is in the top bar, point to the mode byte (byte 2) of
  ; the pently_sfx_table entry.  But because cpy set the carry,
  ; add only 1 more.
  txa
  ora #$01
  adc #<pently_sfx_table
  sta datalo
  lda #>pently_sfx_table
  jmp have_high_ac
within_pattern:
  tya
  asl a
  ; X: sound number * 4; A: offset within the sound's data
  adc pently_sfx_table,x
  sta datalo
  lda pently_sfx_table+1,x
have_high_ac:
  adc #0
  sta datahi
  rts
.endproc

.proc hold_A_move
  ; Do nothing if no direction on the Control Pad is pressed
  lda new_keys
  and #$0F
  bne :+
  rts
:
  jsr cancel_A_release_action
  lda new_keys
.endproc
.proc change_cell_at_cursor
  ldx cursor_x
  ldy cursor_y
.endproc
;;
; @param X cursor X
; @param Y cursor Y
; @param A the direction to move
.proc change_cell
action = $04
subcol = $05
  sta action
  txa
  and #$03
  sta subcol
  jsr seek_to_xy

  ; Compute the table entry
  ; 0: this cell's pitch
  ; 1: this cell's volume
  ; 2: this cell's timbre
  ; 3: this sound's channel
  ; 4: this sound's rate
  ; 5: this sound's mute status
  tya
  cmp #<253
  bcc handler_from_subcol
  sbc #250
  tay
  bcs have_handler_id
handler_from_subcol:
  ldy subcol
have_handler_id:
  
  ; Now decide which table to look in
  ; up: 3, down: 2, left: 1, right: 0
  lda action
  ldx #0
which_dir_loop:
  lsr a
  bcs have_x
  inx
  bne which_dir_loop
have_x:

  ; Now compute 12*x+2*y
  tya
  asl a
  adc times12,x
  tax
  lda handlers+1,x
  pha
  lda handlers+0,x
  pha
nop_handler:
  rts
.pushseg
.segment "RODATA"
handlers:
  ; Right in pattern
  .addr inc_note-1, inc_volume-1, inc_timbre-1
  ; Right in top bar
  .addr inc_channel-1, inc_rate-1, toggle_mute-1
  ; Left in pattern
  .addr dec_note-1, dec_volume-1, dec_timbre-1
  ; Left in top bar
  .addr dec_channel-1, dec_rate-1, toggle_mute-1
  ; Down in pattern
  .addr dec_octave-1, dec_volume-1, dec_timbre-1
  ; Down in top bar
  .addr dec_channel-1, dec_rate-1, toggle_mute-1
  ; Up in pattern
  .addr inc_octave-1, inc_volume-1, inc_timbre-1
  ; Up in top bar
  .addr inc_channel-1, inc_rate-1, toggle_mute-1
times12:
  .byte 0, 12, 24, 36
.popseg
.endproc
hambail = change_cell::nop_handler

.proc inc_timbre
  lda $0002
  beq is_pulse
  cmp #$0C
  bne hambail

  ; Noise: toggle bit 7 of second byte
is_noise:
  ldy #1
  lda (0),y
  eor #$80
  sta (0),y
  jmp set_current_column_dirty
is_pulse:
  ; Pulse: add $40 to first byte, wrapping at $C0
  ldy #0
  clc
  lda (0),y
  adc #$40
  cmp #$C0
  bcc :+
  and #$3F
:
  sta (0),y
  jmp set_current_column_dirty
.endproc

.proc dec_timbre
  lda $0002
  beq is_pulse
  cmp #$0C
  beq inc_timbre::is_noise
  rts
is_pulse:
  ; Pulse: add $C0 to first byte, wrapping at $C0
  ldy #0
  clc
  lda (0),y
  adc #$C0
  bcs :+
  adc #$C0
:
  sta (0),y
  jmp set_current_column_dirty
.endproc

.proc inc_note
  ldy #1
  lda $0002
  cmp #$0C
  bcc is_melodic
is_noise:
  lda (0),y
  and #$0F
  sbc #1
  bcc sccdbail
noise_writeback_note:
  eor (0),y
  and #$7F
  eor (0),y
  sta (0),y
  jmp set_current_column_dirty
is_melodic:
  lda #1
add_pos_to_note:
  adc (0),y
  cmp #$40
  bcs sccdbail
  sta (0),y
  jmp set_current_column_dirty
.endproc
  
.proc dec_note
  ldy #1
  lda $0002
  cmp #$0C
  bcc is_melodic
is_noise:
  lda (0),y
  and #$0F
  adc #0
  cmp #$10
  bcc inc_note::noise_writeback_note
  rts
is_melodic:
  lda #<-1
add_neg_to_note:
  adc (0),y
  bcc sccdbail
  sta (0),y
  jmp set_current_column_dirty
.endproc

.proc dec_volume
  ldy #0
  lda (0),y
  and #$0F
  beq sccdbail
  lda (0),y
  sec
  sbc #1
  sta (0),y
  jmp set_current_column_dirty
.endproc

.proc inc_volume
  ldy #0
  lda (0),y
  and #$0F
  cmp #$0F  ; Don't try to increase if already $FF
  bcs sccdbail
  lda (0),y
  adc #1
  sta (0),y
  ; fall through to set_current_column_dirty
.endproc
.proc set_current_column_dirty
  lda #CHANGED_PLAYROW
  ora changed_things
  sta changed_things
.endproc
.proc set_current_column_dirty_silent
  lda cursor_x
  lsr a
  lsr a
  tax
  lda one_shl_x,x
  ora dirty_areas
  sta dirty_areas
bail:
  rts
.endproc
sccdbail = set_current_column_dirty_silent::bail

.proc inc_octave
  ldy #1
  lda $0002
  cmp #$0C
  bcs inc_note::is_noise
  lda #12
  bne inc_note::add_pos_to_note
.endproc

.proc dec_octave
  ldy #1
  lda $0002
  cmp #$0C
  bcs dec_note::is_noise
  lda #<-12
  bne dec_note::add_neg_to_note
.endproc

.proc inc_channel
  lda 2
  bne :+
  lda #4
:
  clc
  adc #4
writeback_channel:
  ldy #0
  eor (0),y
  and #$0C
  eor (0),y
  sta (0),y
  lda #DIRTY_TOP_BAR
  ora dirty_areas
  sta dirty_areas
  bne set_current_column_dirty
.endproc

.proc dec_channel
  lda 2
  sec
  sbc #4
  cmp #4
  bne inc_channel::writeback_channel
  lda #0
  beq inc_channel::writeback_channel
.endproc

.proc inc_rate
  ldy #0
  lda (0),y
  clc
  adc #$10
  bcs bail
writeback_rate:
  sta (0),y
  lda #DIRTY_RATE_LINE
add_A_dirty:
  ora dirty_areas
  sta dirty_areas
bail:
  rts
.endproc

.proc dec_rate
  ldy #0
  lda (0),y
  sec
  sbc #$10
  bcs inc_rate::writeback_rate
  rts
.endproc

.proc toggle_mute
  ldy #0
  lda (0),y
  eor #1
  sta (0),y
  lda #DIRTY_TOP_BAR
  bne inc_rate::add_A_dirty
.endproc

;;
; Copies the data in sound gesture_x/4 to sound cursor_x/4.
.proc copy_sound_gtoc
src = $00
dst = $02
  lda gesture_x
  and #$FC
  tax
  lda pently_sfx_table+0,x
  sta src+0
  lda pently_sfx_table+1,x
  sta src+1
  lda cursor_x
  and #$FC
  tay
  lda pently_sfx_table+0,y
  sta dst+0
  lda pently_sfx_table+1,y
  sta dst+1
  lda pently_sfx_table+2,x
  sta pently_sfx_table+2,y
  ldy #0
copyloop:
  lda (src),y
  sta (dst),y
  iny
  cpy #BYTES_PER_SOUND
  bne copyloop
  lda cursor_x
  lsr a
  lsr a
  tax
  lda one_shl_x,x
  ora dirty_areas
  ora #DIRTY_TOP_BAR|DIRTY_RATE_LINE
  sta dirty_areas
  rts
.endproc

.proc insert_rows
src = $00
dst = $02
  lda cursor_x
  and #$FC
  tax

  ; calculate the start of the area affected by the copy
  lda gesture_y
  asl a
  adc pently_sfx_table+0,x
  sta src+0
  lda #0
  adc pently_sfx_table+1,x
  sta src+1
  lda cursor_y
  asl a
  adc pently_sfx_table+0,x
  sta dst+0
  lda #0
  adc pently_sfx_table+1,x
  sta dst+1

  ; use an increasing or decreasing loop depending on the direction
  lda cursor_y
  cmp gesture_y
  bcs copy_down
  
  sec
  lda #MAX_ROWS_PER_SOUND
  sbc gesture_y
  asl a
  tax
inccopyloop:
  lda (src),y
  sta (dst),y
  iny
  dex
  bne inccopyloop
  jmp set_current_column_dirty_silent

copy_down:
  sec
  lda #MAX_ROWS_PER_SOUND
  sbc cursor_y
  asl a
  tax
  tay
  dey
deccopyloop:
  lda (src),y
  sta (dst),y
  dey
  dex
  bne deccopyloop
  jmp set_current_column_dirty_silent
.endproc
