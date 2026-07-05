Comparing Pently to Rob Hubbard's driver
========================================

"How Rob Hubbard’s C64 Music Player Worked" by Luxocrates explains
how the pattern format in Rob Hubbard's sound driver for Commodore 64
works.  The 50-minute video is part of a series about backporting
Hubbard's score for the C64 port of *Commando* to Capcom's original
arcade game.

Here I compare and contrast the data format of Hubbard's driver as
described in the video to [Pently bytecode] and to well-known
sample-based tracker formats (collectively "[s3xmodit]")

Unlike s3xmodit, where each pattern covers all voices in parallel,
Hubbard's driver is like Pently and FamiTracker in that each voice
plays a separate pattern.  And unlike s3xmodit and FamiTracker, both
Hubbard's driver and Pently have patterns of arbitrary length that
do not have to start and end at the same time on all voices.

Hubbard's driver has a "track" (playlist of patterns) per SID voice,
and each pattern plays once to completion.  The song's overall loop
can desync.  Pently has a single conductor track where a play command
stops the pattern on a voice and replaces it with a looping pattern
with a starting instrument.  The overall loop point for the conductor
track is song-wide.  Both allow transposing a pattern.

Most notes in patterns in Hubbard's driver are two or three bytes:
a lead byte containing a 3-bit "type" and 5-bit length, an optional
effect byte, and a pitch in semitones.  Pently packs length and two
octaves of pitch into one byte, reserving values $C8 through $FE for
ties, rests, and effects.  Because of this two-octave range, songs
make heavier use of transposition than in Hubbard's driver.

Coincidentally, both Hubbard's driver and Pently use value $FF to end
a pattern and lack of $FF to mean a fallthrough, in which a pattern
includes the pattern stored after it.

The lead byte's length field in Hubbard's driver has 5 bits, where
values 0 to 31 mean 1 to 32 rows.  Each song has its own "time scale"
value corresponding to s3xmodit speed, controlling how many vblanks
each row lasts, shared among the three voices.  Pently's length
values 0 to 7 mean 1, 2, 3, 4, 6, 8, 12, and 16 rows, and additional
"tie" notes encode in-between lengths.  The conductor track sets
tempo in rows per minute, analogous to FamiTracker tempo and the
reciprocal of speed, at any point in a song.

Speed values in Hubbard's driver are whole numbers of video fields.
This can represent only a handful of tempos.  In the video,
Luxocrates uses Bresenham's line algorithm to adapt a song made for
the 50 Hz version of Rob's driver for an arcade machine with a
roughly 240 Hz time base.  This corresponds to s3xmodit tempo.  The
tempo system of Pently does something analogous to account for 50 Hz
PAL NES, 60 Hz NTSC NES, and the 125 Hz time base of S-Pently, with
no changes in song data.

Hubbard's driver releases notes one row before the next note or has
the next note replace its pitch.  This is selected based on bit 5 of
a note's lead byte, the legato bit.  Pently gives each instrument an
option to cut half a row early or not when legato is off, and it
has a pair of effects to turn legato on or off for following notes.
If legato is off, S-Pently waits one additional 125 Hz tick between
key off and key on; the NES version does not.

Bit 6 of the lead byte in Hubbard's driver a pitch byte does not
follow.  This can be a tie (if the previous note was legato) or a
rest (if not).  Pently treats pitch 25 as tie and 26 as rest.

Bit 7 of the lead byte in Hubbard's driver means an effect byte
follows.  (Luxocrates' video saves effects for a later episode.)
Pently effects are encoded as values $D8-$FE.


[How Rob Hubbard’s C64 Music Player Worked]: https://www.youtube.com/watch?v=1YWe811rehU
[Pently bytecode]: ./bytecode.md
[s3xmodit]: https://battleofthebits.com/lyceum/View/s3xmodit+(format)
