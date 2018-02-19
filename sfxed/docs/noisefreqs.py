#!/usr/bin/python
from __future__ import division
import math

notenames = ['C-','C#','D-','D#','E-','F-','F#','G-','G#','A-','A#','B-']

def note_freq_names(periods, numerator):

    freqs = [numerator/x for x in periods]
    notes = [69 + 12 * math.log(f / 440, 2) for f in freqs]
    rnotes = [int(round(note)) for note in notes]
    diffcents = [int(round(100 * (note - rnote))) 
                 for note, rnote in zip(notes, rnotes)]
    named = ["%6.1f Hz: %s%d%+03d"
             % (freq, notenames[midi % 12], midi // 12, diff)
             for freq, midi, diff in zip(freqs, rnotes, diffcents)]
    return named

noiseperiods = lens = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]
noisenum = 315000000/(176 * 93*1.03)
print("NES looped noise notes")
print("\n".join(note_freq_names(noiseperiods, noisenum)))

dmcperiods = [428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106,  84,  72,  54]
dmcnum = 315000000/(176 * 8)
dmcnumlong = dmcnum / 17
print("NES DMC (1 byte) notes")
print("\n".join(note_freq_names(dmcperiods, dmcnum)))
print("NES DMC (17 bytes) notes")
print("\n".join(note_freq_names(dmcperiods, dmcnumlong)))
