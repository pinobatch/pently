#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Find equivalent frequencies of MIDI notes

Copyright 2018 Damian Yerrick

[Insert zlib License here]
"""
from math import log
# from table at https://wiki.nesdev.com/w/index.php/APU_Noise
noiseperiods = [
    4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068
]
notenames = ['c', 'c#', 'd', 'd#', 'e', 'f', 'f#', 'g', 'g#', 'a', 'a#', 'b']

def lynotename(midinote):
    """Find the LilyPond/Pently name of a MIDI note number.

For example, given 60 (which means middle C), return "c'".
"""
    octave, notewithin = midinote // 12, midinote % 12
    notename = notenames[notewithin]
    if octave < 4:
        return notename + "," * (4 - octave)
    else:
        return notename + "'" * (octave - 4)

def main():
    xpositions = []
    lines = ["""{| class="wikitable"
|+ Pitches of 93-step noise on NTSC
! Period setting || Sample rate || Fundamental || MIDI note || Pitch"""]
    for i, period in enumerate(noiseperiods):
        updatefreq = 39375000/22/period
        fundamental = updatefreq/93

        # MIDI note 69 corresponds to 440 Hz, and an octave spans
        # 12 MIDI notes (1200 cents).
        cts = int(round(1200 * log(fundamental/440, 2) + 6900))
        notefloor, ctsdiff = cts // 100, cts % 100
        row = (
            "$8%X" % i,
            "%.1f Hz" % updatefreq,
            "%.1f Hz" % fundamental,
            "%.2f" % (cts / 100),
            "<nowiki>%s</nowiki> + %d¢" % (lynotename(notefloor), ctsdiff)
        )
        lines.append("|-\n| " + " || ".join(row))

        # The lowest note supported by Pently is the lowest pulse
        # note on 2A03, or 55 Hz. This corresponds to MIDI note 33.
        pentlycts = cts - 3300
        xpositions.append(16 + int(round(pentlycts * 3 / 100)))

    lines.append("|}")
    lines.extend([
        "<!-- Theoretical X positions of noise pitches: ",
        repr(xpositions), "-->"
    ])
    print("\n".join(lines))

if __name__=='__main__':
    main()
