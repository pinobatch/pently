Pently bytecode
===============
This document describes the format of the music data that Pently
reads.  Before Pently 0.05, specifying bytecode was the only way to
create music.  Since then, Pently's primary input format has changed
to an MML-like language processed by a Python program called
`pentlyas` (described in [pentlyas.md]), and NovaSquirrel has created
an experimental tool called [ft2pently] to convert FamiTracker music.

[ft2pently]: https://github.com/NovaSquirrel/ft2pently

Sound effects
-------------
Sound effects are defined in `pently_sfx_table` in `musicseq.s`.
Each is a call to the `sfxdef` macro giving a pointer to the sound
effect's data, the length in steps, how much to slow it down, and
which channel to play it on.

    sfxdef name, baseaddr, length, period, channel

* `name` is the name of the sound effect, used for
  `pently_start_sound` and `drumdef`. This value is exported.
* `baseaddr` is the starting address of sound effect data.
* `length` is the length in steps of sound effect data.
* `period` is the time in frames (1 to 16) to play each step of
  sound effect data.
* `channel` tells which channel type to play this sound effect on
  (0: pulse, 2: triangle, or 3: noise).

Sound effect data consists of a stream of two-byte steps, each
consisting of a duty/volume and a pitch value.  It may be played at
one entry per frame or more slowly for longer sound effects.  Volume
is in the range `$01` through `$0F`, and for square wave channels, it
can be OR'd with `$00` (1/8 duty, sharp), `$40` (1/4 duty, smooth),
or `$80` (1/2 duty, hollow).  For sound effects used on the triangle
wave channel, always use `$80` to keep the note from stopping early
due to interaction with the linear counter.  The noise channel
ignores duty, instead using the upper bit of pitch to determine the
type of sound.

Pitch on the square and triangle channels is specified in semitone
offsets from the lowest possible pitch (0, a low A). C is 3, 15, 27,
39, 51, or 63.  Triangle waves are always played an octave below
square waves; middle C is 27 on a square wave channel or 39 on a
triangle wave channel. Pitch on a noise channel is `$03` (highest) to
`$0F` (lowest) for ordinary noise or `$80` (highest) to $8F (lowest)
for metallic tones.  Values `$00` through `$02` are also valid, but
they sound identical to quieter versions of `$03`.

Instruments
-----------
Each instrument is defined by one line in `pently_instruments`:

    instdef name, duty, volume, decayrate, earlycut, attackptr, attacklen

* `name` is the name of the instrument, used for `pently_play_note`.
  This value is exported.
* `duty` controls width of pulse waves.  Options are `0` for 12.5%
  (sharp); `1` for 25% (smooth), or `2` for 50% (hollow).
  Instruments for the triangle channel MUST use 2.
* `volume` controls the starting volume of the sustain phase, from
  0 to 15.  Volume for the triangle channel is either off (0) or on
  (nonzero), but instrument volume still controls priority against
  sound effects.
* `decayrate` controls the rate of volume decrease in the sustain
  phase, in volume units per 16 frames.  Optional; defaults to 0.
* If `earlycut` is nonzero, the note shall be cut half a row before
  the next note.  This allows leaving space between notes if an
  instrument has no decay, especially on triangle.  Optional;
  defaults to 0.
* `attackptr` points to attack data. Optional; used only if
  `attacklen` is larger than 0.
* `attacklen` sets the length in steps of attack data.

Attack data differs from sound effects in three ways:

1. Instead of specifying an absolute pitch (as in FamiTracker's
   "Fixed" envelope), they specify a signed offset in semitones from
   the note's own pitch (as in FamiTracker "Absolute" envelope).
2. If bit 4 (`$10`) of the duty and volume byte is set, the pitch
   offset is omitted from the byte stream and treated as zero.
3. Attack data cannot be played slower than one step per frame.

Each drum is defined by one line in `pently_drums`:

    drumdef name, sfx1, sfx2

* `name` is the name of the drum.
* `sfx1` is an entry in `pently_sfx_table` to play when this drum is
  triggered.
* `sfx2` is an optional second entry in pently_sfx_table to play when
  this drum is triggered.

Conductor track
---------------
The `pently_songs` table contains `songdef` lines that associate a
song ID with a conductor track.

    songdef name, conductor_addr

* `name` is an identifier to pass to `pently_start_music`. Exported.
* `conductor_addr` is the address of the start of this song's
  conductor data.

Some examples of conductor patterns:

* `setTempo 288` sets the playback speed to 288 rows per minute.
  For example, this can represent 96 beats per minute where a beat is
  three rows, or 144 beats per minute where a beat is two rows.
  The speed defaults to 300 rows per minute and can be up to 2047
  rows per minute, enough for thirty-second-note resolution at up to
  255 quarter notes per minute.  The player automatically adjusts the
  playback speed based on the value of the tvSystem variable (zero:
  60.1 Hz, nonzero: 50 Hz).  However, values greater than 1500 may
  introduce playback issues.
* `playPatSq2 4, 27, FLUTE` plays pattern 4 on the second pulse wave
  channel (`Sq2` for "square 2"), transposed up 27 semitones (setting
  the base to middle C), with instrument `FLUTE`.
* `playPatTri 5, 15, 0` plays pattern 4 on the triangle wave channel
  (`Tri`), transposed up 15 semitones (base C3, two octaves below
  middle C), with instrument `BASS`.
* `noteOnNoise $05, CRASH` plays note $05 on the noise channel
  (`Noise`), with instrument `CRASH`.  Conductor notes always use the
  instrument system, not the sound effect system, even on the noise
  channel.  This is most useful for cymbals.
* `waitRows 48` waits 48 rows before processing the next command.
  Use this to allow patterns to play through.
* `fine` stops music playback. Use this at the end of a piece.
  (_Fine_, pronounced fee-neh, is Italian for "end".  In sheet music,
  it directs the performer to stop playing in a piece of ternary
  (A-B-A) form.  More generally, sheet music uses a "final barline"
  symbol 𝄂 to denote where a piece stops.) 
* `segno` sets a loop point.  (_Segno_, pronounced sen-yo, is Italian
  for "sign".  In sheet music, it refers to the symbol 𝄋 that marks
  the end of an introduction and the start of a large portion of a
  piece that should be repeated.)
* `dalSegno` rewinds playback to the most recently seen loop point.
  (_[Dal segno] (D.S.)_ is Italian for "from the sign".)  If no
  `segno` was seen, the position moves to the start of the piece;
  in music, this is called _[da capo]_ (from the head).
* `stopPatSq2` stops the pattern playing on the second square wave
  channel.  Patterns ordinarily loop when they reach the end, so
  you'll need to stop the pattern if you're not starting another
  while patterns continue on other tracks.
* `attackOnSq1` sets the attack track to use the first pulse channel.
* `setBeatDuration D_D8` sets the duration of one beat to a dotted
  eighth note (three rows).  The default is D_4, a quarter note (four
  rows).  This has no audible effect, but your `pently_row_callback`
  can see `pently_row_beat_part` and `pently_rows_per_beat` as a
  convenience to synchronize animations or DPCM samples to the music.

The transpose values are in semitones.  Pitch values such that the
value `N_C` in pattern code produces a C are 3, 15, 27, and 39.
For example, with transpose 15 on a square wave channel or 27 on a
triangle wave channel, `N_CH` produces a middle C and `N_C` produces
the C an octave below it.  Other values produce transpositions that
can prove useful for fitting a melody into the two-octave range of
a single pattern.  The drum track ignores both `transpose` and
`instrument`.

The list of all conductor commands defined in `pentlyseq.inc`
follows.  Their meaning should ideally be self-explanatory given
the above descriptions.

* Play pattern: `playPatSq1`, `playPatSq2`, `playPatTri`,
  `playPatNoise`, `playPatAttack`
* Stop pattern: `stopPatSq1`, `stopPatSq2`, `stopPatTri`,
  `stopPatNoise`, `stopPatAttack`
* Play note on pattern: `noteOnSq1`, `noteOnSq2`, `noteOnTri`,
  `noteOnNoise`, `noteOnAttack`
* Set channel for attack track: `attackOnSq1`, `attackOnSq2`,
  `attackOnTri`
* Loop control: `fine`, `segno`, `dalSegno`
* Timing control: `setTempo`, `setBeatDuration`, `waitRows`

[Dal segno]: https://en.wikipedia.org/wiki/Dal_Segno
[da capo]: https://en.wikipedia.org/wiki/Da_capo

Patterns
--------
Patterns are listed below `pently_patterns`:

    patdef name, patdata_addr

* `name` is an identifier to pass to playPat commands.
* `patdata_addr` is the address of the start of this pattern's data.

Each note's pitch is relative to the transposition base in the `playPat` command in the conductor track.
  
Code             | Note       | Interval name  | Semitones
---------------- | ---------- | -------------- | --------:
`N_C`            | C          | Unison         | 0
`N_CS`, `N_DB`   | C#/D♭            | Minor second   | 1
`N_D`            | D          | Major second   | 2
`N_DS`, `N_EB`   | D#/E♭            | Minor third    | 3
`N_E`            | E          | Major third    | 4
`N_F`            | F          | Perfect fourth | 5
`N_FS`, `N_GB`   | F#/G♭            | Tritone        | 6
`N_G`            | G          | Perfect fifth  | 7
`N_GS`, `N_AB`   | G#/A♭            | Minor sixth    | 8
`N_A`            | A          | Major sixth    | 9
`N_AS`, `N_BB`   | A#/B♭            | Minor seventh  | 10
`N_B`            | B          | Major seventh  | 11
`N_CH`           | High C     | Octave         | 12
`N_CSH`, `N_DBH` | High C#/D♭ |                | 13
`N_DH`           | High D     |                | 14
`N_DSH`, `N_EBH` | High D#/E♭ |                | 15
`N_EH`           | High E     |                | 16
`N_FH`           | High F     |                | 17
`N_FSH`, `N_GBH` | High F#/G♭ |                | 18
`N_GH`           | High G     |                | 19
`N_GSH`, `N_ABH` | High G#/A♭ |                | 20
`N_AH`           | High A     |                | 21
`N_ASH`, `N_BBH` | High A#/B♭ |                | 22
`N_BH`           | High B     |                | 23
`N_CHH`          | Top C      | Two octaves    | 24

(The "Note" column above assumes the transposition base is a C.)

To stop a note without playing another, use a `REST`.  This makes
sense only on pulse or triangle channels and is treated the same as
a tie on the drum or attack track.

Each note or rest is OR'd with a duration, or the number of rows to
wait after the note is played.  The durations are in fractions of
a 16-row "[whole note]", following standard practice for describing
durations in U.S. and Canadian English, most other Germanic
languages, Chinese, and Greek.  Available durations are 𝅘𝅥𝅯 sixteenth
(default, 1 row), 𝅘𝅥𝅮 eighth (`|D_8`, 2 rows), 𝅘𝅥 quarter (`|D_4`,
4 rows), 𝅗𝅥 half (`|D_2`, 8 rows), and 𝅝 whole (`|D_1`, 2 rows).
Augmented (or "dotted") durations are 50 percent longer:
𝅘𝅥𝅮𝅭 dotted eighth (`|D_D8`, 3 rows), 𝅘𝅥𝅭 dotted quarter (`|D_D4`,
6 rows), and 𝅗𝅥𝅭 dotted half (`|D_D2`, 12 rows).  Not all durations
can be expressed with one byte, but anything up to 20 rows can be
made from two [tied] notes: a note with `D_4`, `D_2`, `D_D2`, or
`D_1` followed by `N_TIE`, `N_TIE|D_8`, or `N_TIE|D_D8`.

Note G played with each of 16 durations

Code                    | Duration name               | Length in rows
----------------------- | --------------------------- | -------------:
`N_G`                   | Sixteenth                   | 1
`N_G\|D_8`              | Eighth                      | 2
`N_G\|D_D8`             | Dotted eighth               | 3
`N_G\|D_4`              | Quarter                     | 4
`N_G\|D_4,N_TIE`        | Quarter + sixteenth         | 5
`N_G\|D_D4`             | Dotted quarter              | 6
`N_G\|D_4,N_TIE\|D_D8`  | Quarter + dotted eighth     | 7
`N_G\|D_2`              | Half                        | 8
`N_G\|D_2,N_TIE`        | Half + sixteenth            | 9
`N_G\|D_2,N_TIE\|D_8`   | Half + eighth               | 10
`N_G\|D_2,N_TIE\|D_D8`  | Half + dotted eighth        | 11
`N_G\|D_D2`             | Dotted half                 | 12
`N_G\|D_D2,N_TIE`       | Dotted half + sixteenth     | 13
`N_G\|D_D2,N_TIE\|D_8`  | Dotted half + eighth        | 14
`N_G\|D_D2,N_TIE\|D_D8` | Dotted half + dotted eighth | 15
`N_G\|D_1`              | Whole                       | 16

<!--
You are reading this in a text editor, not a Markdown processor.
The backslashes appear in the Code column above to tell the Markdown
processor on GitHub that the pipe (|) characters in the Code column
are not intended as table cell separators.  Remove the backslashes
before adding this code to your file, such as N_G|D_D2.
-->

[whole note]: https://en.wikipedia.org/wiki/Whole_note
[tied]: https://en.wikipedia.org/wiki/Tie_(music)

### Effects

A pattern can force a particular instrument to be used, such as when
a pattern alternates between instruments. For this, use `INSTRUMENT`
followed by the instrument's name, such as `INSTRUMENT,FLUTE`.

Legato skips the ordinary note-on process, instead changing the
pitch of an existing note on a pulse or triangle channel.
Instruments set to note-off a half row early will not do so when
legato is on.  To slur a set of notes, put `LEGATO_ON` after the
first and `LEGATO_OFF` after the last.

Arpeggio rapidly cycles a note among two or three different pitches,
which produces the warbly chords heard in SIDs and NSFs by European
composers. The arpeggio is specified as a hexadecimal number, similar
to that used with the `J47` effect in [S3M] or [IT] or the `047`
effect in [MOD], [XM], or FTM, with a first and second nibble
representing intervals in semitones.  For example, `ARPEGGIO,$47`
makes a major chord in root position including 4 semitones (a major
third) and 7 semitones (a perfect fifth) above the root note.

If the second nibble is 0, only two steps are used; otherwise, three
steps are used.  Thus there are three ways to make an interval of
two notes, depending on how much the lower or higher note should
dominate.  For example, with an octave `ARPEGGIO,$0C` is three steps
low, low, and high; `ARPEGGIO,$C0` is two steps low and high; and
`ARPEGGIO,$CC` is three steps low, high, and high.

Effects `FASTARP` and `SLOWARP` set arpeggio to change pitch every
frame or every 2 frames respectively.

The depth of vibrato can be set from off (`VIBRATO,0`) to subtle
(`VIBRATO,1`) through very strong (`VIBRATO,4`).  These correspond to
amplitudes of 0, 9, 18, 38, and 75 [cents].

The volume of an instrument's attack and sustain phases can be scaled
by channel volume, from 25% (`CHVOLUME,1`) to full (`CHVOLUME,4`;
default).  Drums are unaffected.

A pattern spanning more than two octaves needs to use the transpose
command, which changes the pitch of the rest of a pattern by a given
number of semitones.  For example, `TRANSPOSE,5` moves the rest of
the pattern up a perfect fourth.  `TRANSPOSE,<-12` moves down an
octave, with the `-` denoting negative and the `<` working around
ca65's lack of support for signed bytes.

The `GRACE` command shortens the next two rows to one row's length.
The next byte specifies the length in frames of the first note in
the pair.  Like the `EDx` command in MOD/XM, `SDx` in S3M/IT, or
`G0x` in FamiTracker, it's designed for making an [acciaccatura]
(grace note) or a set of triplets (3 notes in the time of 4).
For example, to play a short C note for 4 frames followed by a
B flat that is as long as a quarter note minus 4 frames, do this:
`GRACE,4,N_CH,N_BB|D_Q4`.

The bend command controls pitch bend, also called portamento or pitch
slide.  In `BEND,$xy`, `x` chooses the rate scale, and `y` chooses
the rate.  Because of the wide range of speeds expected of
portamento, Pently provides three rate scales:

* Rates $00-$0F  
  0 means snap immediately to the target pitch, while 1-F mean change
  the pitch by 1 to 15 semitones per frame.
* Rates $10-$1B  
  Fractional rates in 256ths of a semitone per frame, where $10 to
  $1B set the numerator to 4, 8, 12, 16, 24, 32, 48, 64, 96, 128,
  192, or 384.  This crosses a semitone in 64, 32, 21.3, 16, 10.7, 8,
  5.3, 4, 2.7, 2, 1.3, or 0.7 frames.
* Rates $20-$27  
  Constant-time slides, passing pitch through a first-order low-pass
  filter with a time constant (τ) of 2, 4, 8, 16, 32, 64, 128, or 256
  frames.  For example, with a time constant of 8 frames, the pitch
  changes by 1/8 of the remaining distance to the target pitch per
  frame, and it takes 8 frames to go about 1 - 1/e = 63% of the way
  to the target pitch.

Finally, to end the pattern, use `PATEND`.  This isn't strictly
necessary if a pattern is always interrupted at its end, but if it
isn't present, playback will [fall through] into the following
pattern.

The following are all the symbols that are valid in pattern code:

* Notes, low octave: `N_C`, `N_CS`, `N_D`, `N_DS`, `N_E`, `N_F`,
  `N_FS`, `N_G`, `N_GS`, `N_A`, `N_AS`, `N_B`
* Notes, high octave: `N_CH`, `N_CSH`, `N_DH`, `N_DSH`, `N_EH`,
  `N_FH`, `N_FSH`, `N_GH`, `N_GSH`, `N_AH`, `N_ASH`, `N_BH`
* Note, top of range: `N_CHH`
* Notes, enharmonic synonyms: `N_DB`, `N_EB`, `N_GB`, `N_AB`, `N_BB`,
  `N_DBH`, `N_EBH`, `N_GBH`, `N_ABH`, `N_BBH`
* Duration carriers that are not notes: `N_TIE`, `REST`
* Durations: `D_8` (2 rows), `D_D8` (3 rows), `D_4` (4 rows),
  `D_D4` (6 rows), `D_2` (8 rows), `D_D2` (12 rows), `D_1` (16 rows)
* Effects and controls: `INSTRUMENT,id`; `ARPEGGIO,$xy`; `LEGATO_ON`
  and `LEGATO_OFF`; `VIBRATO,depth`; `TRANSPOSE,interval`;
  `CHVOLUME,vol`; `BEND,type`; `FASTARP` and `SLOWARP`; and `PATEND`

[S3M]: https://en.wikipedia.org/wiki/S3M_(file_format)
[IT]: https://en.wikipedia.org/wiki/Impulse_Tracker
[MOD]: https://en.wikipedia.org/wiki/MOD_(file_format)
[XM]: https://en.wikipedia.org/wiki/FastTracker_2
[cents]: https://en.wikipedia.org/wiki/Cent_(music)
[acciaccatura]: https://en.wikipedia.org/wiki/Ornament_%28music%29#Acciaccatura
[fall through]: https://en.wikipedia.org/wiki/Switch_statement#Fallthrough

Low-level data formats
----------------------
If generating Pently bytecode without use of macros, the low-level
data formats accepted by Pently versions 3, 4, and 5 are as follows:

### Definition tables

`sfxdef` expands to 4 bytes: a 2-byte little-endian base address,
1 byte with channel in bits 3-2 and step period minus 1 in bits 7-4,
and 1 byte of length in steps.

`drumdef` expands to 2 bytes with sound effect IDs of the first and
second sound effects that make up this drum.  The second byte (and 
the second) may be $80 or greater for no second sound effect.

`instdef` expands to 5 bytes.  The first is duty in bits 7-6 and
volume in bits 3-0.  The second is the decay rate in volume units per
16 frames.  The third is attack length in steps in bits 6-0 and
early cut (1: enabled) in bit 7.  The next two are the address of
attack data, ignored if the attack's length is 0.

Song and pattern tables are lists of addresses.  The `songdef`
and `patdef` macros only create symbol names for their IDs.

### Conductor

* `0x pp tt ii`: On track `x`, play pattern `pp` with base note `tt`
  and instrument `ii`
* `20 rr`: Wait `rr + 1` rows
* `21`: Stop music and set tempo to 0
* `22`: Set loop point
* `23`: Jump to loop point
* `24+x` (4+): Set attack track to channel `x`
* `28+x nn ii` (4+): Play note `nn` on channel `x` with instrument `ii`
* `30+h ll`: Set tempo to `h * 256 + ll` rows per minute
* `38+d` (4+): Set beat duration to offset `d` in the duration table

### Patterns

For pattern bytes $00-$D7: Bits 7-3 are the relative semitone number
(0-24 for notes, 25 for tie, 26 for rest), and bits 2-0 are an index
into a duration table `[1, 2, 3, 4, 6, 8, 12, 16]`.

Pattern bytes $D8 and up set effects:

* `D8 ii` (3+): Set instrument to ii
* `D9 xy` (4+): Set arpeggio intervals to x and y semitones
* `DA` (3+): Disable legato
* `DB` (3+): Enable legato (do not retrigger notes)
* `DC tt` (4+): Add `tt` to track's base note
* `DD gg` (4+): Reduce duration of following note/rest to `gg` frames
* `DE dd` (4+): Set vibrato depth to dd
* `DF dd` (5): Set channel volume
* `E0 sd` (5): Set pitch bend style to s and depth to d
* `E2` (5): Update arpeggio every tick
* `E3` (5): Update arpeggio every second tick
* `FF`: Restart pattern from beginning

### Historical notes

- In Pently 2, the drum table did not exist.  The driver supported
  drums with one sound effect, but the only publicly released game
  with Pently 2 (_Concentration Room_) used no drums.
- Through Pently 3, `instdef` was 4 bytes:  duty and volume, decay
  rate, early cut enable, and an unused byte.  Attack was not
  supported.
- Through Pently 4, a zero pitch byte in attack data could not
  be elided.
