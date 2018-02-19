; mbyt.s
; Multibyte constant macro for ca65
;
; Copyright 2013 Damian Yerrick
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
.macro mbyt_hex2nibs highnib, lownib
.local highdig, lowdig
  ; "dec0de" the hex nibbles
  .if highnib >= 'A' && highnib <= 'F'
    highdig = highnib - 'A' + 10
  .elseif highnib >= 'a' && highnib <= 'f'
    highdig = highnib - 'a' + 10
  .elseif highnib >= '0' && highnib <= '9'
    highdig = highnib - '0'
  .endif
  .if lownib >= 'A' && lownib <= 'F'
    lowdig = lownib - 'A' + 10
  .elseif lownib >= 'a' && lownib <= 'f'
    lowdig = lownib - 'a' + 10
  .elseif lownib >= '0' && lownib <= '9'
    lowdig = lownib - '0'
  .endif
  .byte highdig * $10 + lowdig
  ;.out .sprintf(".byte %02x", highdig * $10 + lowdig)
.endmacro

.macro mbyt inbytes
  ; thanks to thefox who recommended .set
  .local pos, nib
  pos .set 0
  .repeat .strlen(inbytes)
    .if pos < .strlen(inbytes)
      nib .set .strat(inbytes, pos)
      ; these characters can be used as separators
      .if (nib = ' ' || nib = ',' || nib = '$' || nib = '_')
        pos .set pos + 1
      .else
        mbyt_hex2nibs nib, {.strat(inbytes, pos + 1)}
        pos .set pos + 2
      .endif
    .endif
  .endrepeat
.endmacro

; use it like this:
; mbyt "09F91102 9D74E35B D84156C5 635688C0"
