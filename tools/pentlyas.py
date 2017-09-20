#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Pently audio engine
# Music assembler
#
# Copyright 2015-2017 Damian Yerrick
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
    'pp': 1, 'mp': 2, 'mf': 3, 'ff': 4
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

class PentlyPitchContext(object):
    """

Six octave modes are recognized at various places:

'drum' -- any word that starts and ends with a letter a pitch
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
last_chord -- last (pitch, arpeggio) used in an o; used for note 'q'
arp_names

"""

    def __init__(self, other=None, language='english'):
        if other is None:
            self.set_language(language)
            self.reset_octave(octave_mode=None)
            self.reset_arp()
            self.simul_notes = False
            self.arp_names = ChainMap({}, default_arp_names)
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

    def reset_octave(self, octave_mode='unchanged'):
        self.last_octave = (3, 0)
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
        if notename in ('r', 'w', 'l'):
            if not (preoctave or accidental or postoctave):
                # Rests kill a single-note arpeggio.
                # Waits and length changes preserve it.
                if notename == 'r':
                    self.arp_mod = arp
                arp = arp or self.arp_mod or self.last_arp
                return self.fixup_downward_arp(notename, arp)
            nonpitchtypes = {'r': 'rests', 'w': 'waits', 'l': 'length changes'}
            modifier = ("octave changes" if postoctave or preoctave
                        else "accidentals")
            raise ValueError("%s: %s can't have %s"
                             % (pitch, nonpitchtypes[notename], modifier))
            
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
        return self.fixup_downward_arp(notenum, arp)

    pitchRE = re.compile(r"""
(>*|<*)       # MML style octave
([a-hrwlq])    # note name
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

Return (pitch, number of rows, slur) or None if it's not actually a note.

"""

        pitcharp, denom, augment, slur = notematch[:4]
        if pitcharp[0] == 'l':
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
        measure, row, _, _ = self.parse_measure(measure, beat, row)
        self.cur_measure, self.row_in_measure = measure, row

    def wait_for_measure(self, measure, beat=1, row=0):
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

class PentlyRenderable(object):

    nonalnumRE = re.compile("[^a-zA-Z0-9]")

    def __init__(self, name=None, linenum=None):
        self.name, self.linenum = name, linenum
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

    def __init__(self, name=None, linenum=None):
        super().__init__(name, linenum)
        self.timbre = self.volume = self.pitch = None
        self.pitch_looplen = self.timbre_looplen = 1

    def set_volume(self, volumes, linenum=None):
        if self.volume is not None:
            raise ValueError("volume for %s was already set on line %d"
                             % (self.name, self.volume_linenum))
        volumes = list(volumes)
        if not all(0 <= x <= 15 for x in volumes):
            raise ValueError("volume steps must be 0 to 15")
        self.volume, self.volume_linenum = volumes, linenum

    @staticmethod
    def pipesplit(words):
        pipesplit = ' '.join(words).split('|', 1)
        out = pipesplit[0].split()
        if len(pipesplit) > 1:
            afterloop = pipesplit[1].split()
            looplen = len(afterloop)
            out.extend(afterloop)
        else:
            looplen = None
        return out, looplen

    def get_max_timbre(self):
        return 3

    def set_timbre(self, timbrewords, linenum=None):
        if self.timbre is not None:
            raise ValueError("timbre for %s %s was already set on line %d"
                             % (self.cur_obj[0], self.cur_obj[1].name,
                                volumedthing['timbre_linenum']))
        timbres, looplen = self.pipesplit(timbrewords)
        timbres = [int(x) for x in timbres]
        maxduty = self.get_max_timbre()
        if not all(0 <= x <= maxduty for x in timbres):
            raise ValueError("timbre steps must be 0 to %d" % maxduty)
        self.timbre, self.timbre_looplen = timbres, looplen or 1
        self.timbre_linenum = linenum

    def parse_pitchenv(self, pitchword):
        """Parse an element of a pitch envelope.

The set_pitch() method calls this once per pitch word.  Subclasses
may initialize any necessary state in their __init__() method or in
an overridden set_pitch().

If not overridden, this abstract method raises NotImplementedError.

"""
        raise NotImplementedError

    def set_pitch(self, pitchwords, linenum=None):
        if self.pitch is not None:
            raise ValueError("pitch for %s %s was already set on line %d"
                             % (self.cur_obj[0], self.cur_obj[1].name,
                                volumedthing['pitch_linenum']))
        pitches, looplen = self.pipesplit(pitchwords)
        pitches = [self.parse_pitchenv(pitch) for pitch in pitches]
        self.pitch, self.pitch_looplen = pitches, looplen or 1
        self.pitch_linenum = linenum

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
        attackdata = [t | (v << 8) | (p & 0xFF)
                      for t, v, p in zip(xtimbre, volume, pitch)]
        return timbre, volume, pitch, attackdata

class PentlyInstrument(PentlyEnvelopeContainer):

    def __init__(self, name=None, linenum=None):
        """Set up a new instrument.

name, linenum -- used in duplicate error messages

"""
        super().__init__(name, linenum)
        self.detached = self.decay = None

    def set_decay(self, rate, linenum=None):
        if not 0 <= rate <= 127:
            raise ValueError("decay must be 1 to 127 units per 16 frames, not %d"
                             % rate)
        if self.decay is not None:
            raise ValueError("decay for %s was already set on line %d"
                             % (self.name, self.decay_linenum))
        self.decay, self.decay_linenum = rate, linenum

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

    def render(self, scopes=None):
        timbre, volume, pitch, attackdata = self.render_tvp()
        del attackdata[-1]
        sustaintimbre = timbre[-1]
        sustainvolume = volume[-1]
        decay = self.decay or 0
        detached = 1 if self.detached else 0

        asmname = self.get_asmname(self.name)
        self.asmname = 'PI_'+asmname
        self.asmdef = ("instdef PI_%s, %d, %d, %d, %d, %s, %d"
                       % (asmname, sustaintimbre, sustainvolume, decay,
                          detached, 'PIDAT_'+asmname if attackdata else '0',
                          len(attackdata)))
        self.asmdataname = 'PIDAT_'+asmname
        self.asmdataprefix = '.dbyt '
        self.asmdata = attackdata
        self.bytesize = len(attackdata) * 2 + 5

class PentlySfx(PentlyEnvelopeContainer):

    def __init__(self, channel_type, pitchctx=None, name=None, linenum=None):
        """Set up a new sound effect.

channel_type -- 0 for pulse, 2 for triangle, or 3 for noise
name, linenum -- used in duplicate error messages

"""
        super().__init__(name, linenum)
        self.rate, self.channel_type = None, channel_type
        self.pitchctx = PentlyPitchContext(pitchctx)
        octave_mode = 'noise' if channel_type == 3 else 'absolute'
        self.pitchctx.reset_octave(octave_mode=octave_mode)

    def set_rate(self, rate, linenum=None):
        """Sets the playback rate of a sound effect."""
        if not 1 <= rate <= 16:
            raise ValueError("rate must be 1 to 16 frames per step, not %d"
                             % rate)
        if self.rate is not None:
            raise ValueError("rate for %s was already set on line %d"
                             % (self.cur_obj[1].name,
                                rated_sfx['rate_linenum']))
        self.rate, self.rate_linenum = rate, linenum

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
        while len(volume) > 1 and volume[-1] == 0:
            del volume[-1], attackdata[-1]

        asmname = self.get_asmname(self.name)
        self.asmname = 'PE_'+asmname
        self.asmdef = ("sfxdef PE_%s, PEDAT_%s, %d, %d, %d"
                       % (asmname, asmname,
                          len(attackdata), rate, self.channel_type))
        self.asmdataname = 'PEDAT_'+asmname
        self.asmdataprefix = '.dbyt '
        self.asmdata = attackdata
        self.bytesize = len(attackdata) * 2 + 4

class PentlyDrum(PentlyRenderable):

    drumnameRE = re.compile('([a-zA-Z_].*[a-zA-Z_])$')

    def __init__(self, sfxnames, name, linenum=None):
        super().__init__(name, linenum)
        if not self.drumnameRE.match(name):
            raise ValueError("drum names must begin and end with letter or '_'")
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
                 name=None, linenum=None):
        super().__init__(name, linenum)
        self.pitchctx = PentlyPitchContext(pitchctx)
        self.rhyctx = PentlyRhythmContext(rhyctx)
        self.rhyctx.tempo = 100.0
        self.last_rowtempo = self.segno_linenum = self.last_beatlen = None
        self.conductor = []
        self.bytesize = 2

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

    def stop_tracks(self, tracks):
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
        abstract_cmds = [('stopPat', track) for track in tracks_to_stop]
        self.conductor.extend(abstract_cmds)
        self.bytesize += 4 * len(abstract_cmds)

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
                if track != 'drum' and pat.transpose is None:
                    raise ValueError("%s: pitched track %s has only rests; use stopPat instead"
                                     % (self.name, patname))
                if track == 'drum':
                    if pat.track != 'drum':
                        raise ValueError('cannot play pitched pattern %s on drum track'
                                         % (patname,))
                    out.append("playPatNoise %s" % pat.asmname)
                    continue
                if pat.track == 'drum':
                    raise ValueError('%s: cannot play drum pattern %s on pitched track'
                                     % (self.name, patname))
                if isinstance(track, str):
                    track = pitched_tracks[track]
                if track is None:
                    raise ValueError("%s: no track for pitched pattern %s"
                                     % (self.name, patname))
                transpose += pat.transpose
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
                 instrument=None, track=None, name=None, linenum=None):
        super().__init__(name, linenum)
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
([a-hrwl])        # note name
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
        semi = self.pitchctx.parse_pitch(
            preoctave, notename, accidental, postoctave, arp.lstrip(':')
        )
        if isinstance(semi, tuple) and semi[1]:
            assert not semi[1].startswith('-')
        duration, duraugment = self.rhyctx.parse_duration(duration, duraugment)
        return semi, duration, duraugment, slur

    drumnoteRE = re.compile(r"""
([a-zA-Z_][0-9a-zA-Z_]*[a-zA-Z_]|[lrw])  # drum name, length, rest, or wait
([0-9]*)       # duration
(|\.|\.\.|g)$  # duration augment
""", re.VERBOSE)

    def parse_drum_note(self, pitch):
        m = self.drumnoteRE.match(pitch)
        if not m:
            return None, None, None, None
        (notename, duration, duraugment) = m.groups()
        duration, duraugment = self.rhyctx.parse_duration(duration, duraugment)
        if notename == 'r':
            notename = 'w'
        return notename, duration, duraugment, False

    arpeggioRE = re.compile(r"""
EN(-?(?:
  [a-zA-Z][0-9a-zA-Z]*|[0-9a-fA-F]{1,2}  # arpeggio chord name
)(?:/[12]|))      # inversion
""", re.VERBOSE)
    vibratoRE = re.compile("MP(OF|[0-9a-fA-F])$")
    portamentoRE = re.compile("EP(OF|[0-2][0-9a-fA-F])$")
    def add_pattern_note(self, word):
        if word in ('absolute', 'orelative', 'relative'):
            if self.pitchctx.octave_mode == 'drum':
                raise ValueError("drum pattern's octave mode cannot be changed")
            self.pitchctx.octave_mode = word
            return

        volmatch = volcodes.get(word)
        if volmatch is not None:
            self.notes.append("CHVOLUME,%d" % volmatch)
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
            print("warning: malformed arpeggio %s" % repr(word),
                  file=sys.stderr)

        # EPxx: Portamento rate
        slidematch = (self.portamentoRE.match(word)
                      if self.pitchctx.octave_mode != 'drum'
                      else None)
        if slidematch:
            self.notes.append("BEND,$"+slidematch.group(1))
            return
        if word.startswith("EP") and not slidematch:
            print("warning: malformed portamento %s" % repr(word),
                  file=sys.stderr)

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
                if notematch[0][0] not in ('l', 'r', 'w'):
                    raise ValueError("%s is ambiguous: it could be a drum or a pitch"
                                     % word)
                f = self.rhyctx.fix_note_duration(drummatch)
                if f: self.notes.append(f)
                return
            elif drummatch[0] is not None:
                self.track = self.pitchctx.octave_mode = 'drum'
                f = self.rhyctx.fix_note_duration(drummatch)
                if f: self.notes.append(f)
                return
            elif notematch[0] is not None:
                self.pitchctx.set_pitched_mode()
                f = self.rhyctx.fix_note_duration(notematch)
                if f: self.notes.append(f)
                return
            else:
                raise ValueError("unknown first note %s" % word)

        if self.pitchctx.octave_mode == 'drum':
            drummatch = self.parse_drum_note(word)
            if drummatch[0] is not None:
                f = self.rhyctx.fix_note_duration(drummatch)
                if f: self.notes.append(f)
            else:
                raise ValueError("unknown drum pattern note %s" % word)
            return

        notematch = self.parse_note(word)
        if notematch[0] is not None:
            f = self.rhyctx.fix_note_duration(notematch)
            if f: self.notes.append(f)
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
                        print("warning: removing %s" % item, file=sys.stderr)
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
                print(repr(note), file=sys.stderr)
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

# Pass 1: Load
class PentlyInputParser(object):

    def __init__(self):
        self.sfxs = {}
        self.drums = {}
        self.instruments = {}
        self.patterns = {}
        self.songs = {}
        self.cur_obj = self.cur_song = None
        self.linenum = 0
        self.rhyctx = PentlyRhythmContext()
        self.pitchctx = PentlyPitchContext()
        self.unk_keywords = 0

    def append(self, s):
        """Parse one line of code."""
        self.linenum += 1
        s = s.strip()
        if not s or s.startswith(('#', '//')):
            return
        self.dokeyword(s.split())

    def extend(self, iterable):
        """Parse an iterable of lines."""
        for line in iterable:
            self.append(line)

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
            article = 'an' if allowed_objects[0].lower() in 'aeiou' else 'a'
            wrong_type = self.cur_obj_type()
            sep = ' ' if len(allowed_objects) < 2 else ', '
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
            raise ValueError("sfx %s was already defined on line %d"
                             % (name, self.sfxs[name].linenum))
        inst = PentlySfx(channel, pitchctx=self.pitchctx,
                         name=name, linenum=self.linenum)
        self.sfxs[name] = inst
        self.cur_obj = ('sfx', inst)

    def add_instrument(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: instrument INSTNAME")
        name = words[1]
        if self.cur_song is not None:
            name = '::'.join((self.cur_song.name, name))
        if name in self.instruments:
            raise ValueError("instrument %s was already defined on line %d"
                             % (name, self.instruments[name].linenum))
        inst = PentlyInstrument(name=name, linenum=self.linenum)
        self.instruments[name] = inst
        self.cur_obj = ('instrument', inst)

    def add_rate(self, words):
        self.ensure_in_object('rate', 'sfx')
        if len(words) != 2:
            raise ValueError("must have 2 words: rate FRAMESPERSTEP")
        rate = int(words[1])
        self.cur_obj[1].set_rate(rate, linenum=self.linenum)

    def add_volume(self, words):
        self.ensure_in_object('volume', ('sfx', 'instrument'))
        if len(words) < 2:
            raise ValueError("volume requires at least one step")
        obj = self.cur_obj[1]
        obj.set_volume([int(x) for x in words[1:] if x != '|'],
                       linenum=self.linenum)

    def add_decay(self, words):
        self.ensure_in_object('decay', 'instrument')
        if len(words) != 2:
            raise ValueError("must have 2 words: decay UNITSPER16FRAMES")
        obj = self.cur_obj[1]
        obj.set_decay(int(words[1]), linenum=self.linenum)

    def add_timbre(self, words):
        self.ensure_in_object('timbre', ('sfx', 'instrument'))
        if len(words) < 2:
            raise ValueError("timbre requires at least one step")
        obj = self.cur_obj[1]
        obj.set_timbre(words[1:], linenum=self.linenum)

    def add_pitch(self, words):
        self.ensure_in_object('pitch', ('sfx', 'instrument'))
        if len(words) < 2:
            raise ValueError("pitch requires at least one step")
        obj = self.cur_obj[1]
        obj.set_pitch(words[1:], linenum=self.linenum)

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
            raise ValueError("drum %s was already defined on line %d"
                             % (drumname, self.drums[drumname].linenum))
        d = PentlyDrum(words[2:], name=drumname, linenum=self.linenum)
        self.drums[drumname] = d

    # Songs and patterns

    def add_song(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: song SONGNAME")
        if self.cur_song:
            raise ValueError("song %s began on line %d and was not ended with fine or dal segno"
                             % (self.cur_song.name, self.cur_song.linenum))
        self.cur_obj = None
        songname = words[1]
        if songname in self.songs:
            oldlinenum = self.songs[songname].linenum
            raise ValueError("song %s was already defined on line %d"
                             % (songname, oldlinenum))
        song = PentlySong(pitchctx=self.pitchctx, rhyctx=self.rhyctx,
                          name=songname, linenum=self.linenum)
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
            if song.segno_linenum is not None:
                raise ValueError("cannot loop to start because segno was set on line %d"
                                 % song.segno_linenum)
            endcmd = 'dalSegno'
        else:
            raise ValueError('song end must be "fine" or "dal segno" or "da capo", not '
                             + end)
        song.conductor.append(endcmd)
        song.bytesize += 1
        self.cur_song = self.cur_obj = None

    def add_segno(self, words):
        if len(words) > 1:
            raise ValueError('segno takes no arguments')
        if not self.cur_song:
            raise ValueError("no song is open")
        song = self.cur_song
        if song.segno_linenum is not None:
            raise ValueError('loop point for song %s was already set at line %d'
                             % (self.cur_song.name, self.segno_linenum))
        song.conductor.append('segno')
        song.bytesize += 1
        song.segno_linenum = self.linenum
        self.cur_obj = None

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
            raise ValueError("must have 2 words: pickup MEASURE[:BEAT[:ROW]]")
        tempo = float(words[1])
        if not 1.0 <= tempo <= 1500.0:
            raise ValueError("tempo must be positive and no more than 1500 rows per minute")
        song = self.cur_song
        song.rhyctx.tempo = tempo  # to be picked up on next wait rows

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

    def add_song_pickup(self, words):
        if not self.cur_song:
            raise ValueError("at must be used in a song")
        if len(words) != 2:
            raise ValueError("must have 2 words: pickup MEASURE[:BEAT[:ROW]]")
        rhyctx = self.cur_song.rhyctx
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
            raise ValueError("pattern %s was already defined on line %d"
                             % (patname, self.patterns[patname].linenum))
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
                            name=patname, linenum=self.linenum)
        self.patterns[patname] = pat
        self.cur_obj = ('pattern', pat)

    def add_fallthrough(self, words):
        if len(words) > 1:
            raise ValueError("fallthrough takes no arguments")
        self.ensure_in_object('fallthrough', 'pattern')
        self.cur_obj[1].set_fallthrough(True)
        self.cur_obj = None

    def add_definition(self, name, value):
        if name.startswith('EN'):
            self.get_pitchrhy_parent().pitchctx.add_arp_name(name[2:], value)
            return

        raise ValueError("unknown definable %s" % repr(name))

    keywordhandlers = {
        'notenames': add_notenames,
        'durations': add_durations,
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
        'time': add_time,
        'scale': add_scale,
        'attack': add_attack,
        'pattern': add_pattern,
        'fallthrough': add_fallthrough,
        'at': add_song_wait,
        'pickup': add_song_pickup,
        'tempo': add_tempo,
        'play': add_play,
        'stop': add_stop,
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
        if self.unk_keywords < 100:
            print("unknown keyword %s inside %s"
                  % (repr(words), self.cur_obj or self.cur_song.name),
                  file=sys.stderr)
        self.unk_keywords += 1

# Pass 3: Try to find envelopes that overlap envelopes

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

def format_dbyt(n):
    return '$%04x' % n

def print_all_dicts(parser):
    print("\nParsed %d lines, with %d using a keyword not yet implemented"
          % (parser.linenum, parser.unk_keywords))
    dicts_to_print = [
        ('Sound effects', parser.sfxs),
        ('Instruments', parser.instruments),
        ('Drums', parser.drums),
        ('Songs', parser.songs),
        ('Patterns', parser.patterns),
    ]
    for name, d in dicts_to_print:
        print("%s (%d)" % (name, len(parser.sfxs)))
        print("\n".join("%s\n  %s" % (name, json.dumps(el))
                        for name, el in d.items()))

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

def render_file(parser, segment='RODATA'):
    # each entry in this row is a tuple of the form
    # list, name of directory table, include asmnames in export,
    # include in dbyt subsequence packing
    parts_to_print = [
        (parser.sfxs, 'pently_sfx_table', True,
         format_dbyt),
        (parser.instruments, 'pently_instruments', True,
         format_dbyt),
        (parser.drums, 'pently_drums', False,
         None),
        (parser.patterns, 'pently_patterns', False,
         None),
        (parser.songs, 'pently_songs', True,
         None),
    ]

    # Pack dbyt arrays that are subsequences of another dbyt array
    # into the longer one
    dbyt_pool_directory = []
    dbyt_pool_data = []
    for ptpidx, row in enumerate(parts_to_print):
        things, deflabel, _, is_dbyt = row
        for thingkey, thing in things.items():
            thing.render(scopes=parser)
            if thing.asmdata and is_dbyt:
                dbyt_pool_directory.append(thing.asmdataname)
                dbyt_pool_data.append(thing.asmdata)
    dbyt_packed = subseq_pack(dbyt_pool_data)
    dbyt_packed = {k: v for k, v in zip(dbyt_pool_directory, dbyt_packed) if v}

    lines = [
        '.include "../../src/pentlyseq.inc"',
        '.segment "%s"' % segment,
        'NUM_SONGS=%d' % len(parser.songs),
        'NUM_SOUNDS=%d' % len(parser.sfxs),
        '.exportzp NUM_SONGS, NUM_SOUNDS',
    ]
    all_export = []
    all_exportzp = []
    bytes_lines = []
    total_partbytes = 0
    for row in parts_to_print:
        things, deflabel, exportable, is_dbyt = row
        fmtfunc = format_dbyt if is_dbyt else None
        defs1 = sorted(things.values(), key=lambda x: x.linenum)
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
            packresult = dbyt_packed.get(thing.asmdataname)
            if packresult is not None:
                diridx, startoffset, endoffset = packresult
                assert endoffset - startoffset == len(thing.asmdata)
                line = ('%s = %s + 2 * %d'
                        % (thing.asmdataname, dbyt_pool_directory[diridx],
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
    lines.extend([
        '',
        '; Total music data size: %d bytes' % total_partbytes
    ])
    lines.extend(bytes_lines)
    return lines

# Period table generation ###########################################

baseNoteFreq = 55.0
region_period_numerator = {
    'ntsc': 39375000.0/(22 * 16),
    'pal': 266017125.0/(10 * 16 * 16),
    'dendy': 266017125.0/(10 * 16 * 15)
}

def getPeriodValues(maxNote=64, region='ntsc'):
    numerator = region_period_numerator[region.strip().lower()]
    octaveBase = numerator / baseNoteFreq
    semitone = 2.0**(1./12)
    relFreqs = [(1 << (i // 12)) * semitone**(i % 12)
                for i in range(maxNote)]
    periods = [int(round(octaveBase / freq)) - 1 for freq in relFreqs]
    return periods

def parse_argv(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("infilename", nargs='?',
                        help='Pently-MML file to process or - for standard input; omit for period table only')
    parser.add_argument("-o", metavar='OUTFILENAME',
                        help='write output to a file instead of standard output')
    parser.add_argument("--periods", type=int, default=0,
                        metavar='NUMSEMITONES',
                        help='include a period table in the output; NUMSEMITONES is usually 64 to 80')
    parser.add_argument("--period-region", default='ntsc',
                        choices=sorted(region_period_numerator.keys()),
                        help='make period table for this region (default: ntsc)')
    parser.add_argument("--segment", default='RODATA',
                        help='place output in this segment (default: RODATA)')
    args = parser.parse_args(argv[1:])
    if not args.infilename and not args.periods:
        parser.error('at least one of infilename and --periods is required')
    if args.periods < 0:
        parser.error('NUMSEMITONES cannot be negative')
    if args.periods > 88:
        parser.error('2A03 not precise enough for NUMSEMITONES > 88')
    return args

def main(argv=None):
    args = parse_argv(argv or sys.argv)

    lines = [
        '; Generated using Pently music assembler'
    ]
    if args.infilename:
        parser = PentlyInputParser()
        is_stdin = args.infilename == '-'
        infp = sys.stdin if is_stdin else open(args.infilename, 'r')
        try:
            parser.extend(infp)
        except Exception as e:
            import traceback
            traceback.print_exc()
            print("%s:%d: %s" % (args.infilename, parser.linenum, e),
                  file=sys.stderr)
            sys.exit(1)
        finally:
            if not is_stdin:
                infp.close()

        if parser.cur_song:
            print("%s:%d: warning: song %s was not ended"
                  % (args.infilename, parser.linenum, parser.cur_song.name),
                  file=sys.stderr)
        lines.append('; Music from ' + ('standard input' if is_stdin else args.infilename))
        lines.extend(render_file(parser, args.segment))

    if args.periods > 0:
        periods = getPeriodValues(args.periods, args.period_region)
        lines.extend([
            '; Period table of length %d for %s'
            % (args.periods, args.period_region),
            '.export periodTableLo, periodTableHi',
            'periodTableLo:'
        ])
        lines.extend(wrapdata(("$%02x" % (x & 0xFF) for x in periods), '.byt '))
        lines.append('periodTableHi:')
        lines.extend(wrapdata((str(x >> 8) for x in periods), '.byt '))

    is_stdout = not args.o
    outfp = sys.stdout if is_stdout else open(args.o, 'w')
    lines.append('')
    try:
        outfp.write('\n'.join(lines))
    finally:
        if not is_stdout:
            outfp.close()

if __name__=='__main__':
##    main(["pentlyas", "../src/musicseq.pently"])
    main()
