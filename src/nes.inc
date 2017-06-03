;
; NES MMIO port definitions
;
; Copyright 2003-2016 Damian Yerrick
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

PPUCTRL = $2000
NT_2000 = $00
NT_2400 = $01
NT_2800 = $02
NT_2C00 = $03
VRAM_DOWN = $04
OBJ_0000 = $00
OBJ_1000 = $08
OBJ_8X16 = $20
BG_0000 = $00
BG_1000 = $10
VBLANK_NMI = $80

PPUMASK = $2001
LIGHTGRAY = $01
BG_OFF = $00
BG_CLIP = $08
BG_ON = $0A
OBJ_OFF = $00
OBJ_CLIP = $10
OBJ_ON = $14
TINT_R = $20
TINT_G = $40
TINT_B = $80

PPUSTATUS = $2002
OAMADDR = $2003
; Don't worry about $2004; let OAM_DMA do the work for you.
PPUSCROLL = $2005
PPUADDR = $2006
PPUDATA = $2007

OAM_DMA = $4014
SNDCHN = $4015
P1 = $4016
P2 = $4017

KEY_A      = %10000000
KEY_B      = %01000000
KEY_SELECT = %00100000
KEY_START  = %00010000
KEY_UP     = %00001000
KEY_DOWN   = %00000100
KEY_LEFT   = %00000010
KEY_RIGHT  = %00000001
