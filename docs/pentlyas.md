This document describes Pently's text-based music description
language.  It should be straightforward for a user of LilyPond
notation software or MML tools such as PPMCK to pick up.

Invoking
========
The Pently assembler takes a music description file and produces an
assembly language file suitable for ca65.  Like other command-line
programs, it should be run from a Terminal or Command Prompt.
Double-clicking it in Finder or File Explorer won't do anything
useful.

Usage:

    pentlyas.py [-h] [-o OUTFILENAME] [--periods NUMSEMITONES]
                [--period-region {dendy,ntsc,pal}]
                [infilename]

Arguments:

* `infilename`  
  Music file to process or `-` for standard input; omit for period
  table only.
* `-o OUTFILENAME`  
  Write output to a file instead of standard output.
* `--periods NUMSEMITONES`  
  Include an equal-temperament period table in the output;
  `NUMSEMITONES` is usually 64 to 80.
* `--period-region {dendy,ntsc,pal}`  
  Make period table for this region (default: `ntsc`).

Overall structure
=================
Indentation is not important.

A sound effect, drum, instrument, or pattern can be defined inside
or outside a song.  Sound effects, drums, instruments, and patterns
defined outside a song are called "global" can be used by any song
in the project.  Those defined inside a song are scoped to that song.

A **comment** consists of zero or more spaces, a number sign (`#`)
or two slashes (`//`), and the rest of the line.  The parser ignores
line comments.  A comment cannot follow other things on the same line
because a number sign outside a line comment means a note is sharp,
such as `c#`.

Defining pitches
================
Pently works by setting the period of a tone generator to periods
associated with musical pitches.  On the pulse and triangle channels,
both sound effects and musical notes are defined on a logarithmic
scale in units of semitones above 55 Hz.

The **note names** `c d e f g a b` refer to notes in the C major
scale, or 0, 2, 4, 5, 7, 9, and 11 semitones above the octave's base.

The meaning of `b` can be changed with the `notenames` option.  Both
`notenames english` and `notenames deutsch` allow `c d e f g a h`
for the C major scale. The difference is how they define `b`:
`english` makes it equal to `h`, while `deutsch` places it between
`a` and `h`, treating it as an H flat (or what English speakers would
call a B flat).  (The solfege-inspired names that LilyPond uses for
Catalan, Flemish, French, Portuguese, and Spanish are not supported
because of clashes with rest and length commands from MML.)

**Accidentals** add or subtract semitones from a note's pitch:

* Sharp (add a semitone): `a# a+ as ais`
* Flat (subtract a semitone): `ab a- aes`
* Double sharp: `ax a## a++ ass aisis`
* Double flat: `abb a-- aeses`

To specify **octave** changes:

* `>` before the note name or `'` after the note name and accidental
  goes up one octave.
* `<` before the note name or `,` after the note name and accidental
  goes down one octave.

A pitched sound effect or pattern can specify the octave of each
pitch by specifying an octave mode inside the pattern:

* `absolute` means that notes `c` through `h` fall in the octave
  below middle C.  The low octave is `c,` through `b,` or `<c`
  through `<b`, and middle C is `c'` or `>c`.  The lowest note that
  works on an NES is `a,,`, and the highest depends on the size of
  the period table.
* `orelative` assumes that an octave will be in the same octave as
  the previous note.  Octave changes persist onto later notes.
  This behavior is familiar to MML users.
* `relative` guesses the octave by trying to move no more than three
  note names up or down, ignoring accidentals.  A G major scale, for
  example, is `g a b c d e fis g`.  This means you don't need to
  indicate octaves after the first note unless you're leaping a fifth
  or more.  This behavior is familiar to LilyPond users.
  
In the `orelative` and `relative` modes, the "previous note" at the
start of a pattern is `f`, the F below middle C.

Sound effects
=============
Each sound effect has a name and channel type, such as
`sfx player_jump on pulse` or `sfx closed_hihat on noise`.

Envelopes
---------
The pitch, volume, and timbre may vary over the course of a sound
effect.  The available changes differ based on whether an effect is
for a `pulse`, `triangle`, or `noise` channel type.

**Pulse** pitch works as above, where `c'` represents middle C.
The `timbre` controls the duty cycle of the wave, where `timbre 0`
(12.5%) sounds thin, `timbre 1` (25%) sounds full, and `timbre 2`
(50%; default) sounds hollow.  The volume of each step of the
envelope can be set between 0 (silent) and 15 (maximum).  There are
two pulse channels (`pulse1` and `pulse2`), and sound effects for
pulse channels will play on whichever one isn't already in use.

**Triangle** pitch plays one octave lower than pulse: `c''` plays
a middle C.  It has no timbre control, and the volume control is
somewhat crippled: any volume greater than zero produces full power,
but it still determines priority when a note and sound effect are
played at once.

**Noise** pitches work differently.  There are only 16 different
pitches, numbered 0 to 15.  The timbre can be set to `timbre 0`
(hiss; default) or `timbre 1` (buzz), and `volume` behaves the same
as pulse.  In `timbre 0`, the top three pitches (13 to 15) sound the
same as 12 but quieter on authentic NES hardware.  They may sound
more problematic on clones and emulators.

The pitch and timbre in a sound effect may loop, but the volume
cannot, as it controls the length of the sound effect.  Place a
vertical line (`|`, Shift+backslash) before the part of the pitch or
timbre that you want to loop.  Otherwise, the last step is looped.

By default, a sound effect plays one step every frame, which is 60
steps per second.  But this can be slowed down with `rate 2` through
`rate 16`.

Examples:

    sfx closed_hihat on noise
    volume 4 2 2 1
    timbre | 0 1
    pitch 12
    
    sfx noise_kick on noise
    volume 10 10 8 6 4 3 2 1
    pitch 10 0

    sfx tri_kick on triangle
    volume 15 15 15 2 2
    pitch e' c' a f# e

Drums
-----
Even if you are making an NSF or a music-only ROM, sound effects are
used for percussion.  Each of up to 25 drums in the drum kit plays
one or two sound effects.  It's common on the NES to build drums
out of one noise effect, which has the noise channel to itself, and
one triangle effect, which interrupts the bass line on the triangle
channel.

The following sets up two drums, called `clhat` and `kick`.  The
former plays only one sound effect, the latter two.  

    drum clhat closed_hihat
    drum kick noise_kick tri_kick

Drum names must start and end with a letter or underscore (`_`) so
as not to be confused with a note duration.  Drums must not have the
same name as a pitch, which rules out things like `ass`.

Instruments
===========
Like sound effects, instruments are built out of envelopes.  They
have the same `volume` and `timbre` settings as pulse sound effects.
But their `pitch` settings differ: instead of being a list of
absolute pitches, they are a list of transpositions in semitones
relative to the note's own pitch.  For example, up a major third
is 4, while down a minor third is -3.  (They behave the same as an
"Absolute" arpeggio in FamiTracker.)  In addition, the `rate` command
is not recognized in an instrument.

The `timbre` of an instrument played on the triangle channel must be
2, or the note will cut prematurely.

On the last step of the volume envelope, the instrument enters
sustain.  (The portion envelope prior to sustain is called "attack".)
A sustaining note's timbre stays constant, its pitch returns to the
note's own pitch, and its volume stays constant or decreases linearly
over time.  (This means that steps in an instrument's `timbre` or
`pitch` envelope past the attack _will be ignored._)  The `decay`
command sets the rate of decrease in volume units per 16 frames, from
`decay 0` (no decrease; default) through `decay 1` (a slow fade) and
`decay 16` (much faster).

The `detached` attribute cuts the note half a row early, so that
notes don't run into each other.  This is especially useful with
envelopes that do not decay.

Example:

    # Not specifying anything will make an instrument with all
    # default settings: timbre 2, pitch 0, volume 8, decay 0,
    # and no detached
    instrument bass

    instrument flute
    timbre 2
    volume 3 6 7 7 6 6 5
    
    instrument piano
    timbre 2 1
    volume 11 9 8 8 7 7 6
    decay 1
    
    instrument banjo
    timbre 0
    volume 12 8 6 5 4 4 3 3 2
    decay 1
    
    instrument tub_bass
    timbre 1 1 2
    pitch 6 3 2 1 1 0
    volume 4
    decay 2
    
    # An instrument like this is useful for the attack track
    instrument one_frame_pop
    volume 8 0

Patterns
========
These are where the notes go.

A pattern contains a musical phrase that repeats until stopped.
A single pattern can be reused with different instruments or on
different channels (except noise vs. non-noise).

Pattern header
--------------
A **pattern** starts with `pattern some_name`.  Optionally a pattern
can have a default instrument: `pattern some_name with flute`.  The
compiler detects whether a pattern is a pitched pattern or a drum
pattern by whether the first note looks like a pitch or a drum name.

The `time` command sets the **time signature**, which controls
the number of beats per measure and the duration of one beat
as a fraction of a whole note, separated by a slash (`/`).  The
denominator (second number) must be a power of 2, no less than 2
and no greater than 64. For example, `time 2/4` puts two quarter
notes in each measure. The default is `time 4/4`, or common time.
A `time` numerator that is a multiple of 3 greater than 3, such as
6 or 9, triggers a special-case behavior for compound prolation,
making the beat three times as long.  For example, each measure in
`time 6/8` is two beats, each beat a dotted quarter note.
A few time signatures have shortcut notations:

* `time c` means `time 4/4` (common time).
* `time ¢` means `time 2/2` (cut time or alla breve).
* `time o` means `time 3/4` (perfect time).

The **`scale`** command sets what note value shall be used as a
_row_, the smallest unit of musical time in Pently.  It must be a
power of two, such as `scale 8`, which sets eighth notes as the
shortest duration, or `scale 32`, which sets thirty-seconds as the
shortest duration.  A larger `scale` will cause durations of 24 rows
or longer to use more bytes.  The default is `scale 16`.

Notes
-------
Each note command consists of up to five parts:

* Note name
* Accidentals (optional)
* Octave (optional)
* Duration (optional)
* Slur (optional)

For pitched patterns, the note name, accidentals, and octave are
specified the same way as for sound effects.  For drum patterns,
one of the names defined in a `drum` command is used instead.
These commands can be used instead of a note:

* `r` is a rest, which cuts the current note.
* `w` (wait) does not change the pitch or restart the note.
  This represents a note tied to the previous note.
* `l` (length) does not play a note or rest but sets the duration
  (see below) for subsequent notes, rests, and waits in a pattern
  that lack their own duration.

Note durations are fractions of a whole note, whose length depends
on the `scale`.  Recognized note durations include `1`, `2`, `4`,
`8`, `16`, and `32`, so long as it isn't shorter than one row.
Durations may be augmented by 50% or 75% by adding `.` or `..`
after the number.

Duration is optional for each note.  The `durations` command controls
how missing durations are assigned.  In `durations temporary`, as
in MML, numbers after a note change the duration only for that
note; only `l` commands affect later notes' implicit duration.
By contrast, `durations stick` means numbers after a note apply
to later notes in the pattern, as in LilyPond.  If the first note
lacks an explicit duration, its duration is one beat as defined
by `time`.  The default is `durations temporary`.

A note's duration can be set in frames (1/60 second) instead
of rows using the `g` (grace note) command, with the following
note taking the remainder of the row.  For example, `d4g e4 d2`
produces a short D, an E taking the remainder of the quarter note,
followed by a D half note.  Grace note durations never stick.

A note followed by a tilde `~` will not be retriggered but instead
will be slurred into the following note.  A note followed by a left
parenthesis `(` will be slurred into the following notes, and a note
followed by a right parenthesis `)` represents the end of such a
slurred group.  This is useful for tying notes together or producing
legato (HOPO).  Slurring into a note with the same pitch is the same
as a wait: `eb2~ eb8`, `eb2( eb8)`, and `eb2 w8` mean the same.

**TODO:** A future version of Pently may introduce a command to
modify durations in compound prolation for a swing feel.

**TODO:** A future version of Pently may introduce a command to
automatically introduce rests between notes for staccato feel.

**TODO:** A future version of Pently may introduce a command to
"bar check", or pad a pattern with rests or notes to the end of
a measure.

**TODO: Example of a pattern**

Pattern effects
---------------
To change the **instrument** within a pattern, use `@` followed
by the instrument name, such as `@piano`.  Notes before the first
change use the instrument specified in the song's play command.

**Arpeggio** is rapid alternation among two or three pitches to
create a warbly chord on one channel.  The `EN` command controls
arpeggio: `EN00` or `ENOF` turns it off, `EN04` sets it to a major
third interval (four semitones above the note), and `EN37` sets it
to a minor chord (three and seven semitones above the note).

**Vibrato** is a subtle pitch slide up and down while a note is held.
The `MP` (modulate period) command controls vibrato: `MP1` through
`MP4` set depth between 1 (very subtle) and 4 (very strong), and
`MP0` or `MPOF` disables it.  Only the depth can be controlled, not
the rate (which is fixed to a musically sane 12 frame period).

Songs
=====
Like patterns, songs also have `time` and `scale`.  They are used to
interpret the `tempo` and `at` commands.

Patterns may be defined inside or outside a song.  A pattern defined
inside a song inherits the song's `time` and `scale`.  If a pattern
is defined  outside a song, and its `scale` does not match that
of the song, it will be played with rows in all tracks the same
duration, which may not be what you want.

The **`tempo`** command tells how many beats are played per minute.
This can be a decimal, which will be rounded to the nearest whole
number of rows per minute.  For example, a song in `time 6/8` and
`scale 16` will have 6 rows per beat; `tempo 100.2` would then
map to 601.2 rows per minute, which is rounded to 601.  A tempo
that maps to more than 1500 rows per minute is forbidden because
it would cause a row to be shorter than two frames.

The **`at`** command waits for a `measure:beat:row` combination,
where measures and beats are numbered from 1 and rows from 0, before
processing the following command.  Row is optional; beat is also
optional if row is unspecified.  Any command may be specified on
the same line immediately following the timecor the following line.
As in Chinese films and Charles Stross novels, an `at` that goes
back in time is forbidden.

If a song begins on an upbeat, you can add a **`pickup`** measure.
The `pickup` command sets what the parser thinks is the current beat,
so that the `at` command knows how many rows to wait.  For example,
in a piece in 3/4 that starts on the third beat, use `pickup 0:3`,
where `0` means the measure preceding the first full measure, and
`3` means the third beat.

In addition to the tracks for pitched channels (`pulse1`, `pulse2`,
and `triangle`) and the drum track, Pently has an **attack track**
that interrupts a sustaining pitched note on another channel with an
attack envelope.  Like sound effects, the attack track uses illusory
continuity to increase the apparent polyphony.  An instrument played
on an attack track must have an attack phase.  (This means its
`volume` must be longer than one step because the last step belongs
to sustain, not attack.)  To select a channel for the attack track,
use `attack on pulse1`, `attack on pulse2`, or `attack on triangle`.
(There is no channel called `titan`.)  It's not recommended to use
attack on the same channel as the sound effects that make up drums.

The loop point is set with the **`segno`** (sen-yoh) command.  A song
ends with the **`fine`** (fee-neh) command, which stops playback, or
the **`dal segno`** command, which loops back to `segno` if it exists
or the beginning of the song otherwise.

To **play a pattern,** use `play pattern_name`.  Pitched patterns
default to the `pulse2` track; to specify another track, add
`on pulse1`, `on triangle`, or `on attack`.  Patterns can be played
with a particular instrument or transposed up or down a number of
semitones.  For example, transposing a pattern on `triangle` up
an octave (12 semitones) counteracts the channel's inherent
transposition.

    play melody_a with fiddle
    play bass_a on triangle up 12
    play melody_b with flute on pulse1 up 7

Drum patterns may be played only on the drum track and do not take a
`with` or `on` parameter.

A `play` command immediately replaces the pattern playing on a track.
To play one pattern after the other, use an `at` command to wait for
the pattern to end.  The pattern will loop until it is stopped or
another pattern is played on the same track.

To **stop the pattern** playing on a track, switch it to a built-in
silent pattern using `stop pulse1`, `stop pulse2`, `stop triangle`,
`stop drum`, or `stop attack`.  You can stop more than one track:

    stop pulse1 pulse2 drum

You can play a single pitch on a channel directly from the song:

    play 10 with crash_cymbal on noise
    play c#' with pad on pulse1

Unlike drum patterns, noise notes in the song use an instrument and
a pitch from 0 to 15.  They're good for crash cymbals and the like,
as they can be interrupted by other drums.  But make sure to play
single notes _after_ patterns in the same `at` block, or the
instrument may change unexpectedly.
  
Glossary
========
Many of the following terms will be familiar to somebody who has
studied music theory and MIDI.

* 2A03: An integrated circuit in the Nintendo Entertainment System
  Control Deck.  It consists of a second-source version of the
  MOS 6502 CPU, a DMA unit for the sprite display list, four tone
  generators, and a sampled audio playback unit.  Pently uses the
  CPU to send commands to the tone generators.
* 2A07: Variant of 2A03 used in the PAL NES sold in Europe.
* 6527P: Variant of 2A03 used in the Dendy famiclone sold in Russia.
* Attack: The beginning of an envelope.  It consists of all volume
  envelope steps except the last.
* Bar: The line in musical notation that separates one measure from
  the next.  Can also mean a measure itself.
* Channel: An output device capable of playing one tone at once.
  The 2A03 contains four channels: `pulse1`, `pulse2`, `triangle`,
  and `noise`.
* Channel type: A set of channels with the same behavior.  The 2A03
  has three channel types: `pulse`, `triangle`, and `noise`.
* Drum: A sound effect played to express rhythm.  Usually represents
  unpitched percussion.
* Envelope: The change in pitch, volume, or timbre over the course
  of a single note or sound effect.
* Frame: The fundamental unit of time, on a scale comparable to the
  progress through an envelope, too fast for rhythmic significance.
  Like other NES music engines, Pently counts frames based on the
  vertical retrace of the picture generator.  An NTSC PPU produces
  60.1 frames per second, and a PAL PPU produces 50.0 frames per
  second.  This usually ends up assigning three to fifteen frames per
  row depending on the tempo and scale.
* HOPO: Instantaneous change in a note's pitch.  (After guitar
  techniques called "hammer-on" and "pull-off" that produce this.)
* Illusory continuity: The tendency of the human auditory system to
  fill in gaps in a continuous tone when these gaps coincide with
  another sufficiently loud tone or noise.
* Instrument: A set of pitch, volume, and timbre envelopes that is
  used to play notes.
* Note: A musical event with a pitch and a duration.
* Note value: A duration expressed as a binary fraction of a
  whole note.
* Octave: A frequency ratio of 2 to 1 between two pitches.
* Pattern: A musical phrase, consisting of a list of notes and rests.
* Pickup measure: A partial measure at the start of a piece of music.
  Also called "anacrusis".
* Pitch: The frequency of a tone expressed using a logarithmic scale.
* Pitched: Relating to a channel with a `pulse` or `triangle` type,
  which plays pitches rather than noise.
* Polyphony: Playing more than one note at once.
* Prolation: The division of a beat into two parts (simple) or
  three parts (compound).
* Rest: A musical event consisting of silence for a duration.
* Row: The shortest rhythmically significant duration in a piece of
  sequenced music.  Also called a subdivision, tick, or tatum (after
  American jazz pianist Art Tatum).
* Semitone: One-twelfth of an octave, or a frequency ratio of 1.0595
  (the twelfth root of 2) to 1 between pitches.
* Song: A piece of music, which plays patterns at various times.
* Sound effect: A set of pitch, volumes, and timbre envelopes
  without necessarily a definite pitch.
* Tempo: The speed at which music is played back, expressed in beats
  per minute.
* Timbre: The quality of a sound independent of its volume, pitch,
  or duration, and determined by its harmonic structure.
* Time signature: A fraction determining the number of beats in a
  measure and the note value corresponding to one beat.
* Track: A logical structure on which notes can be played.  Pently
  has five tracks: one for each pitched channel, one more that can
  replace the attack on a pitched channel's track, and a drum track.
* Upbeat: A beat other than a measure's first beat.
* Whole note: The name in American English, German, Greek, Japanese,
  and other languages for a note whose duration is that of a measure
  of common (4/4) time.  Also called "semibreve" in Italian and
  British English, or words meaning "round" in Catalan, French and
  Spanish.
