NES Sound Effect Editor
=======================

This program lets you create sound effects for the Nintendo
Entertainment System directly on the console with immediate feedback.

Controls
--------

You can use the editor with a standard controller or a Super NES
Mouse.  The mouse may be plugged into an NES/Super NES combo
clone, a Super NES controller to NES 7-pin adapter, or a Super NES
controller to Famicom DA15 expansion port adapter.  If a mouse was
detected, a notice will be displayed on the bottom of the screen.

Controller operation:

* Control Pad: Move cursor
* A+Control Pad: Change value in cell
* B+Up/Down: Insert or delete rows
* B+Left/Right: Copy sound
* B+A: Play sound
* Start: Save to SRAM

Mouse operation:

* Click arrow: Scroll by 1 line
* Click area between arrow and thumb: Scroll by 16 lines
* Drag thumb: Scroll by 1 line per 2 pixels
* Click in pattern: Place cursor
* Drag in pattern: Change value in cell
* Right-drag up or down: Insert or delete rows
* Right-drag left or right: Copy sound
* Left+Right buttons: Play sound

How to make a sound
-------------------

A sound can be played on the pulse, triangle, or noise channel.
The "rate" refers to how many frames (16.7 ms on NTSC or 20 ms on
PAL) make up each row.  Finally, a sound can be muted so that it
plays or doesn't play when you push B+A.

Each sound has up to 64 rows with three columns: pitch, volume,
and timbre.

The pitch for melodic channels (pulse and triangle) ranges from A-0
(lowest) to C-6 (highest).  Middle C is C-3 for Pulse and C-4 for
Noise.  The pitch of noise channels is the closest note to the pitch
that the buzz timbre would produce; hiss timbre has the same update
rate but is not as noticeably periodic.

Volume for pulse and noise can be 0 (silent) to 15 (full).  Volume
for triangle is either on (1-15) or off (0), but higher numbers
establish higher priority relative to notes when music is playing.

Timbre for pulse channels can be 1/8, 1/4, or 1/2 duty.  Timbre for
triangle channels is fixed: it's always triangle.  Timbre for noise
channels can be either hiss (32767-step pattern) or buzz (93-step
pattern).

Save file format
----------------

When you save, the editor writes both the raw sound data and an
assembly language form of the data to SRAM.

The assembly language form is intended for Damian Yerrick's sound
engine and consists of a sound lookup table with four entries, one
for each sound, followed by the raw sound data.  The lookup table
consists of the address of the sound data, followed by a mode byte,
followed by the number of rows in the sound.  The mode byte has the
following form:

    7654 3210
    |||| ||||  
    |||| ||++- Unused
    |||| ++--- 0: pulse; 2: triangle; 3: noise
    ++++------ Rate (number of frames per row) minus 1

Each row is 2 bytes: a duty/volume byte (for $4000, $4008, or $400C)
followed by a pitch byte.  For melodic sounds, the pitch byte is a
semitone number; for noise, it's a value to be written directly to
$400F with timbre in bit 7 and period in bits 3-0.  Silent rows are
omitted from the assembly language.

At the bottom of the .sav file is a second copy with just the hex
nibbles of the mode bytes, which is what the editor actually loads
when it starts.  It consists of all rows for each sound, followed
by a mode byte for each sound, and finally a CRC-16 to detect
corruption of SRAM.

Known issues
------------

* Cannot save to SRAM with mouse.  Workaround: Plug the mouse into
  NES port 2 or the Famicom expansion port and press Start on
  controller 1 to save.
* A-0 and A#0 notes on triangle aren't always played.
* Pitches between two semitones are not supported.
* Some versions of the sound engine require bit 7 of the duty/volume
  byte to be set for each row of a triangle sound.  If you save
  something as triangle and then change it to pulse, its duty will
  be all 1/2.

Legal
-----

The program and its manual are distributed under the following terms:

Copyright 2014 Damian Yerrick

Copying and distribution of this file, with or without modification,
are permitted in any medium without royalty provided the copyright
notice and this notice are preserved.  This file is offered as-is,
without any warranty.
