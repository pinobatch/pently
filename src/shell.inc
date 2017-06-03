;
; Pently audio engine
; Common routines used by NES shell
; Copyright 2009-2015 Damian Yerrick
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

OAM = $0200

; main.s fields
.globalzp cur_keys, new_keys, nmis, tvSystem

; pads.s methods
.global read_pads

; ppuclear.s fields
.globalzp oam_used
; ppuclear.s methods
.global ppu_clear_oam

; math.s methods
.global mul8

