Pently
======
This document describes Pently, the audio engine used in Pin Eight
NES games since 2009. 

Introduction
------------
Pently is a music and sound effect player code library for use in
games for the Nintendo Entertainment System written in assembly
language with ca65. It has seen use in NES games dating back to 2009,
including _Concentration Room_, _Thwaite_, _Zap Ruder_, the menu of
_Action 53_, _Double Action Blaster Guys_, _RHDE: Furniture Fight_,
and _Sliding Blaster_.

The name comes from Polish _pętla_ meaning a loop. It also reminds
one of Greek _πέντε (pénte)_ meaning "five", as it supports five
tracks (pulse 1, pulse 2, triangle, drums, and attack injection)
mapped onto the NES audio circuit's four tone generator channels. 

API
---
The following methods, declared in the assembly language include file
_pently.inc_, make up the public API:

* `pently_init` initializes all sound channels. Call this at the
  start of a program or as a "panic button" before entering a long
  stretch of code where you don't call `pently_update`.
* `pently_update` updates the sound channels. Call this once each
  frame.
* `pently_start_music` starts a song in `pently_songs`.  The value
  in register A chooses which song.
* `pently_stop_music` stops the song, allowing sound effects to
  continue.
* `pently_resume_music` resumes the playing song. If this is called
  before `pently_start_music` or after a song stops, the behavior is
  undefined.
* `pently_play_note` plays the note with pitch A (0 to 63) on channel
  X (0, 4, 8, 12, or 16) with instrument Y from `pently_instruments`.  
* `getTVSystem`, defined in `paldetect.s`, waits for two NMIs and
  counts the time between them to determine which TV system is in
  use.  It returns a region value in A: 0 means NTSC, 1 means PAL
  NES, and 2 means PAL famiclones such as Dendy.  Make sure your NMI
  handler finishes within 1500 cycles (not taking the whole vertical
  blanking period or waiting for sprite 0) while calling this, or the
  result will be wrong.  
* `pently_get_beat_fraction`, defined in `bpmmath.s`, reads the
  fraction of the current beat. Returns a value from 0 to 95 in A.

Your makefile will need to assemble `pentlysound.s`, `pentlymusic.s`,
and `musicseq.s`, and link them into your program.  If using
`getTVSystem`, additionally assemble `paldetect.s`.  If using
`pently_get_beat_fraction`, additionally assemble `math.s` and
`bpmmath.s`.  If not generating into the period table into
`musicseq.s`, additionally assemble `ntscPeriods.s`.

The file `musicseq.s` contains the sound effects, instruments, songs,
and patterns that you define.  It should `.include "pentlyseq.inc"`
to use the macros described below.  For those familiar with Music
Macro Language (MML) or LilyPond, the distribution includes a
processor for an MML-like music description language.
(For more information, see [pentlyas.md].)

### Configuration

The file `pentlyconfig.inc` contains symbol definitions that enable  
or disable certain features of Pently that take more ROM space or
require particular support from the host program.  A project using a
feature can enable it by setting the symbol associated with the
feature to a nonzero number (`PENTLY_USE_this = 1`).  A project not
using a feature, especially an NROM-128 project in which ROM space is
at a premium, can turn it off by setting its symbol to zero
(`PENTLY_USE_this = 0`).

If `PENTLY_USE_ROW_CALLBACK` is enabled, the main program must
`.export` two callback functions: `pently_row_callback` and
`pently_dalsegno_callback`.  These are called before each row is
processed and when a `dalSegno` or `fine` command is processed,
respectively.  They can be useful for synchronizing animations to
music.  For `pently_dalsegno_callback`, carry is clear at the end of
a track or set if looping.

If `PENTLY_USE_PAL_ADJUST` is enabled, Pently will attempt to correct
tempo and pitch for PAL machines.  The main program must `.export` a
1-byte RAM variable called `tvSystem` and store a region code from
0 to 2, as described above.  Typical use is as follows:

    jsr getTVSystem
    sta tvSystem

Disabling `PENTLY_USE_ARPEGGIO` saves about 60 bytes, and disabling
`PENTLY_USE_VIBRATO` saves about 150.

Pitch
-----
Pently expresses pitch in terms of a built-in table of wave periods
in [equal temperament], sometimes called 12edo.  The following values
are valid for the square wave channels; the triangle wave channel
always plays one octave lower.  By default, the player compensates
for the PAL NES's slower APU based on bit 0 of `tvSystem`.

Because of the NES's limited precision for wave period values, note
frequencies become less precise at high pitches.  These frequencies
apply to NTSC playback:

Value | Name    | Frequency (Hz)
----- | ------- | --------------
0     | A1      | 55.0
1     | A#1/B♭1 | 58.3
2     | B1      | 61.7
3     | C2      | 65.4
4     | C#2/D♭2 | 69.3
5     | D2      | 73.4
6     | D#2/E♭2 | 77.8
7     | E2      | 82.4
8     | F2      | 87.3
9     | F#2/G♭2 | 92.5
10    | G2      | 98.0
11    | G#2/A♭2 | 103.9
12    | A2      | 110.0
13    | A#2/B♭2 | 116.5
14    | B2      | 123.5
15    | C3      | 130.8
16    | C#3/D♭3 | 138.6
17    | D3      | 146.8
18    | D#3/E♭3 | 155.6
19    | E3      | 164.7
20    | F3      | 174.5
21    | F#3/G♭3 | 184.9
22    | G3      | 195.9
23    | G#3/A♭3 | 207.5
24    | A3      | 220.2
25    | A#3/B♭3 | 233.0
26    | B3      | 246.9
27    | C4 (middle C) | 261.4
28    | C#4/D♭4 | 276.9
29    | D4      | 293.6
30    | D#4/E♭4 | 310.7
31    | E4      | 330.0
32    | F4      | 349.6
33    | F#4/G♭4 | 370.4
34    | G4      | 392.5
35    | G#4/A♭4 | 415.8
36    | A4      | 440.4
37    | A#4/B♭4 | 466.1
38    | B4      | 495.0
39    | C5      | 522.7
40    | C#5/D♭5 | 553.8
41    | D5      | 588.7
42    | D#5/E♭5 | 621.4
43    | E5      | 658.0
44    | F5      | 699.1
45    | F#5/G♭5 | 740.8
46    | G5      | 782.2
47    | G#5/A♭5 | 828.6
48    | A5      | 880.8
49    | A#5/B♭5 | 932.2
50    | B5      | 989.9
51    | C6      | 1045.4
52    | C#6/D♭6 | 1107.5
53    | D6      | 1177.5
54    | D#6/E♭6 | 1242.9
55    | E6      | 1316.0
56    | F6      | 1398.3
57    | F#6/G♭6 | 1471.9
58    | G6      | 1575.5
59    | G#6/A♭6 | 1669.6
60    | A6      | 1747.8
61    | A#6/B♭6 | 1864.3
62    | B6      | 1962.5
63    | C7      | 2110.6

The pitch table `ntscPeriods.s` is generated with
`pentlyas.py --periods 64 -o ntscPeriods.s`.  To make another octave
above these notes available, you can change the 64 to 76, though that
range begins to fall out of tune due to limited period precision.

[equal temperament]: https://en.wikipedia.org/wiki/Equal_temperament

The parts of music
------------------
You can define music for Pently through `pentlyas.py`, through a
converter such as NovaSquirrel's `ft2pently`, or by just entering
Pently bytecode as described in [pently_bytecode.md].  But before
you do, it helps to understand the way Pently represents music.

### Sound effects

At any moment, the mixer chooses to play either the music or the
sound effect based on whatever is louder on each channel.  If there
is already a sound effect playing on the first square wave channel,
another sound effect played at the same time will automatically be
moved to the second, but a sound effect for the triangle or noise
channel will not be moved. A sound effect will never interrupt
another sound effect that has more frames remaining.

There can be up to 64 different sound effects.

### Instruments

Each instrument defines an envelope, which determines the volume and
timbre of an instrument over time.  We take a cue from the Roland
D-50 and D-550 synthesizers that a note's attack is the hardest thing
to synthesize.  An instrument for the D-50 can play a PCM sample to
sweeten the attack and leave the decay, sustain, and release to a
subtractive synthesizer.  Likewise in Pently, an envelope has two
parts: attack and sustain.

An attack is like a short sound effect that specifies the timbre,
volume, and pitch for the first few frames of a note.  It's analogous
to the duty, volume, and arpeggio envelopes in FamiTracker, but in a
compact format similar to that of sound effects.  After the attack
finishes, the channel continues into the sustain.  The timbre and
initial volume of the channel are set, and then the volume gradually
decreases if desired.

The drum track uses a different kind of instrument.  Each drum
specifies one or two sound effects to be played.  A common pattern is
for a kick or snare drum to have a triangle component and a noise
component, each represented as its own sound effect.

The fifth track can only play attacks, not sustains.  It plays them
on top of the pulse 1, pulse 2, or triangle channel, replacing the
attack phase of that channel's instrument (if any).  This is useful
for playing staccato notes on top of something else, interrupting the
notes much like sound effects do.

There can be up to 51 instruments and 25 drums in `musicseq.s`.

### Conductor track

The conductor track determines which patterns are played when, how
fast and high to play them, and how much of the song to repeat when
reaching the end.  This is the rough equivalent of an "order table"
in a tracker, also incorporating some functions of the "conductor
track" in a MIDI sequencer.

### Patterns

A pattern represents a musical phrase as a sequence of notes with
durations.  Unlike in traditional trackers, patterns can be any
length, with a shorter pattern on one track looping while a longer
pattern on another track plays.  In addition, a pattern can start at
any time, allowing the same pattern to be offset between one track
and another to create single- or dual-channel echo.

Only one note can be played on a single track at once; playing a
note cuts the one already playing.  To play more than one note on
a single channel, use arpeggio or the attack track.

In addition to notes and rests, patterns can also contain effects:

* Change to a different instrument for following notes.
* Legato, or slur, is changing an existing note's pitch rather than
  restarting the note's envelope.  It simulates an untongued note on
  a wind instrument or hammer-ons and pull-offs (HOPO) on a string
  instrument.
* Arpeggio is rapid alternation among two or three pitches to produce
  a warbly chord. It's heard often in European chiptunes.  
* Vibrato, or pitch modulation, is a subtle pitch slide up and down
  while a note is held.  It can make certain instruments sound
  thicker.
* Grace note allows stuffing two notes or rests in one row,
  specifying the length of the first in frames and giving the rest
  of the row to the second.  This may be used for acciaccatura
  or triplets.
  
Legato, arpeggio, and vibrato apply only to the pulse and triangle
channels, not the drum or attack track.

An arpeggio value specifies two intervals in semitones above a note's
base pitch, each expressed as a hexadecimal nibble, where `1` through
`9` represent a minor second through a major sixth and `A` through
`F` a minor seventh through a minor tenth.  Arpeggio doesn't work in
the attack track, and an arpeggio involving both a base note below
middle C and an interval below an octave tends to sound muddy.
Examples of musically useful arpeggio values follow:

Value | Effect
----- | ------
`00`  | Turn off arpeggio
`30`  | Minor third
`40`  | Major third
`50`  | Perfect fourth
`60`  | Tritone
`70`  | Perfect fifth
`C0`  | Octave, equal amounts low and high
`0C`  | Octave, more low than high
`CC`  | Octave, more high than low
`37`  | Minor chord, root
`38`  | Major chord, first inversion
`47`  | Major chord, root
`49`  | Minor chord, first inversion
`57`  | Sus4 chord
`58`  | Minor chord, second inversion
`59`  | Major chord, second inversion

The vibrato rate is always 1 cycle per 12 frames, which means 5 Hz
on NTSC or 4.2 Hz on PAL. The first 12-frame cycle of a note is
played without modulation in order to establish the note's pitch.

Bugs and limits
---------------
No music engine is perfect for all projects.  These limits of Pently
may pose a problem for some projects:

* Though it's only 1.6 KiB and thus much smaller than the FamiTracker
  or NerdTracker II player, it may still take up too much space in a
  very tight NROM-128 game because it is not modularized to be built
  without some effects.  This feature is under development.  
* There is currently no way to split sequence data across multiple
  PRG ROM banks or stash it in CHR ROM (like in Galaxian).
* No pitch bends.
* No true echo buffer.
* No support for DPCM drums. This is a low priority because Pently
  is used in games that depend on controllers or raster effects
  incompatible with DPCM.  However, it won't interfere with your own
  sample player, which can be triggered from `pently_row_callback`.
* No support for Famicom expansion synths, such as Nintendo MMC5,
  Sunsoft 5B, and Konami VRC6 and VRC7.  This is a low priority for
  two reasons: the NES sold in English-speaking regions did not
  support expansion synths without modification, and no expansion
  synth has a CPLD replica as of 2016.
* Envelopes have no release phase; a note-off kills the note
  abruptly.
* No error checking for certain combinations that cause undefined
  behavior.
* No graphical editor, unless you count using FamiTracker and then
  converting it with NovaSquirrel's ft2pently.
* Limit of 51 instruments, 64 sound effects, 25 different drums, 128
  patterns, and 128 songs.
* The bottom octave of the 88-key piano is missing from the pulse
  channel and the top octave from the triangle channel, reflecting an
  NES limit.
* The row grid cannot be swung.
* Pently does not compose music for you.  Writing an improvisation
  engine that calls `pently_play_note` is left as an exercise.

License
-------
The Pently audio engine is distributed under the MIT License (Expat variant):

> Copyright 2010-2016 Damian Yerrick
> 
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
> 
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
> 
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.

This means that yes, you may use Pently in games that you are
selling on cartridge.  And no, you do not have to make your game
free software; this is not a copyleft.  If a game is distributed
with a manual, you may place the full notice in the manual so long
as the author is credited within the game.
