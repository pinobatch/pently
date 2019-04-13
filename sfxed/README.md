NES Sound Effect Editor
=======================

This program lets you create sound effects for the Nintendo
Entertainment System directly on the console with immediate feedback.

Controls
--------

Use with a standard controller:

* Control Pad: Move cursor
* A+Control Pad: Change value in cell
* B+Up/Down: Insert or delete rows
* B+Left/Right: Copy sound
* B+A: Play sound
* Start: Save to SRAM

The editor also works with a Super NES Mouse (Nintendo SNS-016) or
a Hyper Click mouse (Hyperkin M07208).  The mouse may be plugged into
controller port 1 or 2 of an NES/Super NES combo clone, a Super NES
controller to NES 7-pin adapter, or a Super NES controller to
Famicom DA15 expansion port adapter.  If a mouse is detected, its
port number is displayed at the bottom of the screen.

Mouse operation:

* Click arrow: Scroll by 1 line
* Click area between arrow and thumb: Scroll by 16 lines
* Drag thumb: Scroll by 1 line per 2 pixels
* Click in pattern: Place cursor
* Drag in pattern: Change value in cell
* Right-drag up or down: Insert or delete rows
* Right-drag left or right: Copy sound
* Left+Right buttons: Play sound
* Click port number: Change sensitivity (Nintendo only, not Hyperkin)

How to make a sound
-------------------

A sound can be played on the pulse, triangle, or noise channel.
The "rate" refers to how many frames (16.7 ms on NTSC or 20 ms on
PAL) make up each row.  Finally, a sound can be muted so that it
plays or doesn't play when you press B+A.

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

When you save, the editor writes both the raw sound data and a
human-readable form of the data to SRAM.  The resulting save file
is a plain text file in ASCII encoding with UNIX newlines and can
be opened with Notepad++ or any other standard text editor.

At the end of the file is the raw data encoded in hexadecimal form.
This includes each sound's sequence of pitches, each sound's mode
byte (rate and channel), and a CRC-16 value to detect corruption of
SRAM.  The editor reads this copy when it starts.

In addition, the save file includes the sounds in a form that can be
copied into a score for the Pently audio engine by Damian Yerrick.

    sfx sfxed_1 on pulse
      volume 10 10 10 10 10 10 10 10 10
      pitch e''' a'' d'' g' e''' a'' d'' g' c'
      timbre 2 2 2 2 2 2 2 2 2

The `volume` values are 0 to 15, representing volume for pulse and
noise or priority for triangle.

The `pitch` values for melodic sounds are in LilyPond's variant of
Helmholtz notation: `c` through `a` and `h` represent the octave
below middle C, and commas or apostrophes lower or raise the pitch
by one octave.  Noise `pitch` is numbers from 0 to 15 representing
values of $0F through $00 written to $400E.

The `timbre` values for pulse are 0, 1, or 2 for 1/8, 1/4, or 1/2
duty.  For noise, they are 0 for hiss or 1 for buzz.  Again,
triangle has no timbre selection.

A `rate` appears if greater than 1.

Known issues
------------

* Cannot save to SRAM with mouse.  Workaround: Plug the mouse into
  NES port 2 or the Famicom expansion port and press Start on
  controller 1 to save.
* Pitches between two semitones are not supported.
* Changing a sound to or from noise may produce unexpected pitches.

License
-----
Copyright © 2009-2019 Damian Yerrick.
Pently is free software, under the zlib License.
