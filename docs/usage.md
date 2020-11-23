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
`pently.inc`, make up the public API:

* `pently_init` initializes all sound channels. Call this at the
  start of a program or as a "panic button" before entering a long
  stretch of code where you don't call `pently_update`.
* `pently_update` updates the sound channels. Call this once each
  frame.
* `pently_start_sound` starts a sound effect in `pently_sfx_table`.
  The value in register A chooses which sound effect.
* `pently_start_music` starts a song in `pently_songs`.  The value
  in register A chooses which song.
* `pently_stop_music` stops the song, allowing sound effects to
  continue.
* `pently_resume_music` resumes the playing song. If this is called
  before `pently_start_music` or after a song stops, the behavior is
  undefined.
* `pently_play_note` plays the note with pitch A on channel X with
  instrument Y.  Pitch ranges from 0 to 63 (or more depending on the
  pitch table length); see "Pitch" below.  Channel is 0, 4, 8, 12,
  or 16, representing pulse 1, pulse 2, triangle, noise, and attack.
  Instrument is an element of the `pently_instruments` table.
* `pently_skip_to_row` skips to row X*256+A.  This row must be on
  or after the current position; otherwise, behavior is undefined.
  This method is available only if `PENTLY_USE_REHEARSE` is enabled.
* `getTVSystem`, defined in `paldetect.s`, waits for the PPU to
  stabilize and counts the time between vertical blanking periods
  to determine which TV system is in use.  It returns a region
  value in A: 0 means NTSC, 1 means PAL NES, and 2 means PAL
  famiclones such as [Dendy].  It should be called with NMI off
  and can replace the PPU wait spin loop in your game's init code.
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
Macro Language ([MML]) or [LilyPond], the distribution includes a
processor for an MML-like music description language described in 
[pentlyas.md].

[Dendy]: https://en.wikipedia.org/wiki/Dendy_(console)
[MML]: http://www.nullsleep.com/treasure/mck_guide/
[LilyPond]: http://lilypond.org/

### C language API

Some NES game developers use the cc65 compiler.  It requires all
assembly language symbols accessed from code in the C language to
begin with an underscore (`_`), and any function that takes more than
one argument receives its arguments on cc65's data stack.  Thus the
easiest subset of Pently to adapt are those that take one argument or
fewer:

    void __fastcall__ pently_init(void);
    void __fastcall__ pently_start_sound(unsigned char effect);
    void __fastcall__ pently_start_music(unsigned char song);
    void __fastcall__ pently_update(void);
    void __fastcall__ pently_stop_music(void);
    void __fastcall__ pently_resume_music(void);
    void __fastcall__ pently_skip_to_row(unsigned short row);

Pently has been used in at least one game written in the C language
and compiled with cc65.

### Reentrancy

Pently in general is not reentrant.  In particular, the NMI
handler must not call `pently_update` while `pently_start_sound`,
`pently_start_music`, `pently_play_note`, or `pently_skip_to_row`
is running in the main thread.  For workarounds, see [reentrancy.md].

Configuration
-------------
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

If `PENTLY_USE_SQUARE_POOLING` is enabled, Pently treats the pulse 1
and pulse 2 channels as a pool, and if pulse 1 is busy, it moves a
pulse sound effect to pulse 2 if pulse 2 is idle or has less sound
effect data left to play than pulse 1.  If this is disabled, it plays
all pulse sound effects on pulse 1.

If `PENTLY_USE_MUSIC_IF_LOUDER` is enabled, and a sound effect and
musical instrument are playing at the same time on the same channel,
Pently switches between the two frame by frame based on which is
louder.  This allows a loud note to cover up the long tail of a sound
effect or a triangle kick drum to stop sooner if a note is playing.
Turn this off to force a sound effect to silence notes on the same
channel for its entire duration.

If `PENTLY_USE_TRIANGLE_DUTY_FIX` is enabled, the triangle channel
behaves correctly no matter the timbre of the instrument or sound
effect played on it.  Otherwise, an instrument or sound effect
with timbre 0 or 1 will end prematurely.  To save about 10 bytes,
a program can disable this consistency check and ensure all
instruments and sound effects on triangle use timbre 2 or 3.

If `PENTLY_USE_NSF_SOUND_FX` is enabled, drums and other sound
effects are placed after music in the NSF's song order.

If `PENTLY_USE_REHEARSE` is enabled, seeking to a point in the song
is possible.  This is useful for creating rehearsal marks within a
song so that a composer can skip around or repeat a section.

If `PENTLY_USE_VIS` is enabled, Pently updates a bunch of public
variables based on the state of each channel, whose names start
with `pently_vis_`.  These are useful for building a visualizer.

If `PENTLY_USE_VARMIX` is enabled, setting bit 7 of
`pently_mute_track` for each track will turn all note-on commands
on that track into note-offs.  Use this when composing to hear a
part more clearly or in a game to make a [variable mix].

`PENTLY_INITIAL_4011` controls what's written to the DMC's value in
`pently_init`.  Because of nonlinearity in the NES's audio output,
this ends up controlling the balance between the pulse channels and
the triangle and noise channels.  Values range from 0 to 127, with
0 making triangle and noise the loudest.  Programs using the DMC
alongside Pently may want to set this to 64 or thereabouts.

Three options enable workarounds for issues caused by fractional
tempo by realigning the start of a tick and a row under certain
conditions.  `PENTLY_USE_TEMPO_ROUNDING_SEGNO` realigns at the loop
point, `PENTLY_USE_TEMPO_ROUNDING_PLAY_CH` realigns when a pattern is
played on one channel, and `PENTLY_USE_TEMPO_ROUNDING_BEAT` realigns
at the start of every beat.  (The last of these relies on BPM math.)

In addition, `pently_zptemp` needs to point at a 5-byte area of
zero page used as scratch space.  Set it in one of two ways:

    pently_zptemp = $00F0
    ; or ;
    .importzp pently_zptemp

If you use `.importzp`, you'll need to `.exportzp` in the file in
your main project that defines `pently_zptemp`.

### Reducing ROM size

Disabling some features frees up a few bytes of ROM and RAM.  This
can be important for size-constrained projects, such as those using
an NROM-128 board.  When multiple features share code, disabling them
all may reduce the code size by more than the sum of their parts.
Approximate savings follow:

Continuous pitch effects

* `PENTLY_USE_303_PORTAMENTO`  
  60 ROM bytes
* `PENTLY_USE_PORTAMENTO`  
  270 ROM bytes, 12 RAM bytes
* `PENTLY_USE_VIBRATO`  
  100 ROM bytes, 8 RAM bytes
* `PENTLY_USE_VIBRATO` and `PENTLY_USE_PORTAMENTO`  
  410 ROM bytes, 20 RAM bytes

Discrete pitch effects

* `PENTLY_USE_ARPEGGIO`  
  110 ROM bytes, 8 RAM bytes
* `PENTLY_USE_ATTACK_TRACK`  
  50 ROM bytes, 9 RAM bytes, 8 more if arpeggio also disabled
* `PENTLY_USE_ATTACK_PHASE`  
  150 ROM bytes, 12 zero page bytes; cannot be disabled
  while `PENTLY_USE_ATTACK_TRACK` is enabled
* `PENTLY_USE_ARPEGGIO` and `PENTLY_USE_ATTACK_PHASE`  
  281 ROM bytes, 8 RAM bytes

Other features that save substantial ROM bytes:

* `PENTLY_USE_CHANNEL_VOLUME`  
  60 ROM bytes, 4 RAM bytes
* `PENTLY_USE_BPMMATH`  
  30 ROM bytes, 2 RAM bytes
* `PENTLY_USE_TEMPO_ROUNDING_*`  
  56 ROM bytes

`PENTLY_USE_MUSIC = 0` builds only the sound effects portion with
no music support, such as for a tool to edit sound effects.  It is
intended that such a build not include `pentlymusic.s` at all.

Because fields associated with each channel are 4 bytes apart, the
allocation methods inside ca65 itself aren't ideal.  The program
`pentlybss.py` reads `pentlyconfig.inc`, decides which fields are
necessary for the enabled features, and allocates them.

[variable mix]: https://allthetropes.org/wiki/Variable_Mix

Pitch
-----
Pently expresses pitch in terms of a built-in table of wave periods
in [equal temperament], sometimes called "12edo" (12 equal divisions
of the octave).  The following values are valid for the pulse
channels; the triangle wave channel always plays one octave lower.
By default, the player compensates for the PAL NES's slower APU
based on bit 0 of `tvSystem`.

Because of the NES's limited precision for wave period values, note
frequencies become less precise at high pitches.  These frequencies
apply to NTSC playback:

Value | Name          | Frequency (Hz)
----- | ------------- | --------------
0     | A1            | 55.0
1     | A#1/B♭1       | 58.3
2     | B1            | 61.7 (PR)
3     | C2            | 65.4
4     | C#2/D♭2       | 69.3
5     | D2            | 73.4 (PR)
6     | D#2/E♭2       | 77.8
7     | E2            | 82.4
8     | F2            | 87.3 (PR)
9     | F#2/G♭2       | 92.5
10    | G2            | 98.0
11    | G#2/A♭2       | 103.9
12    | A2            | 110.0 (PR)
13    | A#2/B♭2       | 116.5
14    | B2            | 123.5
15    | C3            | 130.8
16    | C#3/D♭3       | 138.6
17    | D3            | 146.8 (PR)
18    | D#3/E♭3       | 155.6
19    | E3            | 164.7
20    | F3            | 174.5
21    | F#3/G♭3       | 184.9
22    | G3            | 195.9
23    | G#3/A♭3       | 207.5
24    | A3            | 220.2 (PR)
25    | A#3/B♭3       | 233.0
26    | B3            | 246.9
27    | C4 (middle C) | 261.4
28    | C#4/D♭4       | 276.9
29    | D4            | 293.6
30    | D#4/E♭4       | 310.7
31    | E4            | 330.0
32    | F4            | 349.6
33    | F#4/G♭4       | 370.4
34    | G4            | 392.5
35    | G#4/A♭4       | 415.8
36    | A4            | 440.4 (PR)
37    | A#4/B♭4       | 466.1
38    | B4            | 495.0
39    | C5            | 522.7
40    | C#5/D♭5       | 553.8
41    | D5            | 588.7
42    | D#5/E♭5       | 621.4
43    | E5            | 658.0
44    | F5            | 699.1
45    | F#5/G♭5       | 740.8
46    | G5            | 782.2
47    | G#5/A♭5       | 828.6
48    | A5            | 880.8
49    | A#5/B♭5       | 932.2
50    | B5            | 989.9
51    | C6            | 1045.4
52    | C#6/D♭6       | 1107.5
53    | D6            | 1177.5
54    | D#6/E♭6       | 1242.9
55    | E6            | 1316.0
56    | F6            | 1398.3
57    | F#6/G♭6       | 1471.9
58    | G6            | 1575.5
59    | G#6/A♭6       | 1669.6
60    | A6            | 1747.8
61    | A#6/B♭6       | 1864.3
62    | B6            | 1962.5
63    | C7            | 2110.6

Pitches marked (PR) are close to the CPU clock rate (1.79 MHz)
divided by a multiple of 4096.  Vibrato effects on a (PR) pitch
may produce audible jitter due to phase reset, a 2A03 quirk when
changing the most significant bits of a pulse channel's period.
The triangle channel is not affected.

The pitch table `ntscPeriods.s` is generated with
`pentlyas.py --periods 64 -o ntscPeriods.s`.  To make another octave
above these notes available, you can change the 64 to 76, though that
range is even farther out of tune.

[equal temperament]: https://en.wikipedia.org/wiki/Equal_temperament

The parts of music
------------------
You can define music for Pently through `pentlyas.py`, through a
converter such as NovaSquirrel's `ft2pently`, or by just entering
Pently bytecode as described in [pently_bytecode.md].  But before
you do, it helps to understand the way Pently represents music.

### Sound effects

There can be up to 64 different sound effects.  Each is a list of
(duty, volume, pitch) triples.

Each sound effect is specific to a particular type of channel (pulse,
triangle, or noise).  When a sound effect is played, it covers up
the musical note on the same channel.  It uses remaining length as a
rough priority scheme; a sound effect will never interrupt another
sound effect that has more frames remaining.

At any moment, the mixer chooses to play either the music or the
sound effect based on whatever is louder on each channel.  If a
sound effect is playing on pulse 1, another pulse sound effect
played at the same time will be moved to pulse 2, but a sound
effect for the triangle or noise channel will not be moved.
The `PENTLY_USE_SQUARE_POOLING` and `PENTLY_USE_MUSIC_IF_LOUDER`
configuration options change these behaviors.

### Instruments

Each instrument defines an envelope, which determines the volume
and timbre of an instrument over time.  We take a cue from the
Roland [D-50] and D-550 synthesizers that a note's attack is the
hardest thing to synthesize.  An instrument for the D-50 can play
a PCM sample to sweeten the attack and leave the decay, sustain,
and release to a subtractive synthesizer.  Likewise in Pently,
an envelope has two parts: attack and sustain.

An attack is like a short sound effect that specifies the timbre,
volume, and pitch for the first few frames of a note.  It's
analogous to the duty, volume, and arpeggio envelopes in FamiTracker,
but in a compact format similar to that of sound effects.
After the attack finishes, the channel continues into the sustain.
The timbre and initial volume of the channel are set, and then
the volume gradually decreases if desired.

The drum track uses a different kind of instrument.  Each drum
specifies one or two sound effects to be played.  A common pattern
is for a kick or snare drum to have a triangle component and a
noise component, each represented as its own sound effect.

The fifth track can only play attacks, not sustains.  It plays
them on top of the pulse 1, pulse 2, or triangle channel,
replacing the attack phase of that channel's instrument (if any).
This is useful for playing staccato notes on top of something
else, interrupting the notes much like sound effects do.

There can be up to 51 instruments and 25 drums in `musicseq.s`.

[D-50]: https://en.wikipedia.org/wiki/Roland_D-50

### Conductor track

The conductor track determines which patterns are played when, how
fast and high to play them, and how much of the song to repeat when
reaching the end.  This is the rough equivalent of an "order table"
in a tracker, also incorporating some functions of the "conductor
track" in a MIDI sequencer.

Pently measures tempo in rows per minute, not ticks per row as is
done in some other drivers.  Because ticks per row are rarely a whole
number, Pently uses an algorithm similar to Bresenham line drawing to
determine when to start the next row.  Every tick, it adds the tempo
to a counter modulo the number of ticks per minute, and a new row
begins when this counter wraps around.

However, this makes rows slightly uneven in length.  Repeated notes
on detached instruments make this difference particularly audible if
ticks per row are close to an odd number.  In addition, some NSF
players can detect a repeating song by comparing RAM contents to
earlier ticks, but variations in fractions of a tick can confuse loop
detection.  Configuration can enable one of three workarounds.

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
  a wind instrument or [hammer-ons] and pull-offs (HOPO) on a string
  instrument.
* Arpeggio is rapid alternation among two or three pitches to produce
  a warbly chord. It's heard often in European [SID] chiptunes.
* Vibrato, or pitch modulation, is a subtle pitch slide up and down
  while a note is held.  It can make certain instruments sound
  thicker.
* Grace note allows stuffing two notes or rests in one row,
  specifying the length of the first in frames and giving the rest
  of the row to the second.  This may be used for acciaccatura
  or triplets.
* Channel volume changes allow for dynamics without duplicating an
  instrument.
  
Legato, arpeggio, and vibrato apply only to the pulse and triangle
channels, not the drum or attack track.

An arpeggio value specifies two intervals in semitones above a note's
base pitch, each expressed as a hexadecimal nibble, where `1` through
`9` represent a minor second through a major sixth and `A` through
`F` a minor seventh through a minor tenth.  Arpeggio doesn't work in
the attack track, and an arpeggio involving both a base note below
middle C and an interval below an octave tends to sound muddy,
especially when played fast.  Examples of musically useful arpeggio
values follow:

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

The vibrato rate is always 1 cycle per 12 frames, which means 5 Hz on
NTSC or 4.2 Hz on PAL. The first 12-frame cycle of a note is played
without modulation in order to establish the note's pitch.  Four
depths are available, with an amplitude of 9, 19, 38, or 75 cents.
These correspond to amplitudes of 3, 6, 12, and 24 steps in
0CC-FamiTracker's "linear pitch" (32 steps per semitone) mode, or
roughly the effects `451`, `453`, `455`, and `457`.

Portamento approaches a pitch by sliding rather than an instant
change.  The rate of pitch change can be specified on one of three
scales: semitones per frame, predefined fractions of a semitone per
frame, or a fraction of the distance to the target pitch per frame.

[hammer-ons]: https://en.wikipedia.org/wiki/Hammer-on
[SID]: https://en.wikipedia.org/wiki/MOS_Technology_SID#Software_emulation

Bugs and limits
---------------
No music engine is perfect for all projects.  These limits of Pently
may pose a problem for some projects:

* Pently is 2 kB with all features on or 1.2 kB with all features
  off, which is much smaller than the FamiTracker or NerdTracker II
  player.  But even this may be too large for a very tight NROM-128
  game.
* No way to split sequence data across multiple PRG ROM banks
  or stash it in CHR ROM (like in _Galaxian_).
* No true echo buffer.
* No support for DPCM drums. This is a low priority because Pently
  is used in games that depend on controllers or raster effects
  incompatible with DPCM.  However, it won't interfere with your own
  sample player, which can be triggered from `pently_row_callback`.
* No support for Famicom expansion synths, such as Nintendo MMC5,
  Sunsoft 5B, Namco 163, and Konami VRC6 and VRC7.  This is a
  low priority for two reasons: the NES sold in English-speaking
  regions did not support expansion synths without modification,
  and none of the six expansion synths defined in NSF has a CPLD
  or MCU replica as of 2017.
* Envelopes have no release phase; a note-off kills the note
  abruptly.
* No error checking for obscure combinations that cause undefined
  behavior.
* No dedicated graphical editor, though FamiTracker with ft2pently
  can use much of Pently's functionality.
* Limit of 51 instruments, 64 sound effects, 25 different drums,
  255 patterns, and 128 songs.
* The bottom octave of the 88-key piano is missing from the pulse
  channel and the top octave from the triangle channel, reflecting
  an NES limit.
* No support for "grooves" as in 0CC-FamiTracker.  For example,
  the row grid cannot be swung.
* Pently does not [compose music for you].  Writing an improvisation
  engine that calls `pently_play_note` is left as an exercise.
* `pently_play_note` and `pently_get_beat_fraction` are not yet
  adapted to the cc65 C ABI.

[compose music for you]: https://en.wikipedia.org/wiki/Algorithmic_composition

License
-------
The Pently audio engine and its manual are distributed under the
zlib License, a non-copyleft free software license:

> Copyright 2010-2018 Damian Yerrick
> 
> This software is provided 'as-is', without any express or implied
> warranty.  In no event will the authors be held liable for any damages
> arising from the use of this software.
> 
> Permission is granted to anyone to use this software for any purpose,
> including commercial applications, and to alter it and redistribute it
> freely, subject to the following restrictions:
> 
> 1. The origin of this software must not be misrepresented; you must not
>    claim that you wrote the original software. If you use this software
>    in a product, an acknowledgment in the product documentation would be
>    appreciated but is not required.
> 2. Altered source versions must be plainly marked as such, and must not be
>    misrepresented as being the original software.
> 3. This notice may not be removed or altered from any source distribution.

tl;dr: Yes, you may use Pently in games that you sell on cartridge.
Please mention Pently in the credits if practical.
