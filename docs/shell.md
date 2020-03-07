NES shell
=========

Pently compiles to, among other targets, an NES ROM.  It has
two screens:

Song selection screen
---------------------
This shows the `title` value for each song in the score, the size
of the driver with the options enabled in `pentlyconfig.inc`,
the size of instrument, song, and pattern data, and the current
and maximum CPU use for this song in cycles.

* Up, Down: Navigate to songs
* A: Go to visualization

If the score contains a `resume` command, playback starts from the
position where the command appears.  Otherwise, playback starts from
the beginning of the first song.

Visualization screen
--------------------
This shows the current song's title, its rehearsal marks, and a
visualization of all channels' state.

On the keyboard are red, green, and blue dots, representing
the target note for the pulse 1, pulse 2, and triangle tracks.
These are unaffected by pitch effects or drum and attack track
interruption.

Below the keyboard are symbols representing the state of each
hardware channel:

* Red square: Pitch and volume of pulse 1
* Green square: Pitch and volume of pulse 2
* Blue triangle: Pitch of triangle; hollow if an octave lower
* Small blue triangle: Effective pitch of 31st and 33rd harmonics
  caused by triangle's 4-bit resolution
* Dust cloud: Pitch of noise (based on buzz mode)

Pulse and triangle marks are white if overridden by the attack track.
Noise is gray in hiss mode (32767-step sequence) or yellow in buzz
mode (93-step sequence).

This screen also offers playback controls useful for rehearsal:

* Up: Seek to previous rehearsal mark
* Down: Seek to next rehearsal mark
* Left, Right: Switch between rehearsal mark navigation and track
  mute control
* A on track mute control: Mute or unmute this track
* A twice: Solo this track or unmute all
* Start: Pause or resume
* Start+Up/Down: Scale tempo to full, half, 1/4, or 1/8
* A while paused: Step one row
* B: Go to song selection

Full functionality of this screen requires enabling three features
not commonly enabled in games:

* If `PENTLY_USE_VARMIX` is off, muting will not work.
* If `PENTLY_USE_REHEARSE` is off, rehearsal marks, tempo scaling,
  and pause and step will not work.
* If `PENTLY_USE_VIS` is off, visualization will not appear.

If the score contains a `mute` or `solo` command, playback begins
with the specified tracks disabled or enabled.
