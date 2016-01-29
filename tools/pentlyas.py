#!/usr/bin/env python3
from __future__ import with_statement, division, print_function
# The above are imported by default in Python 3, but I need to import
# them anyway in case someone runs it on Python 2 for Windows, which
# is the default IDLE in a lot of Windows PCs
import sys, json, re

class PentlyPitchContext(object):
    """

Six octave modes are recognized at various places:

'drum' -- any word that starts and ends with a letter a pitch
'noise' -- 0 to 15 is a pitch; the result is subtracted from 15
    because NES hardware treats 15 as the longest period and thus
    the lowest pitch
'absolute': Always guess the octave below C
'orelative': Guess the octave of the previous note.
'relative': Guess the octave of the note with the given scale degree
    closest to the previous note, disregarding accidentals.
None: Wait for the first thing that looks like a pitch or drum.

"""

    def __init__(self, language='english'):
        self.set_language(language)
        self.reset_octave()

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

    def set_pitched_mode(self):
        """Set the octave mode to absolute if None."""
        if self.octave_mode is None: self.octave_mode = 'absolute'

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

    def parse_pitch(self, preoctave, notename, accidental, postoctave):
        if notename in ('r','w','l'):
            if not (preoctave or accidental or postoctave):
                return notename
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
        scaledegree = self.scaledegrees[notename]
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
            semi = self.notenamesemis[notename]

        self.last_octave = scaledegree, octave
        return semi + self.accidentalmeanings[accidental] + 12 * octave + 15

    pitchRE = re.compile(r"""
(>*|<*)       # MML style octave
([a-hrwl])    # note name
(b|bb|-|--|es|eses|s|ss|is|isis|\#|\#\#|\+|\+\+|x|)  # accidental
(,*|'*)$      # LilyPond style octave
""", re.VERBOSE)

    def parse_pitch_str(self, pitch):
        """Parse an absolute pitch: a note or a noise frequency."""
        if self.octave_mode == 'noise':
            pitch = int(pitch)
            if not 0 <= pitch <= 15:
                raise ValueError("noise pitches must be 0 to 15")
            return 15 - pitch

        m = self.pitchRE.match(pitch)
        if not m:
            raise ValueError("%s doesn't look like a pitch" % pitch)
        return self.parse_pitch(*m.groups())

    def reset_octave(self):
        self.last_octave = (3, 0)

# Pass 1: Load
class PentlyInputParser(object):

    def __init__(self):
        self.sfxs = {}
        self.drums = {}
        self.instruments = {}
        self.patterns = {}
        self.songs = {}
        self.scale = self.global_scale = 16
        self.timenum = self.global_timenum = 16
        self.timeden = self.global_timeden = 16
        self.cur_obj = self.cur_song = None
        self.linenum = 0
        self.pitchctx = PentlyPitchContext()
        self.last_duration = (4, 4)
        self.durations_stick = False
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

    def add_notenames(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: notenames LANGUAGE")
        self.pitchctx.set_language(words[1])

    def add_durations(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: durations BEHAVIOR")
        language = words[1].lower()
        if language == 'temporary':
            self.durations_stick = False 
        elif language == 'stick':
            self.durations_stick = True
        else:
            raise ValueError("unknown durations behavior %s; try temporary or stick"
                             % language)

    sfxchannels = {'pulse': 0, 'triangle': 2, 'noise': 3}

    def add_sfx(self, words):
        if len(words) != 4 or words[2] != 'on':
            raise ValueError("must have 4 words: sfx SFXNAME on CHANNELTYPE")
        _, sfxname, _, channel = words
        try:
            channel = self.sfxchannels[channel]
        except KeyError:
            raise ValueError("unknown channel; try pulse, triangle, or noise")
        if self.cur_song is not None:
            sfxname = '::'.join((self.cur_song, sfxname))
        if sfxname in self.sfxs:
            raise ValueError("sfx %s  was already defined on line %d"
                             % (sfxname, self.sfxs[sfxname]['linenum']))
        self.sfxs[sfxname] = {
            'timbre': None, 'volume': None, 'pitch': None, 'channel': channel,
            'rate': None, 'linenum': self.linenum
        }
        self.cur_obj = ('sfx', sfxname)
        self.pitchctx.reset_octave()
        self.pitchctx.octave_mode = 'noise' if channel == 3 else 'absolute'

    def add_instrument(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: instrument INSTNAME")
        instname = words[1]
        if self.cur_song is not None:
            instname = '::'.join((self.cur_song, instname))
        if instname in self.instruments:
            raise ValueError("instrument %s was already defined on line %d"
                             % (instname, self.instruments[instname]['linenum']))
        self.instruments[instname] = {
            'timbre': None, 'volume': None, 'pitch': None,
            'detached': False, 'decay': None, 'rate': None,
            'linenum': self.linenum
        }
        self.cur_obj = ('instrument', instname)
        self.pitchctx.octave_mode = 'absolute'
        self.pitchctx.reset_octave()

    def cur_obj_type(self):
        return (self.cur_obj[0] if self.cur_obj
                else 'song' if self.cur_song
                else 'top level')

    def add_rate(self, words):
        if not self.cur_obj or self.cur_obj[0] != 'sfx':
            raise ValueError("rate must be inside an sfx, not "
                             + self.cur_obj_type())
        if len(words) != 2:
            raise ValueError("must have 2 words: rate FRAMESPERSTEP")
        rate = int(words[1])
        if not 1 <= rate <= 16:
            raise ValueError("rate must be 1 to 16 frames per step, not %d"
                             % rate)
        rated_sfx = self.sfxs[self.cur_obj[1]]
        if rated_sfx['rate'] is not None:
            raise ValueError("rate for sfx %s was already set on line %d"
                             % (self.cur_obj[1],
                                rated_sfx['rate_linenum']))
        rated_sfx['rate'], rated_sfx['rate_linenum'] = rate, self.linenum

    def add_volume(self, words):
        if not self.cur_obj or self.cur_obj[0] not in ('sfx', 'instrument'):
            raise ValueError("volume must be inside an instrument or sfx, not "
                             + self.cur_obj_type())
        if len(words) < 2:
            raise ValueError("volume requires at least one step")
        volumedthing = (self.sfxs[self.cur_obj[1]]
                        if self.cur_obj[0] == 'sfx'
                        else self.instruments[self.cur_obj[1]])
        if volumedthing['volume'] is not None:
            raise ValueError("volume for %s %s was already set on line %d"
                             % (self.cur_obj[0], self.cur_obj[1],
                                volumedthing['volume_linenum']))
        volumes = [int(x) for x in words[1:]]
        if not all(0 <= x <= 15 for x in volumes):
            raise ValueError("volume steps must be 0 to 15")
        volumedthing['volume'] = volumes
        volumedthing['volume_linenum'] = self.linenum

    def add_decay(self, words):
        if not self.cur_obj or self.cur_obj[0] != 'instrument':
            raise ValueError("rate must be inside an instrument, not "
                             + self.cur_obj_type())
        if len(words) != 2:
            raise ValueError("must have 2 words: decay UNITSPER16FRAMES")
        rate = int(words[1])
        if not 0 <= rate <= 127:
            raise ValueError("decay must be 1 to 127 units per 16 frames, not %d"
                             % rate)
        rated_inst = self.instruments[self.cur_obj[1]]
        if rated_inst['decay'] is not None:
            raise ValueError("decay for instrument %s was already set on line %d"
                             % (self.cur_obj[1],
                                rated_inst['decay_linenum']))
        rated_inst['decay'], rated_inst['decay_linenum'] = rate, self.linenum

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

    def add_timbre(self, words):
        if not self.cur_obj or self.cur_obj[0] not in ('sfx', 'instrument'):
            raise ValueError("timbre must be inside an instrument or sfx, not "
                             + self.cur_obj_type())
        if len(words) < 2:
            raise ValueError("timbre requires at least one step")
        timbredthing = (self.sfxs[self.cur_obj[1]]
                        if self.cur_obj[0] == 'sfx'
                        else self.instruments[self.cur_obj[1]])
        if timbredthing['timbre'] is not None:
            raise ValueError("timbre for %s %s was already set on line %d"
                             % (self.cur_obj[0], self.cur_obj[1],
                                volumedthing['timbre_linenum']))
        timbres, looplen = self.pipesplit(words[1:])
        timbres = [int(x) for x in timbres]
        maxduty = 1 if timbredthing.get('channel') == 3 else 3
        if not all(0 <= x <= maxduty for x in timbres):
            raise ValueError("timbre steps must be 0 to %d" % maxduty)
        timbredthing['timbre'] = timbres
        timbredthing['timbre_looplen'] = looplen or 1
        timbredthing['timbre_linenum'] = self.linenum

    duraugmentnums = {
        '': 4, '.': 6, '..': 7, 'g': 0
    }
    def parse_duration(self, duration, duraugment):
        if duration:
            duration = int(duration)
            if not 1 <= duration <= 64:
                raise ValueError("%s: only whole to 64th notes are valid, not %d"
                                 % (pitch, duration))
            duraugment = self.duraugmentnums[duraugment]
            if duraugment and (duration & (duration - 1)):
                raise ValueError("%s: only powers of 2 are valid, not %d"
                                 % (pitch, duration))
            return duration, duraugment
        elif duraugment:
            raise ValueError("%s: augment dots are valid only with numeric duration"
                             % pitch)
        else:
            return None, None

    noteRE = re.compile(r"""
(>*|<*)       # MML style octave
([a-hrwl])    # note name
(b|bb|-|--|es|eses|s|ss|is|isis|\#|\#\#|\+|\+\+|x|)  # accidental
(,*|'*)       # LilyPond style octave
([0-9]*)      # duration
(|\.|\.\.|g)  # duration augment
(\~?)$        # slur?
""", re.VERBOSE)

    def parse_note(self, pitch):
        m = self.noteRE.match(pitch)
        if not m:
            return None, None, None, None
        (preoctave, notename, accidental, postoctave,
         duration, duraugment, slur) = m.groups()
        semi = self.pitchctx.parse_pitch(preoctave, notename, accidental, postoctave)
        duration, duraugment = self.parse_duration(duration, duraugment)
        slur = slur != ''
        return semi, duration, duraugment, slur

    drumnoteRE = re.compile(r"""
([a-zA-Z_].*[a-zA-Z_]|l|r)  # drum name, length, or rest
([0-9]*)       # duration
(|\.|\.\.|g)$  # duration augment
""", re.VERBOSE)

    def parse_drum_note(self, pitch):
        m = self.drumnoteRE.match(pitch)
        if not m:
            print("%s is not a note" % pitch)
            return None, None, None, None
        (notename, duration, duraugment) = m.groups()
        duration, duraugment = self.parse_duration(duration, duraugment)
        return notename, duration, duraugment, False

    def parse_pitchenv(self, pitch):
        """Parse an element of the pitch envelope in a sfx or instrument."""

        # Instrument: relative pitch (FT "Absolute" arpeggio)
        if self.cur_obj[0] == 'instrument':
            pitch = int(pitch)
            if not -60 <= pitch <= 60:
                raise ValueError("noise pitches must be within five octaves")
            return pitch

        # Otherwise it's a sound effect; use pitch numbers for
        # noise or absolute pitches for other channels
        return self.pitchctx.parse_pitch_str(pitch)

    def add_pitch(self, words):
        if not self.cur_obj or self.cur_obj[0] not in ('sfx', 'instrument'):
            raise ValueError("pitch must be inside an instrument or sfx, not "
                             + self.cur_obj_type())
        if len(words) < 2:
            raise ValueError("pitch requires at least one step")
        pitchedthing = (self.sfxs[self.cur_obj[1]]
                        if self.cur_obj[0] == 'sfx'
                        else self.instruments[self.cur_obj[1]])
        if pitchedthing['pitch'] is not None:
            raise ValueError("pitch for %s %s was already set on line %d"
                             % (self.cur_obj[0], self.cur_obj[1],
                                volumedthing['pitch_linenum']))
        pitches, looplen = self.pipesplit(words[1:])
        pitches = [self.parse_pitchenv(pitch) for pitch in pitches]
        pitchedthing['pitch'] = pitches
        pitchedthing['pitch_looplen'] = looplen or 1
        pitchedthing['pitch_linenum'] = self.linenum

    drumnameRE = re.compile('([a-zA-Z_].*[a-zA-Z_])$')
    def add_drum(self, words):
        if len(words) not in (3, 4):
            raise ValueError("must have 3 words: drum DRUMNAME")
        self.cur_obj = None
        sfxnames = words[2:]
        drumname = words[1]
        if not self.drumnameRE.match(drumname):
            raise ValueError("drum names must begin and end with letter or '_'")
        if self.cur_song is not None:
            drumname = '::'.join((self.cur_song, drumname))
        if drumname in self.drums:
            raise ValueError("drum %s was already defined" % drumname)
        self.drums[drumname] = sfxnames

    def add_detached(self, words):
        if not self.cur_obj or self.cur_obj[0] != 'instrument':
            raise ValueError("detached must be inside an instrument, not "
                             + self.cur_obj_type())
        if len(words) > 1:
            raise ValueError("detached in instrument takes no arguments")
        self.instruments[self.cur_obj[1]]['detached'] = True

    def add_song(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: song SONGNAME")
        if self.cur_song:
            raise ValueError("song %s began on line %d and was not ended with fine or dal segno"
                             % (songname, self.songs['linenum']))
        self.cur_obj = None
        songname = words[1]
        if songname in self.songs:
            raise ValueError("song %s was already defined on line %d"
                             % (songname, self.songs['linenum']))
        self.cur_song = songname
        self.cur_measure = 1
        self.row_in_measure = 0
        self.tempo = 100.0
        self.last_rowtempo = self.segno_linenum = self.last_beatlen = None
        self.songs[songname] = {
            'linenum': self.linenum,
            'conductor': []
        }

    def end_song(self, words):
        if not self.cur_song:
            raise ValueError("no song is open")
        words = ' '.join(words).lower()
        if words == 'fine':
            endcmd = 'fine'
        elif words in ('dal segno', 'dalsegno'):
            endcmd = 'dalSegno'
        elif words in ('da capo', 'dacapo'):
            if self.segno_linenum is not None:
                raise ValueError("cannot loop to start because segno was set on line %d"
                                 % self.segno_linenum)
            endcmd = 'dalSegno'
        else:
            raise ValueError('song end must be "fine" or "dal segno" or "da capo, not '
                             + end)
        self.songs[self.cur_song]['conductor'].append(endcmd)
        self.cur_song = self.cur_obj = None
        self.scale = self.global_scale
        self.timenum = self.global_timenum
        self.timeden = self.global_timeden

    def add_segno(self, words):
        if len(words) > 1:
            raise ValueError('segno takes no arguments')
        if not self.cur_song:
            raise ValueError("no song is open")
        if self.segno_linenum is not None:
            raise ValueError('loop point for song %s was already set at line %d'
                             % (self.cur_song, self.segno_linenum))
        self.segno_linenum = self.linenum
        self.cur_obj = None
        self.songs[self.cur_song]['conductor'].append('segno')

    def add_time(self, words):
        if len(words) not in (2, 4):
            raise ValueError('no time signature given')
        if len(words) > 2 and words[2] != 'scale':
            raise ValueError("time with scale must have 4 words: time N/D scale D")
        sp = words[1].split('/', 1)
        if len(sp) != 2:
            raise ValueError("time signature must be a fraction separated by /")
        timenum = int(sp[0])
        timeden = int(sp[1])
        if timenum < 2:
            raise ValueError("beats per measure must be at least 2")
        if not 2 <= timeden <= 64:
            raise ValueError("beat duration must be a half (2) to 64th (64) note")
        if timeden & (timeden - 1):
            raise ValueError("beat duration must be a power of 2")
        self.timenum, self.timeden = timenum, timeden
        if not self.cur_song:
            self.global_timenum = self.timenum
            self.global_timeden = self.timeden
        if len(words) > 2:
            self.dokeyword(words[2:])

    def add_scale(self, words):
        if len(words) != 2:
            raise ValueError("must have 2 words: scale ROWVALUE")
        rowvalue = int(words[1])
        if not 2 <= rowvalue <= 64:
            raise ValueError("row duration must be a half (2) to 64th (64) note")
        if rowvalue & (rowvalue - 1):
            raise ValueError("beat duration must be a power of 2")
        self.scale = rowvalue
        if not self.cur_song:
            self.global_scale = self.scale

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

    def add_tempo(self, words):
        if not self.cur_song:
            raise ValueError("tempo must be used in a song")
        if len(words) != 2:
            raise ValueError("must have 2 words: pickup MEASURE[:BEAT[:ROW]]")
        tempo = float(words[1])
        if not 1.0 <= tempo <= 1500.0:
            raise ValueError("tempo must be positive and no more than 1500 rows per minute")
        self.tempo = tempo  # to be picked up on next wait rows

    def parse_measure(self, mbr_word):
        measure_length = self.get_measure_length()
        beat_length = self.get_beat_length()
        mbr = [int(x) for x in mbr_word.split(':', 2)]
        measure = mbr[0]
        beat = mbr[1] - 1 if len(mbr) > 1 else 0
        if beat < 0:
            raise ValueError("time %s has a beat less than 1" % mbr_word)
        row = mbr[2] if len(mbr) > 2 else 0
        if row < 0:
            raise ValueError("time %s has a row less than 0" % mbr_word)
        row += beat_length * beat
        if row >= measure_length:
            raise ValueError("time %s has beat %d but measure has only %d beats (%d rows)"
                             % (mbr_word, row // beat_length + 1,
                                measure_length // beat_length, measure_length))
        return measure, row, measure_length, beat_length

    durcodes = {
        1: '0', 2: 'D_8', 3: 'D_D8', 4: 'D_4',
        6: 'D_D4', 8: 'D_2', 12: 'D_D2', 16: 'D_1'
    }

    def add_song_wait(self, words):
        if not self.cur_song:
            raise ValueError("at must be used in a song")
        if len(words) < 2:
            raise ValueError("must have 2 words: at MEASURE[:BEAT[:ROW]]")

        measure, row, measure_length, beat_length = self.parse_measure(words[1])
        if (measure < self.cur_measure
            or (measure == self.cur_measure and row < self.row_in_measure)):
            old_beat = self.row_in_measure // beat_length + 1
            old_row = self.row_in_measure % beat_length
            raise ValueError("wait for %d:%d:%d when song is already to %d:%d:%d"
                             % (measure, row // beat_length + 1, row % beat_length,
                                self.cur_measure, old_beat, old_row))

        # If we're waiting at least one row, update the tempo and
        # put in a wait command
        rows_to_wait = ((measure - self.cur_measure) * measure_length
                        + (row - self.row_in_measure))
        if rows_to_wait > 0:
            song = self.songs[self.cur_song]['conductor']

            # Update tempo if needed
            rowtempo = int(round(self.tempo * beat_length))
            if rowtempo > 1500:
                raise ValueError("last tempo change exceeds 1500 rows per minute")
            if rowtempo != self.last_rowtempo:
                song.append('setTempo %d' % rowtempo)
                self.last_rowtempo = rowtempo

            if self.last_beatlen != beat_length:
                try:
                    durcode = self.durcodes[beat_length]
                except KeyError:
                    raise ValueError("no duration code for %d beats per row"
                                     % beat_length)
                song.append('setBeatDuration %s' % durcode)
                self.last_beatlen = beat_length
            
            while rows_to_wait > 256:
                song.append('waitRows 256')
                rows_to_wait -= 256
            song.append('waitRows %d' % rows_to_wait)
        
        self.cur_measure, self.row_in_measure = measure, row
        self.cur_obj = None  # end any song-local pattern or instrument
        if len(words) > 2:
            self.dokeyword(words[2:])

    def add_song_pickup(self, words):
        if not self.cur_song:
            raise ValueError("at must be used in a song")
        if len(words) != 2:
            raise ValueError("must have 2 words: pickup MEASURE[:BEAT[:ROW]]")
        measure, row, measure_length, beat_length = self.parse_measure(words[1])
        self.cur_measure, self.row_in_measure = measure, row

    @staticmethod
    def extract_prepositions(words):
        return dict(zip(words[2::2], words[3::2]))

    pitched_tracks = {'pulse1': 0, 'pulse2': 1, 'triangle': 2, 'attack': 4}
    track_suffixes = ['Sq1', 'Sq2', 'Tri', 'Noise', 'Attack']

    def add_attack(self, words):
        if len(words) != 3 or words[1] != 'on':
            raise ValueError('syntax: attack on CHANNELNAME')
        if self.cur_song is None:
            raise ValueError('play must be used in a song')
        chname = words[2]
        chnum = self.pitched_tracks[chname]
        if chnum >= 3:
            raise ValueError("%s is not a pitched channel" % chname)
        cmd = "attackOn%s" % self.track_suffixes[chnum]
        self.songs[self.cur_song]['conductor'].append(cmd)

    def add_play(self, words):
        if len(words) % 2 != 0:
            raise ValueError('syntax: pattern PATTERNNAME [on TRACK] [with INSTRUMENT]')
        if self.cur_song is None:
            raise ValueError('play must be used in a song')
        patname = words[1]
        pps = self.extract_prepositions(words)
        track = pps.pop('on', None)
        instrument = pps.pop('with', None)
        transpose = int(pps.pop('up', 0)) - int(pps.pop('down', 0))
        if pps:
            raise ValueError("unknown prepositions: " + " ".join(pps))

        if (track is not None and instrument is not None
            and transpose == 0):
            # Attempt a note-on rather than a pattern start
            if track == 'noise':
                ch = 3
                self.pitchctx.octave_mode = "noise"
            else:
                ch = self.pitched_tracks[track]
                self.pitchctx.octave_mode = 'absolute'
                self.pitchctx.reset_octave()
                if ch >= 3:
                    raise ValueError("cannot play conductor note on a track without its own channel")
            try:
                transpose = self.pitchctx.parse_pitch_str(patname)
            except ValueError as e:
                pass
            else:
                abstract_cmd = ('noteOn', ch, transpose, instrument)
                self.songs[self.cur_song]['conductor'].append(abstract_cmd)
                return

        if track is not None:
            try:
                track = self.pitched_tracks[track]
            except KeyError:
                raise ValueError('unknown track ' + track)
        abstract_cmd = ('playPat', track, patname, transpose, instrument)
        self.songs[self.cur_song]['conductor'].append(abstract_cmd)

    def add_stop(self, words):
        if self.cur_song is None:
            raise ValueError('stop must be used in a song')
        if len(words) < 2:
            raise ValueError('must stop at least one track')
        tracks_to_stop = set()
        tracks_unknown = []
        for trackname in words[1:]:
            if trackname == 'drum':
                tracks_to_stop.add(3)
                continue
            try:
                track = self.pitched_tracks[trackname]
            except KeyError:
                tracks_unknown.append(trackname)
                continue
            else:
                tracks_to_stop.add(track)
        if tracks_unknown:
            raise ValueError("unknown track names: "+" ".join(tracks_unknown))
        abstract_cmds = (('stopPat', track) for track in tracks_to_stop)
        self.songs[self.cur_song]['conductor'].extend(abstract_cmds)

    def add_pattern(self, words):
        if len(words) % 2 != 0:
            raise ValueError('syntax: pattern PATTERNNAME [on TRACK] [with INSTRUMENT]')
        patname = words[1]
        if patname in self.patterns:
            raise ValueError("pattern %s was already defined on line %d"
                             % (patname, self.patterns[patname]['linenum']))
        if self.cur_song is not None:
            patname = '::'.join((self.cur_song, patname))

        pps = self.extract_prepositions(words)
        track = pps.pop('on', None)
        if track and track not in self.pitched_tracks:
            raise ValueError('unknown track ' + track)
        instrument = pps.pop('with', None)
        if pps:
            raise ValueError("unknown prepositions: " + " ".join(pps))

        # Prepare for autodetection of octave mode.  If a pitched
        # track or pitched instrument is specified, default to
        # absolute.  Or if a note is seen before it is set, switch
        # to absolute with that note.  But if a drum is seen first,
        # set to drum mode.
        self.pitchctx.reset_octave()
        self.pitchctx.octave_mode = 'absolute' if track or instrument else None
        self.cur_obj = ('pattern', patname)
        self.patterns[patname] = {
            'linenum': self.linenum,
            'instrument': instrument, 'track': track, 'notes': [],
            'fallthrough': False
        }
        self.last_duration = None

    def add_fallthrough(self, words):
        if len(words) > 1:
            raise ValueError("fallthrough takes no arguments")
        if self.cur_obj is None or self.cur_obj[0] != 'pattern':
            raise ValueError("fallthrough must be used in a pattern")
        self.patterns[self.cur_obj[1]]['fallthrough'] = True
        self.cur_obj = None

    dotted_names = {4: '', 6: 'dotted ', 7: 'double dotted '}

    def fix_note_duration(self, notematch):
        """Convert duration to number of rows. 

notematch -- (pitch, duration denominator, duration augment, slur)

Return (pitch, number of rows, slur) or None if it's not actually a note.

"""

        pitch, denom, augment, slur = notematch[:4]
        if pitch == 'l':
            if denom is None:
                raise ValueError("length requires a duration argument")
            self.last_duration = denom, augment
            return None
        if augment == 0:  # 0: grace note
            return pitch, -denom, slur

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
        return pitch, wholerows, slur

    arpeggioRE = re.compile("@EN([0-9a-fA-F]{1,2})$")

    def add_pattern_note(self, word):
        if word in ('absolute', 'orelative', 'relative'):
            if self.pitchctx.octave_mode == 'drum':
                raise ValueError("drum pattern's octave mode cannot be changed")
            self.pitchctx.octave_mode = word
            return

        pattern = self.patterns[self.cur_obj[1]]

        arpmatch = self.arpeggioRE.match(word)
        if arpmatch:
            if self.pitchctx.octave_mode == 'drum':
                raise ValueError("can't arpeggio a drum")
            self.pitchctx.set_pitched_mode()
            pattern['notes'].append("ARPEGGIO,$"+arpmatch.group(1))
            return

        # Other @ marks are instrument changes.  Resolve them later
        # once asmname values have been assigned.
        if word.startswith('@'):
            pattern['notes'].append(word)
            return

        if self.pitchctx.octave_mode is None:
            drummatch = self.parse_drum_note(word)
            notematch = self.parse_note(word)
            if drummatch[0] is not None and notematch[0] is not None:
                # Only note length and rest commands keep the pattern
                # in an indeterminate state between pitched and drum
                if notematch[0] not in ('l', 'r'):
                    raise ValueError("%s is ambiguous: it could be a drum or a pitch"
                                     % word)
                f = self.fix_note_duration(drummatch)
                if f: pattern['notes'].append(f)
                return
            elif drummatch[0] is not None:
                pattern['track'] = self.pitchctx.octave_mode = 'drum'
                f = self.fix_note_duration(drummatch)
                if f: pattern['notes'].append(f)
                return
            elif notematch[0] is not None:
                self.pitchctx.set_pitched_mode()
                f = self.fix_note_duration(notematch)
                if f: pattern['notes'].append(f)
                return
            else:
                print("unknown first note", word)
                self.unk_keywords += 1

        if self.pitchctx.octave_mode == 'drum':
            drummatch = self.parse_drum_note(word)
            if drummatch[0] is not None:
                f = self.fix_note_duration(drummatch)
                if f: pattern['notes'].append(f)
            else:
                print("unknown drum pattern note", word)
                self.unk_keywords += 1
            return

        notematch = self.parse_note(word)
        if notematch[0] is not None:
            f = self.fix_note_duration(notematch)
            if f: pattern['notes'].append(f)
        else:
            print("unknown pitched pattern note", word,
                  file=sys.stderr)
            self.unk_keywords += 1

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
        try:
            kwh = self.keywordhandlers[words[0]]
        except KeyError:
            pass
        else:
            return kwh(self, words)
        if self.cur_obj and self.cur_obj[0] == 'pattern':
            for word in words:
                self.add_pattern_note(word)
            return
        if self.unk_keywords < 100:
            print("unknown keyword %s inside %s"
                  % (repr(words), self.cur_obj or self.cur_song),
                  file=sys.stderr)
        self.unk_keywords += 1

    @staticmethod
    def expand_envelope_loop(envelope, looplen, length):
        index = 0
        for i in range(length):
            yield envelope[index]
            index += 1
            if index >= len(envelope):
                index -= looplen

    nonalnumRE = re.compile("[^a-zA-Z0-9]")

    def get_asmname(self, name):
        return '_'.join(c for c in self.nonalnumRE.split(name) if c)

    def render_instrument(self, inst_name):
        """Create asmname, def, and data for an instrument."""
        inst = self.instruments[inst_name]
        volume = inst.get('volume') or [8]
        timbre = inst.get('timbre') or [2]
        pitch = inst.get('pitch') or [0]
        decay = inst.get('decay') or 0
        timbre_looplen = inst.get('timbre_looplen') or 1
        pitch_looplen = inst.get('pitch_looplen') or 1
        detached = 1 if inst.get('detached') else 0

        attacklen = len(volume)
        timbre = list(self.expand_envelope_loop(timbre, timbre_looplen, attacklen))
        pitch = list(self.expand_envelope_loop(pitch, pitch_looplen, attacklen - 1))
        attackdata = [((t << 14) | (v << 8) | (p & 0xFF))
                      for t, v, p in zip(timbre, volume, pitch)]
        sustaintimbre = timbre[-1]
        sustainvolume = volume[-1]

        asmname = self.get_asmname(inst_name)
        inst['asmname'] = 'PI_'+asmname
        inst['dataname'] = 'PIDAT_'+asmname
        inst['data'] = attackdata
        inst['def'] = ("instdef PI_%s, %d, %d, %d, %d, %s, %d"
                       % (asmname, sustaintimbre, sustainvolume, decay,
                          detached, 'PIDAT_'+asmname if attackdata else '0',
                          len(attackdata)))

    def render_sfx(self, inst_name):
        """Create asmname, def, and data for an instrument."""
        inst = self.sfxs[inst_name]
        volume = inst.get('volume') or [8]
        pitch = inst.get('pitch') or [0]
        timbre_looplen = inst.get('timbre_looplen') or 1
        pitch_looplen = inst.get('pitch_looplen') or 1
        channel = inst.get('channel') or 0
        rate = inst.get('rate') or 1
        timbre = inst.get('timbre') or [2 if channel != 3 else 0]

        # Trim trailing silence
        while volume and volume[-1] == 0:
            del volume[-1]
        attacklen = len(volume)
        pitch = list(self.expand_envelope_loop(pitch, pitch_looplen, attacklen))
        if channel != 2:
            timbre = self.expand_envelope_loop(timbre, timbre_looplen, attacklen)
            if channel == 3:
                # On noise, nonzero timbre means use looped noise
                timbre = [0x80 if t else 0 for t in timbre]
            else:
                # Otherwise, timbre means duty (1/8, 1/4, 1/2, 3/4)
                timbre = [t << 14 for t in timbre]
        else:
            # Triangle sfx always uses timbre 2
            timbre = [0x8000] * attacklen
        attackdata = [(t | (v << 8) | (p & 0xFF))
                      for t, v, p in zip(timbre, volume, pitch)]

        asmname = self.get_asmname(inst_name)
        inst['asmname'] = 'PE_'+asmname
        inst['dataname'] = 'PEDAT_'+asmname
        inst['data'] = attackdata
        inst['def'] = ("sfxdef PE_%s, PEDAT_%s, %d, %d, %d"
                       % (asmname, asmname, len(attackdata), rate, channel))

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
        """Combine w notes and notes matching previous slurred pitch into previous.

notes -- iterable of (pitch, numrows, slur) sequences
tie_rests -- True if track has no concept of a "note off"

"""
        out = []
        lastwasnote = hasnote = False
        for note in notes:
            if isinstance(note, str):
                lastwasnote = False
                out.append(note)
                continue

            pitch, numrows, slur = note
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

    pattern_pitchoffsets = [
        'N_C', 'N_CS', 'N_D', 'N_DS', 'N_E', 'N_F',
        'N_FS', 'N_G', 'N_GS', 'N_A', 'N_AS', 'N_B',
        'N_CH', 'N_CSH', 'N_DH', 'N_DSH', 'N_EH', 'N_FH',
        'N_FSH', 'N_GH', 'N_GSH', 'N_AH', 'N_ASH', 'N_BH',
        'N_CHH'
    ]

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

    def render_pattern(self, name):
        pattern = self.patterns[name]
        is_drum = pattern['track'] == 'drum'
        pattern['notes'] = notes = self.collapse_ties(pattern['notes'], is_drum)

        bytedata = []

        if not is_drum:
            transpose_runs = self.find_transpose_runs(pattern['notes'])
            pattern['transpose'] = cur_transpose = transpose_runs[0][1]
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
                    instname = self.resolve_scope(note[1:], name, self.instruments)
                    note = 'INSTRUMENT,' + self.instruments[instname]['asmname']
                bytedata.append(note)
                continue
            if len(note) != 3:
                print(repr(note), file=sys.stderr)
            pitch, numrows, slur = note
            if isinstance(pitch, int):
                offset = pitch - cur_transpose
                assert 0 <= offset <= 24
                pitchcode = self.pattern_pitchoffsets[offset]
            elif pitch == 'r':
                pitchcode = 'REST'
            elif pitch == 'w':  # usually a tie after an @-command
                pitchcode = 'N_TIE'
            elif is_drum:
                drumname = self.resolve_scope(pitch, name, self.drums)
                pitchcode = 'D_' + self.get_asmname(drumname)
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
        if not pattern['fallthrough']: bytedata.append('PATEND')

        asmname = self.get_asmname(name)
        pattern['data'] = bytedata
        pattern['def'] = 'patdef PP_%s, PPDAT_%s' % (asmname, asmname)
        pattern['asmname'] = 'PP_'+asmname
        pattern['dataname'] = 'PPDAT_'+asmname

    def render_song(self, name):
        song = self.songs[name]
        out = []
        for row in song['conductor']:
            if isinstance(row, str):
                out.append(row)
                continue
            if row[0] == 'playPat':
                track, patname, transpose, instrument = row[1:5]
                patname = self.resolve_scope(patname, name, self.patterns)
                pat = self.patterns[patname]
                if track is None: track = pat['track']
                if track == 'drum':
                    if pat['track'] != 'drum':
                        raise ValueError('cannot play pitched pattern %s on drum track'
                                         % (patname,))
                    out.append("playPatNoise %s" % pat['asmname'])
                    continue
                if pat['track'] == 'drum':
                    raise ValueError('cannot play drum pattern %s on pitched track'
                                     % (patname,))
                if isinstance(track, str):
                    track = self.pitched_tracks[track]
                if track is None:
                    raise ValueError("%s: no track for pitched pattern %s"
                                     % (name, patname))
                transpose += pat['transpose']
                if instrument is None: instrument = pat['instrument']
                if instrument is None:
                    raise ValueError("%s: no instrument for pattern %s"
                                     % (song, patname))
                instrument = self.resolve_scope(instrument, name, self.instruments)
                instrument = self.instruments[instrument]['asmname']
                suffix = self.track_suffixes[track]
                out.append("playPat%s %s, %d, %s"
                           % (suffix, pat['asmname'], transpose, instrument))
                continue
            if row[0] == 'stopPat':
                out.append('stopPat%s' % self.track_suffixes[row[1]])
                continue
            if row[0] == 'noteOn':
                ch, pitch, instrument = row[1:4]
                instrument = self.resolve_scope(instrument, name, self.instruments)
                instrument = self.instruments[instrument]['asmname']
                out.append('noteOn%s %d, %s'
                           % (self.track_suffixes[ch], pitch, instrument))
                continue
            raise ValueError(row)

        asmname = self.get_asmname(name)
        song['data'] = out
        song['def'] = 'songdef PS_%s, PSDAT_%s' % (asmname, asmname)
        song['asmname'] = 'PS_'+asmname
        song['dataname'] = 'PSDAT_'+asmname


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

def render_file(parser):
    for row in parser.instruments:
        parser.render_instrument(row)
    for row in parser.sfxs:
        parser.render_sfx(row)
    for row in parser.patterns:
        parser.render_pattern(row)
    for row in parser.songs:
        parser.render_song(row)

    lines = [
        '.include "../../src/pentlyseq.inc"'
    ]
    all_exports = []

    parts_to_print = [
        (parser.sfxs, 'pently_sfx_table', True,
         '.dbyt ', format_dbyt),
        (parser.instruments, 'pently_instruments', True,
         '.dbyt ', format_dbyt),
        (parser.patterns, 'pently_patterns', False,
         '.byte ', None),
        (parser.songs, 'pently_songs', True,
         None, None),
    ]

    for row in parts_to_print:
        things, deflabel, exportable, prefix, fmtfunc = row
        defs1 = sorted(things.values(), key=lambda x: x['linenum'])
        if exportable:
            all_exports.extend(row['asmname'] for row in defs1)
        all_exports.append(deflabel)
        lines.append(deflabel+':')
        lines.extend(row['def'] for row in defs1)
        for row in defs1:
            if row['data']:
                lines.append(row['dataname']+':')
                data = (fmtfunc(s) for s in row['data']) if fmtfunc else row['data']
                lines.extend(wrapdata(data, prefix) if prefix else data)

    defs1 = sorted(parser.drums.items(), key=lambda x: x[0])
    lines.append('pently_drums:')
    all_exports.append('pently_drums')
    for drumname, sfxnames in defs1:
        drumname = 'D_'+parser.get_asmname(drumname)
        sfxnames = ', '.join('PE_'+parser.get_asmname(sfxname)
                            for sfxname in sfxnames)
        lines.append("drumdef %s, %s" % (drumname, sfxnames))

    lines.extend(wrapdata(all_exports, ".export "))
    lines.append('NUM_SONGS=%d' % len(parser.songs))
    lines.append('.globalzp NUM_SONGS')
    return lines

def main(argv=None):
    argv = argv or sys.argv
    parser = PentlyInputParser()
    infilename = argv[1]
    with open(infilename, 'r') as infp:
        try:
            parser.extend(infp)
        except Exception as e:
            import traceback
            traceback.print_exc()
            print("%s:%d: %s" % (infilename, parser.linenum, e),
                  file=sys.stderr)
            sys.exit(1)
    if parser.cur_song:
        print("%s:%d: song %s was not ended"
              % (infilename, parser.linenum, parser.cur_song),
              file=sys.stderr)
        return

    lines = render_file(parser)
    print("; Generated using Pently compiler from %s" % infilename)
    print("\n".join(lines))

if __name__=='__main__':
##    main(["pentlyas", "../docs/samplefile.txt"])
    main()

# TO DO
# 1. Render song
# 2. Format ['data'] as .byte or .dbyt
# 3. 
# 4. Write out a file
# 5. Actually play twinkle
# 6. Make a class for each data type rather than just using dicts
# 7. Give each class a 'render' method
# 8. Support grace notes
# 9. Support arpeggio changes
# 10. Support mid-pattern instrument changes
# 11. Try to find envelopes that overlap envelopes
