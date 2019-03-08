#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Pently audio engine
# Music assembler
#
# Copyright 2015-2019 Damian Yerrick
# 
# This software is provided 'as-is', without any express or implied
# warranty.  In no event will the authors be held liable for any damages
# arising from the use of this software.
# 
# Permission is granted to anyone to use this software for any purpose,
# including commercial applications, and to alter it and redistribute it
# freely, subject to the following restrictions:
# 
# 1. The origin of this software must not be misrepresented; you must not
#    claim that you wrote the original software. If you use this software
#    in a product, an acknowledgment in the product documentation would be
#    appreciated but is not required.
# 2. Altered source versions must be plainly marked as such, and must not be
#    misrepresented as being the original software.
# 3. This notice may not be removed or altered from any source distribution.
#

from __future__ import with_statement, division, print_function
# The above features are available by default in Python 3, but
# declaring them anyway makes a cleaner error message on Python 2
# for Windows, which is the default IDLE on many Windows PCs
import os
import sys
import json
import re
import argparse
try:
    from collections import ChainMap
except ImportError:
    print("pentlyas.py: Python 3.3 or later is required", file=sys.stderr)

scaledegrees = {
    'c': 0, 'd': 1, 'e': 2, 'f': 3, 'g': 4, 'a': 5, 'h': 6, 'b': 6
}
notenamesemis = {
    'c': 0, 'd': 2, 'e': 4, 'f': 5, 'g': 7, 'a': 9, 'h': 11
}
accidentalmeanings = {
    '': 0, 'b': -1, 'bb': -2, '-': -1, '--': -2, 'es': -1, 'eses': -2,
    '#': 1, '##': 2, '+': 1, '++': 2, 's': 1, 'ss': 2, 'x': 2,
    'is': 1, 'isis': 2,
}
duraugmentnums = {
    '': 4, '.': 6, '..': 7, 'g': 0
}
dotted_names = {4: '', 6: 'dotted ', 7: 'double dotted '}
timesignames = {
    'c': (4, 4),  # common time
    '¢': (2, 2),  # cut time (you are encoding your file UTF-8 right?)
    'o': (3, 4),  # perfect time
}
channeltypes = {'pulse': 0, 'triangle': 2, 'noise': 3}
durcodes = {
    1: '0', 2: 'D_8', 3: 'D_D8', 4: 'D_4',
    6: 'D_D4', 8: 'D_2', 12: 'D_D2', 16: 'D_1'
}
volcodes = {
    # Musical names
    'pp': 1, 'mp': 2, 'mf': 3, 'ff': 4,
    # Names from https://en.wikipedia.org/wiki/Music_Macro_Language#Modern_MML
    'v1': 1, 'v2': 2, 'v3': 3, 'v4': 4,
}
pitched_tracks = {'pulse1': 0, 'pulse2': 1, 'triangle': 2, 'attack': 4}
track_suffixes = ['Sq1', 'Sq2', 'Tri', 'Noise', 'Attack']
pattern_pitchoffsets = [
    'N_C', 'N_CS', 'N_D', 'N_DS', 'N_E', 'N_F',
    'N_FS', 'N_G', 'N_GS', 'N_A', 'N_AS', 'N_B',
    'N_CH', 'N_CSH', 'N_DH', 'N_DSH', 'N_EH', 'N_FH',
    'N_FSH', 'N_GH', 'N_GSH', 'N_AH', 'N_ASH', 'N_BH',
    'N_CHH'
]
default_arp_names = {
    'OF':   '00',     # off
    'M':    '47',     # major
    'm':    '37',     # minor
    'maj7': '4B',     # major 7
    'm7':   '3A',     # minor 7
    'dom7': '4A',     # dominant 7
    'dim':  '36',     # diminished
    'dim7': '39',     # diminished 7
    'aug':  '48',     # augmented
}

# The concepts of musical pitch and time ############################

class PentlyPitchContext(object):
    """

Six octave modes are recognized at various places:

'drum' -- any word of 2+ characters that starts and ends with a
    letter and does not end with a digit and "g"
'noise' -- 0 to 15 is a pitch; the result is subtracted from 15
    because NES APU treats 15 as the longest period and thus
    the lowest pitch
'absolute' -- Always guess the octave below C
'orelative' -- Guess the octave of the previous note.
'relative' -- Guess the octave of the note with the given scale degree
    closest to the previous note, disregarding accidentals.
None: Wait for the first thing that looks like a pitch or drum.

Arpeggio-related:

last_arp -- last arpeggio value set with EN
arp_top -- if true, transpose notes down by the top of the chord
arp_mod -- if not None, the current note has a single-note arpeggio
    modifier, and subsequent 'w' commands should get the same
last_chord -- last (pitch, arpeggio) used; note 'q' repeats this
arp_names

"""

    def __init__(self, other=None, language='english'):
        if other is None:
            self.set_language(language)
            self.reset_octave(octave_mode=None)
            self.reset_arp()
            self.simul_notes = False
            self.arp_names = ChainMap({}, default_arp_names)
            self.mml_octaves = True
        else:
            self.set_language(other.language)
            self.last_octave = other.last_octave
            self.octave_mode = other.octave_mode
            self.last_arp = other.last_arp
            self.arp_mod = other.arp_mod
            self.arp_top = other.arp_top
            self.last_chord = other.last_chord
            self.simul_notes = other.simul_notes
            self.arp_names = other.arp_names.new_child()
            self.mml_octaves = other.mml_octaves

    def set_language(self, language):
        language = language.lower()
        # English B is H; German and Scandinavian B is H flat
        if language == 'english':
            self.language, self.b_means = language, 11  # a, a#, b, c
        elif language == 'deutsch':
            self.language, self.b_means = language, 10  # a, a#, h, c
        else:
            raise ValueError("unknown notenames language %s; try english or deutsch"
                             % language)

    def reset_octave(self, octave_mode="unchanged", octave=0):
        """Change octave mode and last note.

octave_mode -- the new octave mode, one of these:
    "unchanged": Leave octave mode as it was
    "absolute": Treat notes as relative to F below middle C
    "orelative": Treat notes as relative to F nearest the last note
    "relative": Treat notes as relative to the last note
    "noise": Treat as noise period indices (0=lowest, 15=highest)
    "drum": Treat as drum names
    None: Wait for a drum or note, then go to "drum" or "absolute"

    , which can be "absolute",
    "relative", or "orelative", or a false value to leave it the same
octave -- the number of commas (negative) or primes (positive) in
    the new octave.  For example, octave 0 sets the last note to the
    F below middle C, and octave 1 sets to the F above middle C.
"""
        self.last_octave = (3, int(octave))
        if octave_mode != 'unchanged':
            self.octave_mode = octave_mode

    def reset_arp(self):
        self.last_arp = self.arp_mod = None
        self.last_chord = None
        self.arp_top = False

    def set_pitched_mode(self):
        """Set the octave mode to absolute if None."""
        if self.octave_mode is None: self.octave_mode = 'absolute'

    @staticmethod
    def calc_arp_inversion(arp):
        if len(arp) != 2:
            raise ValueError("internal error: %s not length 2" % repr(arp))

        # Only an arpeggio within an octave can be inverted
        nibbles = [int(c, 16) for c in arp]
        if max(nibbles) >= 12:
            raise ValueError("interval in %s too large to invert; must be smaller than an octave (C)"
                             % arp)

        # 070 -> 050, preserving ratio of 50:50 arps
        if nibbles[1] == 0:
            return "%x0" % (12 - nibbles[0])

        # Replace 0 with C and subtract the lowest nonzero
        nibbles = [12] + [c or 12 for c in nibbles]
        lowest = min(nibbles)
        nibbles = [c - lowest for c in nibbles]

        # Rotate to the left until 0 leads
        while nibbles[0]:
            nibbles.append(nibbles[0])
            del nibbles[0]
        return "%X%X" % (nibbles[1], nibbles[2])

    def translate_arp_name(self, arp):
        """Normalize an arpeggio name to 2 hex digits or raise KeyError.

Return None (if arp is falsey), 2 hex digits, or '-' followed by
2 hex digits.
"""
        if not arp: return None

        # Chop off modifiers (downward, chord inversion)
        arp_prefix = ''
        if arp.startswith('-'):
            arp_prefix, arp = '-', arp[1:]
        arp = arp.split('/', 1)
        inversion = int(arp[1] if len(arp) > 1 else 0)
        arp = arp[0]

        # If not a nibble pair, look it up
        arpvalue = None
        if len(arp) < 3:
            try:
                arpvalue = int(arp, 16)
            except ValueError:
                pass
            else:
                arpvalue = ("00" + arp)[-2:]
        if arpvalue is None:
            arp = self.arp_names[arp]

        # Process inversion
        for _ in range(inversion):
            arp = self.calc_arp_inversion(arp)

        return arp_prefix + arp

    def add_arp_name(self, name, definition):
        if definition.startswith('-'):
            raise ValueError("%s: downward sign goes in pattern, not definition"
                             % definition)
        definition = self.translate_arp_name(definition)
        if not name[:1].isalpha():
            raise ValueError("chord name %s must begin with a letter"
                             % name)
        if name in ('P1', 'P2'):
            raise ValueError("chord name %s is reserved for rate changes"
                             % name)
        try:
            olddefinition = self.translate_arp_name(name)
        except KeyError:
            pass
        else:
            raise ValueError("chord name %s already defined as %s"
                             % (name, definition))
        self.arp_names[name] = definition

    def set_arp(self, arp):
        """Set the arpeggio for subsequent notes to arp."""
        self.set_pitched_mode()
        self.last_arp = self.translate_arp_name(arp)

    @staticmethod
    def fixup_downward_arp(notenum, arp):
        # - means transpose the note down by the larger nibble
        # but it's ignored for waits
        if arp and arp.startswith('-'):
            arp = arp[1:]
            if isinstance(notenum, int):
                notenum -= max(int(c, 16) for c in arp)
        return notenum, arp

    def parse_pitch(self, preoctave, notename, accidental, postoctave, arp):
        arp = self.translate_arp_name(arp)
        if notename == 'p': notename = 'r'
        nonpitchtypes = {
            'r': 'rest', 'w': 'wait', 'l': 'length change',
            'q': 'chord repeat'
        }
        if notename in nonpitchtypes:
            bad_modifier = ("octave changes" if preoctave or postoctave
                            else "accidentals" if accidental
                            else "chords" if arp and notename in "qr"
                            else None)
            if bad_modifier:
                msg = ("%s: %s can't have %s"
                       % (notename, nonpitchtypes[notename], bad_modifier))
                raise ValueError(msg)

            if notename == 'q':
                return self.last_chord

            # Rests kill a single-note arpeggio.
            # Waits and length changes preserve it.
            if notename == 'r':
                self.arp_mod = arp
            arp = arp or self.arp_mod or self.last_arp
            return self.fixup_downward_arp(notename, arp)
            
        octave = 0
        if preoctave and postoctave:
            raise ValueError("%s: cannot specify octave both before and after note name"
                             % pitch)
        elif preoctave:
            octave = len(preoctave)
            if preoctave.startswith('<'):
                octave = -octave
        elif postoctave:
            octave = len(postoctave)
            if postoctave.startswith(','):
                octave = -octave

        if self.octave_mode in ('orelative', 'relative'):
            octave += self.last_octave[1]
        scaledegree = scaledegrees[notename]
        if self.octave_mode == 'relative':
            # Process LilyPond style relative mode
            degreediff = scaledegree - self.last_octave[0]
            if degreediff > 3:
                octave -= 1
            elif degreediff < -3:
                octave += 1

        if notename == 'b':
            semi = self.b_means
        else:
            semi = notenamesemis[notename]

        self.last_octave = scaledegree, octave
        notenum = semi + accidentalmeanings[accidental] + 12 * octave + 15

        # Save the single-note arpeggio if any, and if there is one,
        # have it return to 00 instead of unspecified
        self.arp_mod = arp
        if arp:
            self.last_arp = self.last_arp or '00'
        arp = arp or self.arp_mod or self.last_arp
        notenum, arp = self.fixup_downward_arp(notenum, arp)
        if arp and arp != '00':
            self.last_chord = notenum, arp
        return notenum, arp

    pitchRE = re.compile(r"""
(>*|<*)       # MML style octave
([a-h])       # note name (pitches only, no lengths, volumes, etc.)
(b|bb|-|--|es|eses|s|ss|is|isis|\#|\#\#|\+|\+\+|x|)  # accidental
(,*|'*)$      # LilyPond style octave
""", re.VERBOSE)

    def parse_absolute_pitch(self, pitch):
        """Parse an absolute pitch: a note or a noise frequency."""
        if self.octave_mode == 'noise':
            pitch = int(pitch)
            if not 0 <= pitch <= 15:
                raise ValueError("noise pitches must be 0 to 15")
            return 15 - pitch

        m = self.pitchRE.match(pitch)
        if not m:
            raise ValueError("%s doesn't look like a pitch in %s mode"
                             % (pitch, self.octave_mode))
        g = list(m.groups())
        if g[0] and not self.mml_octaves:
            raise ValueError("%s: MML octave notation is off" % pitch)
        g.append(None)  # no arpeggio
        notenum, arp = self.parse_pitch(*g)
        return notenum


class PentlyRhythmContext(object):

    def __init__(self, other=None):
        if other is None:
            self.durations_stick = False
            self.set_scale(16)
            self.set_time_signature(4, 4)
            self.last_duration = None
            self.cur_measure, self.row_in_measure = 1, 0
        else:
            self.durations_stick = other.durations_stick
            self.set_scale(other.scale)
            self.set_time_signature(other.timenum, other.timeden)
            self.last_duration = other.last_duration
            self.cur_measure = other.cur_measure
            self.row_in_measure = other.row_in_measure

    def parse_duration(self, duration, duraugment):
        if duration:
            duration = int(duration)
            if not 1 <= duration <= 64:
                raise ValueError("only whole to 64th notes are valid, not %d"
                                 % duration)
            duraugment = duraugmentnums[duraugment]
            if duraugment and (duration & (duration - 1)):
                raise ValueError("only powers of 2 are valid, not %d"
                                 % duration)
            return duration, duraugment
        elif duraugment:
            raise ValueError("augment dots are valid only with numeric duration")
        else:
            return None, None

    def set_time_signature(self, timenum, timeden):
        if timenum < 2:
            raise ValueError("beats per measure must be at least 2")
        if not 2 <= timeden <= 64:
            raise ValueError("beat duration must be a half (2) to 64th (64) note")
        if timeden & (timeden - 1):
            raise ValueError("beat duration must be a power of 2")
        self.timenum, self.timeden = timenum, timeden
    
    def set_scale(self, rowvalue):
        if not 2 <= rowvalue <= 64:
            raise ValueError("row duration must be a half (2) to 64th (64) note")
        if rowvalue & (rowvalue - 1):
            raise ValueError("beat duration must be a power of 2")
        self.scale = rowvalue

    def get_measure_length(self):
        if self.scale % self.timeden != 0:
            raise ValueError("scale must be a multiple of time signature denominator")
        return self.scale * self.timenum // self.timeden

    def get_beat_length(self):
        if self.scale % self.timeden != 0:
            raise ValueError("scale must be a multiple of time signature denominator")
        rows_per_beat = self.scale // self.timeden
        # correct for compound prolation convention
        if self.timenum >= 6 and self.timenum % 3 == 0:
            rows_per_beat *= 3
        return rows_per_beat

    def fix_note_duration(self, notematch):
        """Convert duration to number of rows.

notematch -- (pitch, duration denominator, duration augment, slur)

Return (pitch, number of rows, slur) or None if it's not actually a note
(such as a length command 'l').
"""
        pitcharp, denom, augment, slur = notematch[:4]
        if isinstance(pitcharp, tuple) and pitcharp[0] == 'l':
            if denom is None:
                raise ValueError("length requires a duration argument")
            self.last_duration = denom, augment
            return None
        if augment == 0:  # 0: grace note
            return pitcharp, -denom, slur

        if denom is None:

            # If this is the first note, set the default duration to
            # one beat
            if self.last_duration is None:
                bl = self.get_beat_length()
                if bl & (bl - 1):  # Is it compound meter?
                    assert bl % 3 == 0
                    bl = bl * 2 // 3
                    assert self.scale % (2 * bl) == 0
                    augment = 6
                else:
                    augment = 4
                assert self.scale % bl == 0
                self.last_duration = (self.scale // bl, augment)

            denom, augment = self.last_duration
        elif self.durations_stick:
            self.last_duration = denom, augment

        wholerows = self.scale * augment // (denom * 4)
        partrows = self.scale * augment % (denom * 4)
        if partrows != 0:
            augmentname = dotted_names[augment]
            msg = ("%s1/%d note not multiple of 1/%d note scale (%.3f rows)"
                   % (augmentname, denom, self.scale,
                      wholerows + partrows / (denom * 4)))
            raise ValueError(msg)
        return pitcharp, wholerows, slur

    def parse_measure(self, measure=1, beat=1, row=0):
        if beat < 1:
            raise ValueError("time %d:%d:%d has a beat less than 1"
                             % (measure, beat, row))
        if row < 0:
            raise ValueError("time %d:%d:%d has a row less than 0"
                             % (measure, beat, row))

        measure_length = self.get_measure_length()
        beat_length = self.get_beat_length()
        actual_row = row + beat_length * (beat - 1)

        if actual_row >= measure_length:
            raise ValueError("time %d:%d:%d has beat %d but measure has only %d beats (%d rows)"
                             % (measure, beat, row,
                                actual_row // beat_length + 1,
                                measure_length // beat_length, measure_length))
        return measure, actual_row, measure_length, beat_length

    def set_measure(self, measure=1, beat=1, row=0):
        """Set the current musical time."""
        measure, row, _, _ = self.parse_measure(measure, beat, row)
        self.cur_measure, self.row_in_measure = measure, row

    def add_rows(self, rows):
        """Add a duration in rows to the current musical time."""
        measure_length = self.get_measure_length()
        row = self.row_in_measure + rows
        self.cur_measure += row // measure_length
        self.row_in_measure = row % measure_length

    def wait_for_measure(self, measure, beat=1, row=0):
        """Seek to a given musical time.

Return rows between old and new positions."""
        measure, row, measure_length, beat_length = self.parse_measure(measure, beat, row)
        if (measure < self.cur_measure
            or (measure == self.cur_measure and row < self.row_in_measure)):
            old_beat = self.row_in_measure // beat_length + 1
            old_row = self.row_in_measure % beat_length
            raise ValueError("wait for %d:%d:%d when song is already to %d:%d:%d"
                             % (measure, row // beat_length + 1, row % beat_length,
                                self.cur_measure, old_beat, old_row))

        rows_to_wait = ((measure - self.cur_measure) * measure_length
                        + (row - self.row_in_measure))
        self.cur_measure, self.row_in_measure = measure, row
        return rows_to_wait

# The parts of a score ##############################################

class PentlyRenderable(object):

    nonalnumRE = re.compile("[^a-zA-Z0-9]")

    def __init__(self, name=None, orderkey=0, fileline=None, warn=None):
        self.name, self.orderkey, self.fileline = name, orderkey, fileline
        self.warn = warn
        self.asmdataname = self.asmdata = None
        self.asmdataprefix = ''
        self.bytesize = 0

    @classmethod
    def get_asmname(self, name):
        return '_'.join(c for c in self.nonalnumRE.split(name) if c)

    def resolve_scope(self, scoped_name, parent_scope, existing):
        if scoped_name.startswith('::'):
            return scoped_name.lstrip(':')
        while parent_scope:
            test = '::'.join((parent_scope, scoped_name))
            if test in existing: return test
            parent_scope = parent_scope.rsplit('::', 1)
            if len(parent_scope) < 2: break
            parent_scope = parent_scope[0]
        return scoped_name

    def render(self, scopes=None):
        raise NotImplementedError

class PentlyEnvelopeContainer(PentlyRenderable):

    def __init__(self, name=None, orderkey=0, fileline=None, warn=None):
        super().__init__(name, orderkey, fileline, warn=warn)
        self.timbre = self.volume = self.pitch = None
        self.pitch_looplen = self.timbre_looplen = 1

    def set_volume(self, volumes, fileline=None):
        if self.volume is not None:
            file, line = self.volume_fileline
            raise ValueError("volume for %s was already set at %s line %d"
                             % (self.name, file, line))
        volumes = list(volumes)
        if not all(0 <= x <= 15 for x in volumes):
            raise ValueError("volume steps must be 0 to 15")
        self.volume, self.volume_fileline = volumes, fileline

    @staticmethod
    def expand_runs(words):
        if isinstance(words, str):
            words = words.split()
        words = [word.rsplit(":", 1) for word in words]
        # words is [[word], [word, "runlength"], [word], ...]
        words = [(word[0], int(word[1]) if len(word) > 1 else 1)
                 for word in words]
        # words is [(word, runlength), ...]
        words = [word
                 for word, runlength in words
                 for i in range(runlength)]
        return words

    @staticmethod
    def pipesplit(words):
        pipesplit = ' '.join(words).split('|', 1)
        pipesplit = [PentlyEnvelopeContainer.expand_runs(part)
                     for part in pipesplit]
        out = pipesplit[0]
        if len(pipesplit) > 1:
            afterloop = pipesplit[1]
            looplen = len(afterloop)
            out.extend(afterloop)
        else:
            looplen = None
        return out, looplen

    def get_max_timbre(self):
        return 3

    def set_timbre(self, timbrewords, fileline=None):
        if self.timbre is not None:
            file, line = self.timbre_fileline
            raise ValueError("timbre for %s %s was already set at %s line %d"
                             % (self.cur_obj[0], self.cur_obj[1].name,
                                file, line))
        timbres, looplen = self.pipesplit(timbrewords)
        timbres = [int(x) for x in timbres]
        maxduty = self.get_max_timbre()
        if not all(0 <= x <= maxduty for x in timbres):
            raise ValueError("timbre steps must be 0 to %d" % maxduty)
        self.timbre, self.timbre_looplen = timbres, looplen or 1
        self.timbre_fileline = fileline

    def parse_pitchenv(self, pitchword):
        """Parse an element of a pitch envelope.

The set_pitch() method calls this once per pitch word.  Subclasses
may initialize any necessary state in their __init__() method or in
an overridden set_pitch().

If not overridden, this abstract method raises NotImplementedError.

"""
        raise NotImplementedError

    def set_pitch(self, pitchwords, fileline=None):
        if self.pitch is not None:
            fileline = self.pitch_fileline
            raise ValueError("pitch for %s %s was already set at %s line %d"
                             % (self.cur_obj[0], self.cur_obj[1].name,
                                file, line))
        pitches, looplen = self.pipesplit(pitchwords)
        pitches = [self.parse_pitchenv(pitch) for pitch in pitches]
        self.pitch, self.pitch_looplen = pitches, looplen or 1
        self.pitch_fileline = fileline

    @staticmethod
    def expand_envelope_loop(envelope, looplen, length):
        index = 0
        for i in range(length):
            yield envelope[index]
            index += 1
            if index >= len(envelope):
                index -= looplen

    def xform_timbre(self, t):
        return t << 14

    def get_default_timbre(self):
        return 2

    def render_tvp(self):
        volume = self.volume or [8]
        timbre = self.timbre or [self.get_default_timbre()]
        timbre_looplen = self.timbre_looplen
        timbre = list(self.expand_envelope_loop(timbre, timbre_looplen, len(volume)))
        xtimbre = [self.xform_timbre(t) for t in timbre]
        pitch = self.pitch or [0]
        pitch_looplen = self.pitch_looplen
        pitch = list(self.expand_envelope_loop(pitch, pitch_looplen, len(volume)))
        attackdata = bytearray()
        for t, v, p in zip(xtimbre, volume, pitch):
            attackdata.append((t >> 8) | v)
            attackdata.append((t | p) & 0xFF)
        return timbre, volume, pitch, bytes(attackdata)

class PentlyInstrument(PentlyEnvelopeContainer):

    def __init__(self, name=None, orderkey=0, fileline=None, warn=None):
        """Set up a new instrument.

name, fileline -- used in duplicate error messages
"""
        super().__init__(name, orderkey, fileline, warn=warn)
        self.detached = self.decay = None

    def set_decay(self, rate, fileline=None):
        if not 0 <= rate <= 127:
            raise ValueError("decay must be 1 to 127 units per 16 frames, not %d"
                             % rate)
        if self.decay is not None:
            file, line = self.decay_fileline
            raise ValueError("decay for %s was already set at %s line %d"
                             % (self.name, file, line))
        self.decay, self.decay_fileline = rate, fileline

    def parse_pitchenv(self, pitch):
        """Parse an element of the pitch envelope relative to the base note.

This is equivalent to an "absolute" arpeggio envelope in FamiTracker.

"""
        pitch = int(pitch)
        if not -60 <= pitch <= 60:
            raise ValueError("noise pitches must be within five octaves")
        return pitch

    def set_detached(self, detached):
        self.detached = detached
    
    @staticmethod
    def compress_zero_arps(attackdata):
        """Delete zero pitch byte and set bit 4 of timbre/volume byte."""
        out = bytearray()
        attackdata = iter(attackdata)
        for timbre_volume in attackdata:
            pitch = next(attackdata)
            if pitch == 0:
                out.append(timbre_volume | 0x10)
            else:
                out.append(timbre_volume)
                out.append(pitch)
            
        return bytes(out)

    def render(self, scopes=None):
        timbre, volume, pitch, attackdata = self.render_tvp()

        # Drop the final (sustain) frame and compress the rest
        # Sustain pitch is always 0
        sustaintimbre = timbre[-1]
        sustainvolume = volume[-1]
        attackdata = self.compress_zero_arps(attackdata[:-2])

        decay = self.decay or 0
        detached = 1 if self.detached else 0

        asmname = self.get_asmname(self.name)
        self.asmname = 'PI_'+asmname
        self.asmdef = ("instdef PI_%s, %d, %d, %d, %d, %s, %d"
                       % (asmname, sustaintimbre, sustainvolume, decay,
                          detached, 'PIDAT_'+asmname if attackdata else '0',
                          len(volume) - 1))
        self.asmdataname = 'PIDAT_'+asmname
        self.asmdataprefix = '.byte '
        self.asmdata = attackdata
        self.bytesize = len(attackdata) + 5

class PentlySfx(PentlyEnvelopeContainer):

    def __init__(self, channel_type, pitchctx=None,
                 name=None, orderkey=0, fileline=None, warn=None):
        """Set up a new sound effect.

channel_type -- 0 for pulse, 2 for triangle, or 3 for noise
name, fileline -- used in duplicate error messages

"""
        super().__init__(name, orderkey, fileline, warn=warn)
        self.rate, self.channel_type = None, channel_type
        self.pitchctx = PentlyPitchContext(pitchctx)
        octave_mode = 'noise' if channel_type == 3 else 'absolute'
        self.pitchctx.reset_octave(octave_mode=octave_mode)

    def set_rate(self, rate, fileline=None):
        """Sets the playback rate of a sound effect."""
        if not 1 <= rate <= 16:
            raise ValueError("rate must be 1 to 16 frames per step, not %d"
                             % rate)
        if self.rate is not None:
            file, line = self.rate_fileline
            raise ValueError("rate for %s was already set at %s line %d"
                             % (self.cur_obj[1].name, file, line))
        self.rate, self.rate_fileline = rate, fileline

    def get_max_timbre(self):
        return 1 if self.channel_type == 3 else 3

    def parse_pitchenv(self, pitch):
        """Parse an element of the absolute pitch envelope.

This is equivalent to a "fixed" arpeggio envelope in FamiTracker.

"""
        return self.pitchctx.parse_absolute_pitch(pitch)

    def get_default_timbre(self):
        return 0 if self.channel_type == 3 else 2

    def xform_timbre(self, t):
        if self.channel_type == 2:
            return 0x8000
        if self.channel_type == 3:
            return 0x80 if t else 0
        return t << 14

    def render(self, scopes=None):
        timbre, volume, pitch, attackdata = self.render_tvp()
        rate = self.rate or 1

        # Trim trailing silence
        trimmed_silence = 0
        while len(volume) > 1 and volume[-1] == 0:
            del volume[-1]
            trimmed_silence += 1
        if trimmed_silence:
            attackdata = attackdata[:-2 * trimmed_silence]

        asmname = self.get_asmname(self.name)
        self.asmname = 'PE_'+asmname
        self.asmdef = ("sfxdef PE_%s, PEDAT_%s, %d, %d, %d"
                       % (asmname, asmname,
                          len(volume), rate, self.channel_type))
        self.asmdataname = 'PEDAT_'+asmname
        self.asmdataprefix = '.byte '
        self.asmdata = attackdata
        self.bytesize = len(attackdata) + 4

class PentlyDrum(PentlyRenderable):

    drumnameRE = re.compile('([a-zA-Z_][a-zA-Z0-9_]*[a-zA-Z_])$')

    def __init__(self, sfxnames, name, orderkey=0, fileline=None, warn=None):
        super().__init__(name, orderkey, fileline, warn=warn)
        is_grace_note = name[-1] == 'g' and name[-2].isdigit()
        if is_grace_note:
            raise ValueError("drum name must not end with grace note command")
        if not self.drumnameRE.match(name):
            raise ValueError("drum name must begin and end with letter or '_'")
        self.sfxnames = sfxnames

    def render(self, scopes=None):
        # TODO: For drums defined in a song, check for effects in same song
        sfxnames = ', '.join('PE_'+self.get_asmname(sfxname)
                             for sfxname in self.sfxnames)
        self.asmname = 'DR_'+PentlyRenderable.get_asmname(self.name)
        self.asmdef = "drumdef %s, %s" % (self.asmname, sfxnames)
        self.bytesize = 2

class PentlySong(PentlyRenderable):

    def __init__(self, pitchctx=None, rhyctx=None,
                 name=None, orderkey=0, fileline=None, warn=None):
        super().__init__(name, orderkey, fileline, warn=warn)
        self.pitchctx = PentlyPitchContext(pitchctx)
        self.rhyctx = PentlyRhythmContext(rhyctx)
        self.rhyctx.tempo = 100.0
        self.last_rowtempo = self.segno_fileline = self.last_beatlen = None
        self.conductor = []
        self.bytesize = 2
        self.rehearsal_marks = {}
        self.total_rows = self.last_mark_rows = 0
        self.title = self.author = ""

    def wait_rows(self, rows_to_wait):
        """Updates the tempo and beat duration if needed, then waits some rows."""
        if rows_to_wait < 1: return

        # Update tempo if needed
        beat_length = self.rhyctx.get_beat_length()
        rowtempo = int(round(self.rhyctx.tempo * beat_length))
        if rowtempo > 1500:
            raise ValueError("last tempo change exceeds 1500 rows per minute")
        if rowtempo != self.last_rowtempo:
            self.conductor.append('setTempo %d' % rowtempo)
            self.bytesize += 2
            self.last_rowtempo = rowtempo

        if self.last_beatlen != beat_length:
            try:
                durcode = durcodes[beat_length]
            except KeyError:
                raise ValueError("no duration code for %d beats per row"
                                 % beat_length)
            self.conductor.append('setBeatDuration %s' % durcode)
            self.bytesize += 1
            self.last_beatlen = beat_length
            
        self.total_rows += rows_to_wait
        while rows_to_wait > 256:
            self.conductor.append('waitRows 256')
            self.bytesize += 2
            rows_to_wait -= 256
        self.conductor.append('waitRows %d' % rows_to_wait)
        self.bytesize += 2

    def set_attack(self, chname):
        chnum = pitched_tracks[chname]
        if chnum >= 3:
            raise ValueError("%s is not a pitched channel" % chname)
        cmd = "attackOn%s" % track_suffixes[chnum]
        self.conductor.append(cmd)
        self.bytesize += 1

    def play(self, patname, track=None, instrument=None, transpose=0):
        if (track is not None and instrument is not None
            and transpose == 0):
            # Attempt a note-on rather than a pattern start
            if track == 'noise':
                ch = 3
                self.pitchctx.octave_mode = "noise"
            else:
                ch = pitched_tracks[track]
                self.pitchctx.octave_mode = 'absolute'
                self.pitchctx.reset_octave()
                if ch >= 3:
                    raise ValueError("cannot play conductor note on a track without its own channel")
            try:
                transpose = self.pitchctx.parse_absolute_pitch(patname)
            except ValueError as e:
                pass
            else:
                abstract_cmd = ('noteOn', ch, transpose, instrument)
                self.conductor.append(abstract_cmd)
                self.bytesize += 3
                return

        if track is not None:
            try:
                track = pitched_tracks[track]
            except KeyError:
                raise ValueError('unknown track ' + track)
        abstract_cmd = ('playPat', track, patname, transpose, instrument)
        self.bytesize += 4
        self.conductor.append(abstract_cmd)

    @staticmethod
    def parse_trackset(tracks):
        tracks_to_stop = set()
        tracks_unknown = []
        for trackname in tracks:
            if trackname == 'drum':
                tracks_to_stop.add(3)
                continue
            try:
                track = pitched_tracks[trackname]
            except KeyError:
                tracks_unknown.append(trackname)
                continue
            else:
                tracks_to_stop.add(track)
        if tracks_unknown:
            raise ValueError("unknown track names: "+" ".join(tracks_unknown))
        return tracks_to_stop

    def stop_tracks(self, tracks):
        tracks_to_stop = self.parse_trackset(tracks)
        abstract_cmds = [('stopPat', track) for track in tracks_to_stop]
        self.conductor.extend(abstract_cmds)
        self.bytesize += 4 * len(abstract_cmds)

    def add_segno(self, fileline):
        if self.segno_fileline is not None:
            file, line = self.segno_fileline
            raise ValueError("%s: loop point already set at %s line %d"
                             % (self.name, file, line))
        self.conductor.append('segno')
        self.bytesize += 1
        self.segno_fileline = fileline
        self.rehearsal_marks['%'] = (self.total_rows, fileline)

    def add_mark(self, markname, fileline):
        if len(markname) > 24:
            raise ValueError("name of mark %s exceeds 24 characters"
                             % markname)
        try:
            markname.encode('ascii', errors='strict')
        except UnicodeError:
            self.warn("mark %s contains non-ASCII characters" % markname)
            markname = markname.encode('ascii', errors='replace')
            markname = markname.decode('ascii')
            
        if self.total_rows <= self.last_mark_rows:
            raise ValueError("no time between mark %s and preceding mark"
                             % markname)
        if markname.startswith('%'):
            raise ValueError("mark names starting with % are reserved")

        try:
            _, fileline = self.rehearsal_marks[markname]
        except KeyError:
            pass
        else:
            file, line = fileline
            raise ValueError("%s: mark %s already set at %s line %d"
                             % (self.name, markname, file, line))

        self.rehearsal_marks[markname] = (self.total_rows, fileline)
        self.last_mark_rows = self.total_rows

    def get_unclosed_msg(self):
        file, line = self.fileline
        return ("song %s began at %s line %d and was not ended with fine or dal segno"
                % (self.name, file, line))

    def render(self, scopes):
        out = []
        for row in self.conductor:
            if isinstance(row, str):
                out.append(row)
                continue
            if row[0] == 'playPat':
                track, patname, transpose, instrument = row[1:5]
                patname = self.resolve_scope(patname, self.name, scopes.patterns)
                pat = scopes.patterns[patname]
                if track is None: track = pat.track
                try:
                    lowestnote = pat.transpose
                except AttributeError:
                    lowestnote = None
                if track != 'drum' and lowestnote is None:
                    lowestnote = 0
                    self.warn("%s: pitched track %s has only rests"
                              % (self.name, patname))

                if track == 'drum':
                    if pat.track != 'drum':
                        raise ValueError('cannot play pitched pattern %s on drum track'
                                         % (patname,))
                    out.append("playPatNoise %s" % pat.asmname)
                    continue
                if pat.track == 'drum' and lowestnote is not None:
                    raise ValueError('%s: cannot play drum pattern %s on pitched track'
                                     % (self.name, patname))
                if isinstance(track, str):
                    track = pitched_tracks[track]
                if track is None:
                    raise ValueError("%s: no track for pitched pattern %s"
                                     % (self.name, patname))
                transpose += lowestnote
                if transpose < 0:
                    raise ValueError("%s: %s: trying to play %d semitones below lowest pitch"
                                     % (self.name, patname, -transpose))
                if instrument is None: instrument = pat.instrument
                if instrument is None:
                    raise ValueError("%s: no instrument for pattern %s"
                                     % (self.name, patname))
                instrument = self.resolve_scope(instrument, self.name, scopes.instruments)
                instrument = scopes.instruments[instrument].asmname
                suffix = track_suffixes[track]
                out.append("playPat%s %s, %d, %s"
                           % (suffix, pat.asmname, transpose, instrument))
                continue
            if row[0] == 'stopPat':
                out.append('stopPat%s' % track_suffixes[row[1]])
                continue
            if row[0] == 'noteOn':
                ch, pitch, instrument = row[1:4]
                instrument = self.resolve_scope(instrument, self.name, scopes.instruments)
                instrument = scopes.instruments[instrument].asmname
                out.append('noteOn%s %d, %s'
                           % (track_suffixes[ch], pitch, instrument))
                continue
            raise ValueError(row)

        asmname = PentlyRenderable.get_asmname(self.name)
        self.asmname = 'PS_'+asmname
        self.asmdef = 'songdef PS_%s, PSDAT_%s' % (asmname, asmname)
        self.asmdataname = 'PSDAT_'+asmname
        self.asmdataprefix = ''
        self.asmdata = out

class PentlyPattern(PentlyRenderable):

    def __init__(self, pitchctx=None, rhyctx=None,
                 instrument=None, track=None,
                 name=None, orderkey=0, fileline=None, warn=None):
        super().__init__(name, orderkey, fileline, warn=warn)
        self.pitchctx = PentlyPitchContext(pitchctx)
        self.rhyctx = PentlyRhythmContext(rhyctx)
        self.rhyctx.last_duration = None
        self.instrument, self.track, self.notes = instrument, track, []

        # TODO: The fallthrough feature is currently sort of broken
        # for pitched patterns.  Rendering needs to be reworked in
        # order to make the transposition consistent with that of
        # the following pattern.
        self.set_fallthrough(False)

        # Prepare for autodetection of octave mode.  If a pitched
        # track or pitched instrument is specified, default to
        # absolute.  Or if a note is seen before it is set, switch
        # to absolute with that note.  But if a drum is seen first,
        # set to drum mode.
        octave_mode = 'absolute' if track or instrument else None
        self.pitchctx.reset_octave(octave_mode=octave_mode)

    def set_fallthrough(self, value):
        self.fallthrough = bool(value)

    noteRE = re.compile(r"""
(>*|<*)           # MML style octave
([a-hwprlq])      # note name
(b|bb|-|--|es|eses|s|ss|is|isis|\#|\#\#|\+|\+\+|x|)  # accidental
(,*|'*)           # LilyPond style octave
([0-9]*)          # duration
(|\.|\.\.|g)      # duration augment
(|:-?(?:
  [a-zA-Z][0-9a-zA-Z]*|[0-9a-fA-F]{1,2}  # arpeggio chord name
)(?:/[12]|))      # inversion
([~()]?)$         # tie/slur?
""", re.VERBOSE)

    def parse_note(self, pitch):
        m = self.noteRE.match(pitch)
        if not m:
            return None, None, None, None, None
        (preoctave, notename, accidental, postoctave,
         duration, duraugment, arp, slur) = m.groups()
        if preoctave and not self.pitchctx.mml_octaves:
            raise ValueError("%s: MML octave notation is off" % pitch)
        semi = self.pitchctx.parse_pitch(
            preoctave, notename, accidental, postoctave, arp.lstrip(':')
        )
        if isinstance(semi, tuple) and semi[1]:
            assert not semi[1].startswith('-')
        duration, duraugment = self.rhyctx.parse_duration(duration, duraugment)
        return semi, duration, duraugment, slur

    drumnoteRE = re.compile(r"""
([a-zA-Z_][0-9a-zA-Z_]*[a-zA-Z_]|[lprw])  # drum name, length, rest, or wait
([0-9]*)       # duration
(|\.|\.\.|g)$  # duration augment
""", re.VERBOSE)

    def parse_drum_note(self, pitch):
        trace = pitch == 'w1g'

        # Don't have time right now to troubleshoot the RE to allow
        # things like "e1f1g" being drum "e1f" with duration "1g".
        # So hide grace note markup from the RE.
        is_grace_note = pitch[-1] == 'g' and pitch[-2].isdigit()
        if is_grace_note:
            pitch = pitch[:-1]

        m = self.drumnoteRE.match(pitch)
        if not m:
            return None, None, None, None
        (notename, duration, duraugment) = m.groups()
        if is_grace_note and duraugment == '':
            duraugment = 'g'
        duration, duraugment = self.rhyctx.parse_duration(duration, duraugment)
        if notename == 'r':
            notename = 'w'
        return notename, duration, duraugment, False

    def add_notematch(self, notematch):
        """Convert the duration in a notematch to rows and add it to the pattern.

notematch -- (pitch, duration denominator, duration augment, slur)

Return the fixed notematch as (pitch, rows, slur) or None if non-note.
"""
        f = self.rhyctx.fix_note_duration(notematch)
        if f:
            self.notes.append(f)
            rowduration = f[1]
            if rowduration > 0:
                self.rhyctx.add_rows(rowduration)
        return f

    arpeggioRE = re.compile(r"""
EN(-?(?:
  [a-zA-Z][0-9a-zA-Z]*|[0-9a-fA-F]{1,2}  # arpeggio chord name
)(?:/[12]|))      # inversion
""", re.VERBOSE)
    vibratoRE = re.compile("MP(OF|[0-9a-fA-F])$")
    portamentoRE = re.compile("EP(OF|[0-2][0-9a-fA-F])$")
    def add_pattern_note(self, word):
        """Parse a word of a pattern and add it."""
        if word in ('absolute', 'orelative', 'relative'):
            if self.pitchctx.octave_mode == 'drum':
                raise ValueError("drum pattern's octave mode cannot be changed")
            self.pitchctx.octave_mode = word
            return

        if len(word) == 2 and word[0] == 'o' and word[1].isdigit():
            if self.pitchctx.octave_mode == 'drum':
                raise ValueError("drum pattern's octave cannot be changed")
            elif self.pitchctx.octave_mode is None:
                self.pitchctx.octave_mode = 'absolute'
            target_octave = int(word[1])
            self.pitchctx.reset_octave(octave=target_octave - 2)
            return

        volmatch = volcodes.get(word)
        if volmatch is not None:
            self.notes.append("CHVOLUME,%d" % volmatch)
            return

        if word == '|':  # Bar check
            m, r = self.rhyctx.cur_measure, self.rhyctx.row_in_measure
            if r != 0:
                rpb = self.rhyctx.get_beat_length()
                b, r = 1 + r // rpb, r % rpb
                self.warn("bar check failed at musical time %d:%d:%d"
                          % (m, b, r))
            return

        # ENxx: Arpeggio
        arpmatch = (self.arpeggioRE.match(word)
                    if self.pitchctx.octave_mode != 'drum'
                    else None)
        if arpmatch:
            arpvalue = arpmatch.group(1)
            if arpvalue == 'P1':
                self.notes.append("FASTARP")
            elif arpvalue == 'P2':
                self.notes.append("SLOWARP")
            else:
                self.pitchctx.set_arp(arpvalue)
            return
        if word.startswith("EN") and not arpmatch:
            self.warn("malformed arpeggio %s" % repr(word))

        # EPxx: Portamento rate
        slidematch = (self.portamentoRE.match(word)
                      if self.pitchctx.octave_mode != 'drum'
                      else None)
        if slidematch:
            bendhex = slidematch.group(1)
            if bendhex == 'OF':
                bendhex = '00'
            self.notes.append("BEND,$"+bendhex)
            return
        if word.startswith("EP") and not slidematch:
            self.warn("malformed portamento %s" % repr(word))

        # MPxx: Vibrato
        vibratomatch = (self.vibratoRE.match(word)
                        if self.pitchctx.octave_mode != 'drum'
                        else None)
        if vibratomatch:
            self.pitchctx.set_pitched_mode()
            vibargument = vibratomatch.group(1)
            if vibargument == 'OF':  # Treat MPOF as MP0
                vibargument = '0'
            else:
                vibargument = int(vibargument, 16)
                vibargument = "%d" % min(vibargument, 4)
            self.notes.append("VIBRATO,"+vibargument)
            return

        # @ marks are instrument changes.  Resolve them later
        # once asmname values have been assigned.
        if word.startswith('@'):
            self.notes.append(word)
            return

        if self.pitchctx.octave_mode is None:
            drummatch = self.parse_drum_note(word)
            notematch = self.parse_note(word)
            if drummatch[0] is not None and notematch[0] is not None:
                # Only note length and rest/wait commands keep the pattern
                # in an indeterminate state between pitched and drum
                if notematch[0][0] not in ('l', 'p', 'r', 'w'):
                    raise ValueError("%s is ambiguous: it could be a drum or a pitch"
                                     % word)
                self.add_notematch(drummatch)
                return
            elif drummatch[0] is not None:
                self.track = self.pitchctx.octave_mode = 'drum'
                self.add_notematch(drummatch)
                return
            elif notematch[0] is not None:
                self.pitchctx.set_pitched_mode()
                self.add_notematch(notematch)
                return
            else:
                raise ValueError("unknown first note %s" % word)

        if self.pitchctx.octave_mode == 'drum':
            drummatch = self.parse_drum_note(word)
            if drummatch[0] is not None:
                self.add_notematch(drummatch)
            else:
                raise ValueError("unknown drum pattern note %s" % word)
            return

        notematch = self.parse_note(word)
        if notematch[0] is not None:
            self.add_notematch(notematch)
        else:
            raise ValueError("unknown pitched pattern note %s" % word)

    # in a way that minimizes TRANSPOSE transitions
    @staticmethod
    def find_transpose_runs(data):
        hi = None
        runs = [[0, None]]
        for i, note in enumerate(data):
            if isinstance(note, str):
                continue
            pitch = note[0]
            if not isinstance(pitch, int):
                continue
            lo = min(runs[-1][-1], pitch) if runs[-1][-1] is not None else pitch
            hi = max(hi, pitch) if hi is not None else pitch
            if hi - lo > 24:
                runs.append([i, pitch])
                hi = pitch
            else:
                runs[-1][-1] = lo
        return [tuple(i) for i in runs]

    @staticmethod
    def collapse_ties(notes, tie_rests=False):
        """Interpret slur commands; combine w notes and slurred same-pitch notes.

notes -- iterable of (pitch, numrows, slur) sequences
tie_rests -- True if track has no concept of a "note off"

"""

        # Convert tie/slur notations ~, (, and ) to true/false
        sluropen = False
        slurnotes = []
        for note in notes:
            if isinstance(note, str):
                slurnotes.append(note)
                continue

            pitch, numrows, slur = note
            if slur == '(':
                sluropen = True
            elif slur == ')':
                sluropen = False
            slur = sluropen or slur == '~'
            slurnotes.append((pitch, numrows, slur))
        notes = slurnotes

        out = []
        lastwasnote = hasnote = False
        curarp = None
        for note in notes:
            if isinstance(note, str):
                lastwasnote = False
                out.append(note)
                continue

            pitch, numrows, slur = note
            if isinstance(pitch, tuple):
                pitch, arp = pitch
            else:
                arp = None

            if arp is not None and arp != curarp:
                arp = str(arp)
                out.append("ARPEGGIO,$" + arp)
                lastwasnote = False
                curarp = arp

            # slur
            if tie_rests and pitch == 'r':
                pitch = 'w'
            # Initial wait becomes a rest
            if pitch == 'w' and not out:
                pitch = 'r'
            # If match and not grace, combine notes
            if (lastwasnote
                and numrows > 0
                and (pitch == 'w'
                     or (out[-1][0] == pitch and out[-1][2]))):
                out[-1][1] += numrows
                out[-1][2] = slur
            else:
                out.append([pitch, numrows, slur])
            lastwasnote = hasnote = True
        return [tuple(i) if not isinstance(i, str) else i for i in out]

    @staticmethod
    def collapse_effects(notes):

        # Size optimization: If there are only rests and other effect
        # changes between an arp and the following arp, not notes or
        # waits, remove the first of the two.
        rnotes = []
        keep_prev_arp = True
        for item in reversed(notes):
            if isinstance(item, str):
                if item.startswith("ARPEGGIO,$"):
                    if not keep_prev_arp:
                        continue
                    keep_prev_arp = False
            elif item[0] != 'r':
                keep_prev_arp = True
            rnotes.append(item)
        rnotes.reverse()

        # Size optimization: Remove instruments identical to the
        # previous with no notes or waits in between
        # TODO

        return rnotes

    row_to_duration = [
        (16, '|D_1'), (12, '|D_D2'), (8, '|D_2'), (6, '|D_D4'),
        (4, '|D_4'), (3, '|D_D8'), (2, '|D_8'), (1, '')
    ]
    @classmethod
    def numrows_to_durations(self, numrows):
        """Break a number of rows into a sequence of tied durations."""
        it = iter(self.row_to_duration)
        dur, ormask = next(it)
        while numrows >= 1:
            while numrows < dur:
                dur, ormask = next(it)
            yield ormask
            numrows -= dur

    def render(self, scopes):
        is_drum = self.track == 'drum'
        notes = self.collapse_ties(self.notes, is_drum)
        self.notes = notes = self.collapse_effects(notes)

        bytedata = []

        if not is_drum:
            transpose_runs = self.find_transpose_runs(self.notes)
            self.transpose = cur_transpose = transpose_runs[0][1]
            transpose_pos = 1
        else:
            transpose_runs = []
        last_slur = False

        for i, note in enumerate(notes):
            if (transpose_runs
                and transpose_pos < len(transpose_runs)
                and i >= transpose_runs[transpose_pos][0]):
                new_transpose = transpose_runs[transpose_pos][1]
                bytedata.append("TRANSPOSE,<%d" % (new_transpose - cur_transpose))
                cur_transpose = new_transpose
                transpose_pos += 1
            if isinstance(note, str):
                if note.startswith('@'):
                    instname = self.resolve_scope(note[1:], self.name, scopes.instruments)
                    note = 'INSTRUMENT,' + scopes.instruments[instname].asmname
                bytedata.append(note)
                continue
            if len(note) != 3:
                self.warn("internal: bad element count in "+repr(note))
            pitch, numrows, slur = note
            if isinstance(pitch, int):
                offset = pitch - cur_transpose
                assert 0 <= offset <= 24
                pitchcode = pattern_pitchoffsets[offset]
            elif pitch == 'r':
                pitchcode = 'REST'
            elif pitch == 'w':  # usually a tie after an @-command
                pitchcode = 'N_TIE'
            elif is_drum:
                drumname = self.resolve_scope(pitch, self.name, scopes.drums)
                pitchcode = 'DR_' + self.get_asmname(drumname)
            else:
                raise ValueError("unknown pitch %s" % pitch)

            if numrows < 0:
                # Grace note of -numrows frames
                bytedata.append('GRACE,%d' % -numrows)
                bytedata.append(pitchcode)
            else:
                for durcode in self.numrows_to_durations(numrows):
                    bytedata.append(pitchcode+durcode)
                    pitchcode = 'N_TIE'

            slur = bool(slur)
            if slur != last_slur:
                last_slur = slur
                bytedata.append("LEGATO_ON" if slur else "LEGATO_OFF")

        # Transpose back to start at end of pattern
        if transpose_runs and cur_transpose != transpose_runs[0][1]:
            bytedata.append("TRANSPOSE,<%d" % (transpose_runs[0][1] - cur_transpose))
        if not self.fallthrough: bytedata.append('PATEND')

        asmname = self.get_asmname(self.name)
        self.asmdef = 'patdef PP_%s, PPDAT_%s' % (asmname, asmname)
        self.asmname = 'PP_'+asmname
        self.asmdataname = 'PPDAT_'+asmname
        self.asmdataprefix = '.byte '
        self.asmdata = bytedata
        self.bytesize = sum(len(s.split(',')) for s in bytedata) + 2

# Parse the score into objects ######################################

class PentlyInputParser(object):

    def __init__(self, filename=None):
        self.sfxs = {}
        self.drums = {}
        self.instruments = {}
        self.patterns = {}
        self.songs = {}
        self.resume_mute_fileline = self.resume_fileline = None
        self.resume_row = self.resume_mute = 0
        self.cur_obj = self.cur_song = self.resume_song = None
        self.filelinestack = [[filename, 0]]
        self.rhyctx = PentlyRhythmContext()
        self.pitchctx = PentlyPitchContext()
        self.unk_keywords = self.total_lines = 0
        self.warnings = []
        self.filename = filename or os.path.basename(sys.argv[0])
        self.title = self.author = self.copyright = "<?>"

    def append(self, s):
        """Parse one line of code."""
        self.filelinestack[-1][1] += 1
        self.total_lines += 1
        s = s.strip()
        if not s or s.startswith(('#', '//')):
            return
        self.dokeyword(s.split())

    def extend(self, iterable):
        """Parse an iterable of lines."""
        for line in iterable:
            self.append(line)

    def warn(self, msg):
        self.warnings.extend(
            (tuple(row), "in included file")
            for row in self.filelinestack[:-1]
        )
        self.warnings.append((tuple(self.filelinestack[-1]), msg))

    def print_warnings(self, file=None):
        if len(self.warnings) == 0: return
        outfp = file or sys.stderr
        outfp.write("".join(
            "%s:%s: warning: %s\n" % (file, line, msg)
            for (file, line), msg in self.warnings
        ))

    def cur_obj_type(self):
        return (self.cur_obj[0] if self.cur_obj
                else 'song' if self.cur_song.name
                else 'top level')

    def ensure_in_object(self, parent, allowed_objects):
        allowed_objects = ([allowed_objects]
                           if isinstance(allowed_objects, str)
                           else frozenset(allowed_objects))
        if not self.cur_obj or self.cur_obj[0] not in allowed_objects:
            allowed_objects = sorted(allowed_objects)
            print(allowed_objects, file=sys.stderr)
            article = 'an' if allowed_objects[0].lower()[0] in 'aeiou' else 'a'
            wrong_type = self.cur_obj_type()
            sep = ' ' if len(allowed_objects) < 2 else ', '
            if len(allowed_objects) > 1:
                allowed_objects[-1] = 'or ' + allowed_objects[-1]
            allowed_objects = sep.join(allowed_objects)
            raise ValueError("%s must be inside %s %s, not %s"
                             % (parent, article, allowed_objects, wrong_type))

    # Configuration

    def get_pitchrhy_parent(self):
        """Get the currently open pattern, song, or project in that order.

Used to find the target of a time, scale, durations, or notenames command.

"""
        return (self.cur_obj[1]
                if self.cur_obj is not None and self.cur_obj[0] == 'pattern'
                else self.cur_song
                if self.cur_song is not None
                else self)

    def add_title(self, words):
        self.cur_obj = None
        title = " ".join(words[1:])
        if self.cur_song:
            self.cur_song.title = title
        else:
            self.title = title

    def add_author(self, words):
        self.cur_obj = None
        title = " ".join(words[1:])
        if self.cur_song:
            self.cur_song.author = title
        else:
            self.author = title

    def add_copyright(self, words):
        self.cur_obj = None
        title = " ".join(words[1:])
        if self.cur_song:
            raise ValueError("copyright must be at top level, not song")
        self.copyright = title

    def add_notenames(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: notenames LANGUAGE")
        self.get_pitchrhy_parent().pitchctx.set_language(words[1])

    def add_durations(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: durations BEHAVIOR")
        rhyctx = self.get_pitchrhy_parent().rhyctx
        language = words[1].lower()
        if language == 'temporary':
            rhyctx.durations_stick = False 
        elif language == 'stick':
            rhyctx.durations_stick = True
        else:
            raise ValueError("unknown durations behavior %s; try temporary or stick"
                             % language)

    def add_mmloctaves(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: mmloctaves on|off")
        pitchctx = self.get_pitchrhy_parent().pitchctx
        value = words[1].lower()
        try:
            value = self.boolean_names[value]
        except KeyError:
            raise ValueError("unknown MML octaves behavior %s; try on or off"
                             % value)
        pitchctx.mml_octaves = value

    boolean_names = {
        'on': True, 'true': True, 'yes': True,
        'off': False, 'false': False, 'no': False
    }

    # Instruments

    def add_sfx(self, words):
        if len(words) != 4 or words[2] != 'on':
            raise ValueError("must have 4 words: sfx SFXNAME on CHANNELTYPE")
        _, name, _, channel = words
        try:
            channel = channeltypes[channel]
        except KeyError:
            raise ValueError("unknown channel; try pulse, triangle, or noise")
        if self.cur_song is not None:
            name = '::'.join((self.cur_song.name, name))
        if name in self.sfxs:
            file, line = self.sfxs[name].fileline
            raise ValueError("sfx %s was already defined at %s line %d"
                             % (name, file, line))
        inst = PentlySfx(channel, pitchctx=self.pitchctx,
                         name=name, fileline=tuple(self.filelinestack[-1]),
                         orderkey=self.total_lines,
                         warn=self.warn)
        self.sfxs[name] = inst
        self.cur_obj = ('sfx', inst)

    def add_instrument(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: instrument INSTNAME")
        name = words[1]
        if self.cur_song is not None:
            name = '::'.join((self.cur_song.name, name))
        if name in self.instruments:
            file, line = self.instruments[name].fileline
            raise ValueError("instrument %s was already defined at %s line %d"
                             % (name, file, line))
        inst = PentlyInstrument(name=name,
                                fileline=tuple(self.filelinestack[-1]),
                                orderkey=self.total_lines,
                                warn=self.warn)
        self.instruments[name] = inst
        self.cur_obj = ('instrument', inst)

    def add_rate(self, words):
        self.ensure_in_object('rate', 'sfx')
        if len(words) != 2:
            raise ValueError("must have 2 words: rate FRAMESPERSTEP")
        rate = int(words[1])
        self.cur_obj[1].set_rate(rate, fileline=tuple(self.filelinestack[-1]))

    def add_volume(self, words):
        self.ensure_in_object('volume', ('sfx', 'instrument'))
        if len(words) < 2:
            raise ValueError("volume requires at least one step")
        obj = self.cur_obj[1]
        vols = [int(x) for x in obj.expand_runs(words[1:]) if x != '|']
        obj.set_volume(vols, fileline=tuple(self.filelinestack[-1]))

    def add_decay(self, words):
        self.ensure_in_object('decay', 'instrument')
        if len(words) != 2:
            raise ValueError("must have 2 words: decay UNITSPER16FRAMES")
        obj = self.cur_obj[1]
        obj.set_decay(int(words[1]), fileline=tuple(self.filelinestack[-1]))

    def add_timbre(self, words):
        self.ensure_in_object('timbre', ('sfx', 'instrument'))
        if len(words) < 2:
            raise ValueError("timbre requires at least one step")
        obj = self.cur_obj[1]
        obj.set_timbre(words[1:], fileline=tuple(self.filelinestack[-1]))

    def add_pitch(self, words):
        self.ensure_in_object('pitch', ('sfx', 'instrument'))
        if len(words) < 2:
            raise ValueError("pitch requires at least one step")
        obj = self.cur_obj[1]
        obj.set_pitch(words[1:], fileline=tuple(self.filelinestack[-1]))

    def add_detached(self, words):
        self.ensure_in_object('detached', 'instrument')
        if len(words) > 1:
            raise ValueError("detached in instrument takes no arguments")
        self.cur_obj[1].set_detached(True)

    def add_drum(self, words):
        if len(words) not in (3, 4):
            raise ValueError("must have 3 words: drum DRUMNAME")
        self.cur_obj = None
        drumname = words[1]
        if self.cur_song is not None:
            drumname = '::'.join((self.cur_song.name, drumname))
        if drumname in self.drums:
            file, line = self.drums[drumname].fileline
            raise ValueError("drum %s was already defined at %s line %d"
                             % (drumname, file, line))
        d = PentlyDrum(words[2:],
                       name=drumname, orderkey=self.total_lines,
                       fileline=tuple(self.filelinestack[-1]),
                       warn=self.warn)
        self.drums[drumname] = d

    # Songs and patterns

    def add_song(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: song SONGNAME")
        if self.cur_song:
            raise ValueError(self.cur_song.get_unclosed_msg())
        
        self.cur_obj = None
        songname = words[1]
        if songname in self.songs:
            file, line = self.songs[songname].fileline
            raise ValueError("song %s was already defined at %s line %d"
                             % (songname, file, line))
        song = PentlySong(pitchctx=self.pitchctx, rhyctx=self.rhyctx,
                          name=songname, orderkey=self.total_lines,
                          fileline=tuple(self.filelinestack[-1]),
                          warn=self.warn)
        song.title = songname  # default songname
        self.cur_song = self.songs[songname] = song

    def end_song(self, words):
        if not self.cur_song:
            raise ValueError("no song is open")
        song = self.cur_song
        words = ' '.join(words).lower()
        if words == 'fine':
            endcmd = 'fine'
        elif words in ('dal segno', 'dalsegno'):
            endcmd = 'dalSegno'
        elif words in ('da capo', 'dacapo'):
            if song.segno_fileline is not None:
                fileline = song.segno_fileline
                raise ValueError("%s: cannot loop to start because segno was set at %s line %d"
                                 % (song.name, file, line))
            endcmd = 'dalSegno'
        else:
            raise ValueError('song end must be "fine" or "dal segno" or "da capo", not '
                             + end)
        song.conductor.append(endcmd)
        song.bytesize += 1
        self.cur_song = self.cur_obj = None

    def add_segno(self, words):
        if len(words) > 1:
            raise ValueError("segno takes no arguments")
        song = self.cur_song
        if not song:
            raise ValueError("no song is open")
        song.add_segno(fileline=tuple(self.filelinestack[-1]))
        self.cur_obj = None

    def add_mark(self, words):
        if len(words) == 1:
            raise ValueError("mark requires a name (which may contain spaces)")
        markname = ' '.join(words[1:])
        song = self.cur_song
        if not song:
            raise ValueError("mark %s encountered outside song"
                             % markname)
        song.add_mark(markname, fileline=tuple(self.filelinestack[-1]))

    def add_time(self, words):
        if len(words) < 2:
            raise ValueError('no time signature given')
        if len(words) > 2 and (len(words) != 4 or words[2] != 'scale'):
            raise ValueError("time with scale must have 4 words: time N/D scale D")
        try:
            sp = timesignames[words[1].lower()]
        except KeyError:
            sp = words[1].split('/', 1)
        if len(sp) != 2:
            raise ValueError("time signature must be a fraction separated by /")
        timenum, timeden = int(sp[0]), int(sp[1])
        rhyctx = self.get_pitchrhy_parent().rhyctx
        rhyctx.set_time_signature(timenum, timeden)
        if len(words) > 2:
            self.add_scale(words[2:])

    def add_scale(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: scale ROWVALUE")
        target = self.get_pitchrhy_parent()
        target.rhyctx.set_scale(int(words[1]))

    def add_tempo(self, words):
        if not self.cur_song:
            raise ValueError("tempo must be used in a song")
        if len(words) != 2:
            raise ValueError("must have 2 words: tempo BPMVALUE")
        tempo = float(words[1])
        if not 1.0 <= tempo <= 1500.0:
            raise ValueError("tempo must be positive and no more than 1500 rows per minute")
        song = self.cur_song
        song.rhyctx.tempo = tempo  # to be picked up on next wait rows

    def add_resume(self, words):
        if not self.cur_song:
            raise ValueError("resume must be used in a song")
        if self.resume_fileline is not None:
            file, line = self.resume_fileline
            raise ValueError("resume point already set at %s line %d"
                             % (file, line))
        self.resume_fileline = tuple(self.filelinestack[-1])
        self.resume_song = self.cur_song.name
        self.resume_rows = self.cur_song.total_rows

    def add_mute(self, words):
        is_solo = words[0] == 'solo'
        if self.resume_mute_fileline is not None:
            file, line = self.resume_mute_fileline
            raise ValueError("resume muting already set at %s line %d"
                             % (file, line))
        trackbits = 0
        for track in self.cur_song.parse_trackset(words[1:]):
            trackbits |= 1 << track
        if is_solo:
            trackbits = trackbits ^ (1 << 5) - 1
        self.resume_mute = trackbits
        self.resume_mute_fileline = tuple(self.filelinestack[-1])
        self.warn("muting $%02x" % trackbits)
    
    def add_song_wait(self, words):
        if not self.cur_song:
            raise ValueError("at must be used in a song")
        if len(words) < 2:
            raise ValueError("must have 2 words: at MEASURE[:BEAT[:ROW]]")
        song = self.cur_song
        mbr = [int(x) for x in words[1].split(':', 2)]

        # If we're waiting at least one row, update the tempo and
        # put in a wait command
        rows_to_wait = song.rhyctx.wait_for_measure(*mbr)
        song.wait_rows(rows_to_wait)

        self.cur_obj = None  # end any song-local pattern or instrument
        if len(words) > 2:
            self.dokeyword(words[2:])

    def add_pickup(self, words):
        in_a_pattern = self.cur_obj and self.cur_obj[0] == 'pattern'
        if not (in_a_pattern or self.cur_song):
            raise ValueError("pickup: no song or pattern is open")
        if len(words) != 2:
            raise ValueError("must have 2 words: pickup MEASURE[:BEAT[:ROW]]")
        rhyctx = self.get_pitchrhy_parent().rhyctx
        mbr = [int(x) for x in words[1].split(':', 2)]
        rhyctx.set_measure(*mbr)

    @staticmethod
    def extract_prepositions(words):
        return dict(zip(words[2::2], words[3::2]))

    def add_attack(self, words):
        if len(words) != 3 or words[1] != 'on':
            raise ValueError('syntax: attack on CHANNELNAME')
        if self.cur_song.name is None:
            raise ValueError('no song is open')
        self.cur_obj = None
        chname = words[2]
        song = self.cur_song
        song.set_attack(chname)

    def add_play(self, words):
        if len(words) % 2 != 0:
            raise ValueError('syntax: pattern PATTERNNAME [on TRACK] [with INSTRUMENT]')
        if self.cur_song.name is None:
            raise ValueError('no song is open')
        self.cur_obj = None
        patname = words[1]
        pps = self.extract_prepositions(words)
        track = pps.pop('on', None)
        instrument = pps.pop('with', None)
        transpose = int(pps.pop('up', 0)) - int(pps.pop('down', 0))
        if pps:
            raise ValueError("unknown prepositions: " + " ".join(pps))
        song = self.cur_song
        song.play(patname, track=track, instrument=instrument,
                  transpose=transpose)

    def add_stop(self, words):
        if self.cur_song.name is None:
            raise ValueError('no song is open')
        self.cur_obj = None
        if len(words) < 2:
            raise ValueError('must stop at least one track')
        self.cur_song.stop_tracks(words[1:])

    def add_pattern(self, words):
        if len(words) % 2 != 0:
            raise ValueError('syntax: pattern PATTERNNAME [on TRACK] [with INSTRUMENT]')
        patname = words[1]
        if patname in self.patterns:
            file, line = self.patterns[patname].fileline
            raise ValueError("pattern %s was already defined at %s line %d"
                             % (patname, file, line))
        if self.cur_song is not None:
            patname = '::'.join((self.cur_song.name, patname))
            pitchrhy = self.cur_song
        else:
            pitchrhy = self

        pps = self.extract_prepositions(words)
        track = pps.pop('on', None)
        if track and track not in pitched_tracks:
            raise ValueError('unknown track ' + track)
        instrument = pps.pop('with', None)
        if pps:
            raise ValueError("unknown prepositions: " + " ".join(pps))

        pat = PentlyPattern(pitchctx=pitchrhy.pitchctx, rhyctx=pitchrhy.rhyctx,
                            instrument=instrument, track=track,
                            name=patname, orderkey=self.total_lines,
                            fileline=tuple(self.filelinestack[-1]),
                            warn=self.warn)
        self.patterns[patname] = pat
        self.cur_obj = ('pattern', pat)

    def add_fallthrough(self, words):
        if len(words) > 1:
            raise ValueError("fallthrough takes no arguments")
        self.ensure_in_object('fallthrough', 'pattern')
        self.cur_obj[1].set_fallthrough(True)
        self.cur_obj = None

    def add_include(self, words):
        if len(self.filelinestack) >= 20:
            self.warn("approaching limbo")
            raise ValueError("include nested too deeply")
        
        # XXX: Impossible to include a file that includes multiple
        # consecutive spaces or whitespace other than " " (U+0020)
        path = " ".join(words[1:])
        if not path:
            raise ValueError('include requires a path')
        with open(path, "r") as infp:
            self.filelinestack.append([path, 0])
            self.extend(infp)
            del self.filelinestack[-1]

    def add_definition(self, name, value):
        if name.startswith('EN'):
            self.get_pitchrhy_parent().pitchctx.add_arp_name(name[2:], value)
            return

        raise ValueError("unknown definable %s" % repr(name))

    keywordhandlers = {
        'notenames': add_notenames,
        'durations': add_durations,
        'mmloctaves': add_mmloctaves,
        'title': add_title,
        'author': add_author,
        'copyright': add_copyright,
        'sfx': add_sfx,
        'volume': add_volume,
        'rate': add_rate,
        'decay': add_decay,
        'timbre': add_timbre,
        'pitch': add_pitch,
        'instrument': add_instrument,
        'drum': add_drum,
        'detached': add_detached,
        'song': add_song,
        'fine': end_song,
        'dal': end_song,
        'dalSegno': end_song,
        'da': end_song,
        'daCapo': end_song,
        'segno': add_segno,
        'mark': add_mark,
        'time': add_time,
        'scale': add_scale,
        'attack': add_attack,
        'pattern': add_pattern,
        'fallthrough': add_fallthrough,
        'at': add_song_wait,
        'pickup': add_pickup,
        'resume': add_resume,
        'mute': add_mute,
        'solo': add_mute,
        'tempo': add_tempo,
        'play': add_play,
        'stop': add_stop,
        'include': add_include,
    }

    def dokeyword(self, words):
        if words[0].startswith('@'):
            defmatch = ' '.join(words).split("=", 1)
            if len(defmatch) > 1:
                self.add_definition(defmatch[0][1:].rstrip(), defmatch[1].strip())
                return

        try:
            kwh = self.keywordhandlers[words[0]]
        except KeyError:
            pass
        else:
            return kwh(self, words)
        if self.cur_obj and self.cur_obj[0] == 'pattern':
            pat = self.cur_obj[1]
            for word in words:
                pat.add_pattern_note(word)
            return
        if self.unk_keywords < 10:
            if self.cur_obj:
                type_name = " ".join((self.cur_obj[0], self.cur_obj[1].name))
            elif self.cur_song:
                type_name = "song " + self.cur_song.name
            else:
                type_name = "top level"
            self.warn("ignoring unknown keyword %s in %s"
                      % (repr(words[0]), type_name))
        self.unk_keywords += 1

# Finding pieces of data that can overlap each other ################

# Perfect optimization of these is unlikely in the near future
# because the shortest common supersequence problem is NP-complete.
# So instead, we limit the optimization to cases where one entire
# envelope is a supersequence of another.  This is polynomial even
# with a naive greedy algorithm.

def subseq_pack(subseqs):
    # out_seqs is a list of tuples of the form (index into subseqs,
    # sequence data).  We want to find the LONGEST sequence that
    # contains each.
    inclen_seqs = sorted(enumerate(subseqs), key=lambda x: len(x[1]))

    def handle_one_seq(inclen_seqs, i):
        subseq = inclen_seqs[i][1]
        for candidate in range(len(inclen_seqs) - 1, i, -1):
            ckey, longerdata = inclen_seqs[candidate]
            for startidx in range(0, len(longerdata) - len(subseq) + 1):
                if (subseq[0] == longerdata[startidx]
                    and subseq == longerdata[startidx:startidx + len(subseq)]):
                    return ckey, startidx, startidx + len(subseq)
        return None

    out_seqs = [None] * len(inclen_seqs)

    # Each element out_seqs[i] is either a tuple
    # (index of longer sequence in subseqs, slice start, slice end)
    # if a match for subseqs[i] is found among longer sequences,
    # or None otherwise.
    for i in range(len(inclen_seqs)):
        key = inclen_seqs[i][0]
        out_seqs[key] = handle_one_seq(inclen_seqs, i)
    return out_seqs

# Rendering #########################################################

def print_all_dicts(parser):
    print("\n;Parsed %d lines, with %d using a keyword not yet implemented"
          % (parser.total_lines, parser.unk_keywords))
    dicts_to_print = [
        ('Sound effects', parser.sfxs),
        ('Instruments', parser.instruments),
        ('Drums', parser.drums),
        ('Songs', parser.songs),
        ('Patterns', parser.patterns),
    ]
    for name, d in dicts_to_print:
        print(";%s (%d)" % (name, len(parser.sfxs)))
        print("\n".join(";%s\n;  %s" % (name, json.dumps(el))
                        for name, el in d.items()))

def wrapdata(atoms, lineprefix, maxlength=79):
    lpfx = len(lineprefix)
    maxlength -= lpfx
    out, lout = [], 0
    for atom in atoms:
        lthis = len(atom)
        if len(out) > 0 and lthis + lout > maxlength:
            yield lineprefix+','.join(out)
            out, lout = [], 0
        out.append(atom)
        lout += lthis + 1
    yield lineprefix+','.join(out)

MAX_REHEARSAL_MARKS = 15

def render_rehearsal(parser):
    """Render the rehearsal marks

A pointer table called pently_rehearsal_marks points to the start of
each song's rehearsal mark table, which consists of the following:

byte: Number of rehearsal marks
byte: Reserved for future use
16-bit words: Number of rows preceding each rehearsal mark
n bytes: ASCII encoded rehearsal mark names, separated by $0A,
    terminated by $00
"""
    songs = sorted(parser.songs.items(), key=lambda x: x[1].orderkey)
    lines = [
        "; Rehearsal mark data begin",
        ".exportzp pently_resume_song",
        ".export pently_rehearsal_marks, pently_resume_rows:absolute",
        "pently_rehearsal_marks:"
    ]
    rmidxnames = ["PRM_%s" % row[0] for row in songs]
    lines.extend(wrapdata(rmidxnames, ".addr "))

    resume_song = resume_rows = 0
    for i, (songname, songdata) in enumerate(songs):
        if parser.resume_song == songname:
            resume_song, resume_rows = i, parser.resume_rows
        rm = [
            (name, rows)
            for name, (rows, linenum) in songdata.rehearsal_marks.items()
        ]
        if len(rm) > MAX_REHEARSAL_MARKS:
            parser.warn("%s has %d rehearsal marks; only %d will fit"
                        % (songname, len(rm), MAX_REHEARSAL_MARKS))
        rm.sort(key=lambda row: row[1])
        lines.extend([
            "",
            "PRM_%s:" % songname,
            ".byte %2d  ; number of rehearsal marks" % len(rm),
            ".byte  0  ; reserved"
        ])

        if rm:
            rmrowsdata = ("%d" % row[1] for row in rm)
            lines.extend(wrapdata(rmrowsdata, ".word "))
            rmnames = "\n".join(row[0] for row in rm)
            rmnamesdata = ["%d" % x for x in rmnames.encode("ascii")]
            rmnamesdata.append("0")
            lines.extend(wrapdata(rmnamesdata, ".byte "))

    lines.extend([
        "pently_resume_song = %d" % resume_song,
        "pently_resume_rows = %d" % resume_rows,
        "; Rehearsal mark end"
    ])
    return lines

def render_file(parser, segment='RODATA'):
    if len(parser.songs) == 0:
        raise IndexError("no songs defined")

    # each entry in this row is a tuple of the form
    # list, name of directory table, include asmnames in export,
    # include in byte subsequence packing
    parts_to_print = [
        (parser.sfxs, 'pently_sfx_table', True,
         True),
        (parser.instruments, 'pently_instruments', True,
         True),
        (parser.drums, 'pently_drums', False,
         False),
        (parser.patterns, 'pently_patterns', False,
         False),
        (parser.songs, 'pently_songs', True,
         False),
    ]

    # Pack byte arrays that are subsequences of another byte array
    # into the longer one
    subseq_pool_directory = []
    subseq_pool_data = []
    for ptpidx, row in enumerate(parts_to_print):
        things, deflabel, _, is_bytes = row
        for thingkey, thing in things.items():
            thing.render(scopes=parser)
            if thing.asmdata and is_bytes:
                subseq_pool_directory.append(thing.asmdataname)
                subseq_pool_data.append(thing.asmdata)
    subseq_packed = subseq_pack(subseq_pool_data)
    subseq_packed = {
        k: v
        for k, v in zip(subseq_pool_directory, subseq_packed)
        if v
    }

    lines = [
        '; title: ' + parser.title,
        '; author: ' + parser.author,
        '; copyright: ' + parser.copyright,
        ';',
        '.include "../../src/pentlyseq.inc"',
        '.segment "%s"' % segment,
        'NUM_SONGS=%d' % len(parser.songs),
        'NUM_SOUNDS=%d' % len(parser.sfxs),
        '.exportzp NUM_SONGS, NUM_SOUNDS',
    ]
    all_export = []
    all_exportzp = ['pently_resume_mute']
    bytes_lines = []
    songbytes = {'': 0}
    total_partbytes = 0
    for row in parts_to_print:
        things, deflabel, exportable, is_bytes = row

        # Count the size attributable to each song
        for name, tng in things.items():
            name = name.split("::", 1)
            song_specific = len(name) > 1 or isinstance(tng, PentlySong)
            name = name[0] if song_specific else ''
            songbytes[name] = songbytes.get(name, 0) + tng.bytesize

        fmtfunc = str if is_bytes else None
        defs1 = sorted(things.values(), key=lambda x: x.orderkey)
        if exportable:
            all_exportzp.extend(thing.asmname for thing in defs1)
        all_export.append(deflabel)

        entries_plural = "entry" if len(defs1) == 1 else "entries"
        partbytes = sum(thing.bytesize for thing in defs1)
        total_partbytes += partbytes
        lines.append("%s:  ; %d %s, %d bytes"
                     % (deflabel, len(defs1), entries_plural, partbytes))
        lines.extend(thing.asmdef for thing in defs1)
        for thing in defs1:

            # Skip renderables without any data array
            if not thing.asmdata: continue

            # Use the packed array if it exists
            packresult = subseq_packed.get(thing.asmdataname)
            if packresult is not None:
                diridx, startoffset, endoffset = packresult
                assert endoffset - startoffset == len(thing.asmdata)
                line = ('%s = %s + %d'
                        % (thing.asmdataname, subseq_pool_directory[diridx],
                           startoffset))
                lines.append(line)
                continue

            # Otherwise, emit the array
            lines.append("%s:" % thing.asmdataname)
            data = ((fmtfunc(s) for s in thing.asmdata)
                    if fmtfunc
                    else thing.asmdata)
            if thing.asmdataprefix:
                data = wrapdata(data, thing.asmdataprefix)
            lines.extend(data)

        bytes_lines.append('; %s: %d bytes' % (deflabel, partbytes))
        bytes_lines.extend(';   %s: %d bytes' % (thing.asmname, thing.bytesize)
                           for thing in defs1)

    lines.extend([
        '',
        '; Make music data available to Pently'
    ])
    lines.extend(wrapdata(all_export, ".export "))
    lines.extend([
        '',
        '; Sound effect, instrument, and song names for your program to .importzp'
    ])
    lines.extend(wrapdata(all_exportzp, ".exportzp "))
    lines.append("pently_resume_mute = $%02X" % parser.resume_mute)
    lines.extend([
        '',
        '; Total music data size: %d bytes' % total_partbytes
    ])
    lines.extend(bytes_lines)
    lines.extend([
        ";",
        "; Breakdown by song",
        ";   Shared: %d bytes" % songbytes['']
    ])
    lines.extend(
        ";   Song %s: %d bytes" % (k, v)
        for (k, v) in sorted(songbytes.items())
        if k
    )

    lines.append('')
    return lines

def ca65_escape_bytes(blo):
    """Encode an iterable of ints in 0-255, mostly ASCII, for ca65 .byte statement"""
    runs = []
    for c in blo:
        if 32 <= c <= 126 and c != 34:
            if runs and isinstance(runs[-1], bytearray):
                runs[-1].append(c)
            else:
                runs.append(bytearray([c]))
        else:
            runs.append(c)
    return ','.join('"%s"' % r.decode('ascii')
                    if isinstance(r, bytearray)
                    else '%d' % r
                    for r in runs)

def bytes_strcpy(b, length):
    """Crop or NUL-pad to exactly length bytes"""
    b = b[:32]
    return bytes(b) + bytes(32 - len(b))

def render_include_file(parser):
    title_utf8 = parser.title.encode("utf-8")
    author_utf8 = parser.author.encode("utf-8")
    copyright_utf8 = parser.copyright.encode("utf-8")

    lines = [
        '; title: ' + parser.title,
        '; author: ' + parser.author,
        '; copyright: ' + parser.copyright,
        ';',
        'NUM_SONGS=%d' % len(parser.songs),
        'NUM_SOUNDS=%d' % len(parser.sfxs),
        "",
        ".macro PENTLY_WRITE_NSFE_TITLE",
        "  .byte "+ca65_escape_bytes(title_utf8),
        ".endmacro",
        ".macro PENTLY_WRITE_NSFE_AUTHOR",
        "  .byte "+ca65_escape_bytes(author_utf8),
        ".endmacro",
        ".macro PENTLY_WRITE_NSFE_COPYRIGHT",
        "  .byte "+ca65_escape_bytes(copyright_utf8),
        ".endmacro",
        ".macro PENTLY_WRITE_NSF_TITLE",
        "  .byte "+ca65_escape_bytes(bytes_strcpy(title_utf8, 32)),
        ".endmacro",
        ".macro PENTLY_WRITE_NSF_AUTHOR",
        "  .byte "+ca65_escape_bytes(bytes_strcpy(author_utf8, 32)),
        ".endmacro",
        ".macro PENTLY_WRITE_NSF_COPYRIGHT",
        "  .byte "+ca65_escape_bytes(bytes_strcpy(copyright_utf8, 32)),
        ".endmacro",
        "",
    ]

    # Assembly names of everything
    parts_to_print = [parser.sfxs, parser.instruments, parser.songs]
    parts_to_print = [
        sorted(objs.values(), key=lambda x: x.orderkey)
        for objs in parts_to_print
    ]
    songs = parts_to_print[2]
    for objs in parts_to_print:
        lines.extend(
            "%s = %i" % (obj.asmname, i) for i, obj in enumerate(objs)
        )

    # Macros to write song names
    lines.append(".macro PENTLY_WRITE_SONG_TITLES terminator")
    lines.extend(
        "PSTITLE_%d: .byte %s, terminator"
        % (i, ca65_escape_bytes(song.title.encode("utf-8")))
        for i, song in enumerate(songs)
    )
    lines.append(".endmacro")
    lines.append(".macro PENTLY_WRITE_SONG_TITLE_PTRS")
    lines.extend(
        "  .addr PSTITLE_%d" % i for i in range(len(songs))
    )
    lines.append(".endmacro")

    lines.append(".macro PENTLY_WRITE_SONG_AUTHORS terminator")
    lines.extend(
        "PSAUTHOR_%d: .byte %s, terminator"
        % (i, ca65_escape_bytes((song.author or parser.author).encode("utf-8")))
        for i, song in enumerate(songs)
    )
    lines.append(".endmacro")
    lines.append(".macro PENTLY_WRITE_SONG_AUTHOR_PTRS")
    lines.extend(
        "  .addr PSAUTHOR_%d" % i for i in range(len(songs))
    )
    lines.append(".endmacro")

    lines.append('')
    return lines

# Period table generation ###########################################

region_period_numerator = {
    'ntsc': 39375000.0/(22 * 16),
    'pal': 266017125.0/(10 * 16 * 16),
    'dendy': 266017125.0/(10 * 16 * 15)
}

def getPeriodValues(maxNote=64, region='ntsc', a=440.0):
    numerator = region_period_numerator[region.strip().lower()]
    octaveBase = numerator / (a/8.0)
    semitone = 2.0**(1./12)
    relFreqs = [(1 << (i // 12)) * semitone**(i % 12)
                for i in range(maxNote)]
    periods = [min(2048, int(round(octaveBase / freq))) - 1
               for freq in relFreqs]
    return periods

def parse_argv(argv):
    warntypes = ['error']
    parser = argparse.ArgumentParser()
    parser.add_argument("infilename", nargs='?',
                        help='Pently-MML file to process or - for standard input; omit for period table only')
    parser.add_argument("-o", "--output", metavar='OUTFILENAME',
                        help='write output to a file instead of standard output')
    parser.add_argument("--write-inc", metavar='INCFILENAME',
                        help='write metadata as include file')
    parser.add_argument("--periods", type=int, default=0,
                        metavar='LENGTH',
                        help='include a period table in the output; LENGTH is usually 64 to 80')
    parser.add_argument("--period-region", default='ntsc',
                        choices=sorted(region_period_numerator.keys()),
                        help='make period table for this region (default: ntsc)')
    parser.add_argument("-A", "--period-tuning", type=float, default=440.0,
                        metavar='FREQ',
                        help='frequency in Hz of A above middle C (default: 440)')
    parser.add_argument("--segment", default='RODATA',
                        help='place output in this segment (default: RODATA)')
    parser.add_argument("--rehearse", action='store_true',
                        help='include rehearsal mark data in output')
    parser.add_argument("-v", '--verbose', action="store_true",
                        help='show tracebacks and other verbose diagnostics')
    parser.add_argument("-W", '--warn', action="append", choices=warntypes,
                        help='enable warning options')
    args = parser.parse_args(argv[1:])
    args.warn = set(args.warn or [])
    if not args.infilename and not args.periods:
        parser.error('at least one of infilename and --periods is required')
    if args.write_inc and not args.infilename:
        parser.error("cannot write include file without infilename")
    if args.periods < 0:
        parser.error('NUMSEMITONES cannot be negative')
    if args.periods > 88:
        parser.error('2A03 not precise enough for NUMSEMITONES > 88')
    min_tuning = region_period_numerator[args.period_region] / 256
    if args.period_tuning < min_tuning:
        msg = ("tuning below %.1f Hz in %s makes 'a,,' unreachable"
               % (min_tuning, args.period_region))
        if 'error' in args.warn:
            parser.error(msg)
        else:
            print("%s: warning: %s" % (parser.prog, msg), file=sys.stderr)
    return args

def main(argv=None):
    argv = argv or sys.argv
    prog = os.path.basename(argv[0])
    args = parse_argv(argv)

    lines = [
        '; Generated using Pently music assembler'
    ]
    if args.infilename:
        is_stdin = args.infilename == '-'
        display_filename = "<stdin>" if is_stdin else args.infilename
        parser = PentlyInputParser(filename=display_filename)
        infp = sys.stdin if is_stdin else open(args.infilename, 'r')
        try:
            parser.extend(infp)
            if parser.cur_song:
                parser.warn(parser.cur_song.get_unclosed_msg())
            lines.append('; Music from ' + display_filename)
            lines.extend(render_file(parser, args.segment))
            if args.rehearse:
                lines.extend(render_rehearsal(parser))
        except Exception as e:
            if args.verbose:
                import traceback
                traceback.print_exc()
            file, line = tuple(parser.filelinestack[-1])
            print("%s:%d: %s" % (file, line, e), file=sys.stderr)
            sys.exit(1)
        finally:
            if not is_stdin:
                infp.close()
            parser.print_warnings()

    if 'error' in args.warn:
        print("%s: exiting due to warnings (-Werror)" % (prog,),
              file=sys.stderr)
        sys.exit(1)

    if args.periods > 0:
        periods = getPeriodValues(args.periods, args.period_region,
                                  a=args.period_tuning)
        lines.extend([
            '; Period table of length %d for %s: %d bytes'
            % (args.periods, args.period_region, args.periods * 2),
            '.export periodTableLo, periodTableHi',
            'periodTableLo:'
        ])
        lines.extend(wrapdata(("$%02x" % (x & 0xFF) for x in periods), '.byt '))
        lines.append('periodTableHi:')
        lines.extend(wrapdata((str(x >> 8) for x in periods), '.byt '))

    is_stdout = not args.output or args.output == '-'
    outfp = sys.stdout if is_stdout else open(args.output, 'w')
    lines.append('')
    try:
        outfp.write('\n'.join(lines))
    finally:
        if not is_stdout:
            outfp.close()
    if args.write_inc:
        lines = render_include_file(parser)
        with open(args.write_inc, "w") as outfp:
            outfp.write("\n".join(lines))

if __name__=='__main__':
##    main(["pentlyas", "../src/musicseq.pently"])
    main()
