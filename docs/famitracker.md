Pently for FamiTracker users
============================

Some composers for Pently prefer to work in FamiTracker and convert
its text export to a Pently score using tools such as [ft2pently]
rather than working directly with the MML dialect in a Pently score.
Because Pently focuses more on small size than the replayer that
FamiTracker inserts into exported NSFs, its feature set differs
somewhat from that of FamiTracker.  So composers should be aware
of a few differences that affect how a converted score sounds.

Shared features
---------------
Pently includes counterparts to these [FamiTracker effects]:

* Channel volume changes (`4`, `8`, `C`, `F`)  
  Volumes are rounded to those four values.
* Arpeggio (`0xy`)
* Pitch slide to target note (`3xx`)
* Vibrato (`45x`)  
  Speed is treated as 5, and depth can be 1, 3, 5, or 7.
* Looping (`Bxx`)
* Halt (`Cxx`)
* Pattern truncation (`D00`)
* Tempo (`Fxx`)

It also allows multiple note-column events per row, from which
these can be built:

* Delayed note (`Gxx`)  
  Becomes a wait then note, such as `w4g c'4`.
* Delayed note cut (`Sxx`)  
  Becomes a note or wait then rest, such as `c'4g r8`
* Start at one note and slide to another
  (`1xx`, `2xx`, `Qxy`, `Rxy`)  
  Becomes a note then a legato note played with pitch slide,
  such as `c'2g( EP17 d'4) EPOF`

Features not in Pently
----------------------
These FamiTracker features are currently unsupported, and
converters may warn about their use:

* Pitch and hi-pitch envelopes
* Looping envelopes
* Note release
* Melodies played with duty 1 (93-step) noise
* DPCM (which ft2pently translates to drums in your drum kit)
* Famicom expansion audio
* Tremolo (`7xy`)
* Volume slide (`Axy`)
* Jumping into the middle of a pattern (`Dxx` with `x` > 0)
* Speed 1 tracking (`F01`)
* Delays spanning more than a row (`Gxx` or `Sxx` with large `x`)
* 2A03 hardware sweep unit (`Hxy`, `Ixy`)
* Detune (`Pxx`)
* Timbre override (`Vxx`)

Nor are most features added in [0CC-FamiTracker] supported:

* Grooves (speed sequences)
* Detune settings other than global tuning
* Arpeggio schemes other than `| 0 x`, `| 0 0 x x`, `| 0 x y`, and
  `| 0 0 x x y y`

Features not in FamiTracker
---------------------------
One can compose in FamiTracker, convert a text export to a Pently
score, and use that directly.  This process won't allow use of these
Pently features, many of which would fit a song in less ROM space.

* Grace notes  
  Play a note, wait a fraction of a row, then play another note.
* Detached notes  
  An instrument can automatically cut notes a half row early.
* Half-speed arpeggios  
  Play each step of `0xy` for two frames instead of one, which makes
  harmonic chords less noisy.
* TB-303 style slides  
  The [Roland TB-303] Bass Line synthesizer has a "slide" feature
  that behaves as a low-pass filter on the pitch signal.  Because the
  rate of change of pitch at any given moment is proportional to the
  distance to the target pitch, it takes the same time to slide an
  octave as a single semitone.  Pently supports the same model.
* Shorter patterns  
  A short pattern is looped.  This can make a drum pattern or
  ostinato smaller.
* Longer patterns  
  A longer melody spanning several measures can be written as one
  pattern.  This avoids spending bytes on assigning and playing
  each 4-measure part of each pattern.
* Pattern transposition  
  A pattern can be played up or down a number of semitones.
  This allows key changes or ostinato reuse with no overhead.
* Pattern reuse across channels  
  You can play the same thing on different channels with different
  instruments at different transpositions, at the same time or
  different times.
* Pattern interruption  
  At any row, the conductor track can switch a channel to a new
  pattern and play it from the beginning.  This applies to each
  individual channel, not to all channels at once as `D00` does.
* Automatic 2-channel echo  
  Start your melody on pulse 2, then use "Pattern reuse" and "Pattern
  interruption" to start it 3 rows late on pulse 1 with a quieter
  instrument.
* Decay phase  
  If the timbre and pitch remain constant while the volume steadily
  decreases at the end of an envelope, the instrument can compress
  the tail end to nothing.
* Attack track  
  Play an ostinato with a staccato instrument overlaid on the
  harmony on the same channel.  Or play a staccato melody or
  countermelody over arpeggiated pad chords.  This can substitute
  for the MMC5 expansion in some cases, and one converter maps
  the MMC5's pulse channel to this track.
* Drum interruption  
  Each drum consists of one or two "sound effects", which amount to
  notes with fixed arpeggio envelopes played on a particular channel.
  It's common to make a kick or snare drum from a noise sound effect
  and a triangle sound effect.  When a sound effect and a note play
  at once on the channel, greater volume wins.  This allows, for
  example, the triangle part of a drum to play slightly longer when
  bass is silent.

Features that may not be converted
----------------------------------
Pently and FamiTracker both support some features, but the underlying
data models differ so much that an automatic converter may not
translate everything.

* Fixed arpeggio envelopes  
  Use drums instead.  Track in DPCM, then map pitches to your Pently
  drum kit in the module comments.
* Pitch slides and vibrato  
  FamiTracker traditionally measures pitch slide rate and vibrato
  depth in frequency or period units of the underlying chip, causing
  vibrato to be weaker and pitch slides slower at some pitches than
  others.  0CC-FamiTracker optionally uses a "linear pitch" model
  that divides each semitone into 32 steps.  Pently also uses
  linear pitch.  If you export from FamiTracker 0.4.6 or from
  0CC-FamiTracker with linear pitch turned off, slides well above
  `A-2` will play slower and slides well below `A-2` faster.
* Half-speed arpeggio  
  Pently supports full-speed (60 Hz) and half-speed (30 Hz) `0xy`
  arpeggios, which correspond to 0CC-FamiTracker arpeggio schemes
  `| 0 x y` and `| 0 0 x x y y`.  But these are selected as an
  effect, not as part of an instrument.
* Rows per beat  
  FamiTracker saves how many rows make up one beat, calling it a
  song's "row highlight".  Pently also tracks rows per beat if
  the BPM math flag is enabled, so that animations in a rhythm
  game or cut scene can be synchronized to the music.  But because
  FamiTracker's [text export format] doesn't include row highlight,
  converters will likely write the default value of 4 to the score
  instead of the true value for the song's time signature.

Workflow implications
---------------------
To take full advantage of these features, a composer can prototype in
FamiTracker, run the converter, and polish the result.  This Pently
score then becomes the [single source of truth], or the authoritative
version from which the entire sound team works.  And because it is
text, it works well with the [diff] utility and [version control]
systems such as Git.

On the one hand, use of a Pently score as authoritative may cause
problems for composers who work only in trackers.  On the other hand,
composers fluent in MML or LilyPond may be attracted to the model.


[ft2pently]: https://github.com/NovaSquirrel/ft2pently
[FamiTracker effects]: http://famitracker.com/wiki/index.php?title=Effect_list
[0CC-FamiTracker]: https://github.com/HertzDevil/0CC-FamiTracker
[Roland TB-303]: https://en.wikipedia.org/wiki/Roland_TB-303
[text export format]: https://github.com/HertzDevil/famitracker-all/blob/master/hlp/text_export.htm
[single source of truth]: https://en.wikipedia.org/wiki/Single_source_of_truth
[diff]: https://en.wikipedia.org/wiki/Diff_utility
[version control]: https://en.wikipedia.org/wiki/Version_control
