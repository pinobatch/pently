;
; NES MMIO port definitions
;
; Copyright 2003-2016 Damian Yerrick
; 
; Permission is hereby granted, free of charge, to any person
; obtaining a copy of this software and associated documentation
; files (the "Software"), to deal in the Software without
; restriction, including without limitation the rights to use, copy,
; modify, merge, publish, distribute, sublicense, and/or sell copies
; of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
; 
; The above copyright notice and this permission notice shall be
; included in all copies or substantial portions of the Software.
; 
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
; THE SOFTWARE.
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
