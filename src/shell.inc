;
; Pently NES shell
; Copyright 2009-2015 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

OAM = $0200

; main.s fields
.globalzp cur_keys, new_keys, nmis, tvSystem

; pads.s methods
.global read_pads

; ppuclear.s fields
.globalzp oam_used
; ppuclear.s methods
.global ppu_clear_oam

; bcd.s methods
.global bcd8bit

; math.s methods
.global mul8

; bpmmath.s methods
.global getCurBeatFraction

