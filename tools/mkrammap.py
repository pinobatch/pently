#!/usr/bin/env python3
"""
Pently RAM map generator

Copyright 2017 Damian Yerrick

[Insert zlib License here]
"""
import sys
import re
import argparse

default_heighttypes = {
    'SINGLETON': 1,
    'PER_TRACK': 5,
    'PER_CHANNEL': 4,
    'PER_PITCHED_CHANNEL': 4
}
num_cols = 4  # spacing between channels' length counters

# Pitched channels may be reduced to 3 rows in a later commit after
# I can confirm that noise isn't accessing any of them

specs = """
# Pitch
chPitchHi        PER_CHANNEL

# Pitch effects
arpPhase         PER_CHANNEL         ARPEGGIO|ATTACK_TRACK
arpIntervalA     PER_PITCHED_CHANNEL ARPEGGIO
arpIntervalB     PER_PITCHED_CHANNEL ARPEGGIO
vibratoDepth     PER_PITCHED_CHANNEL VIBRATO
vibratoPhase     PER_PITCHED_CHANNEL VIBRATO
notePitch        PER_PITCHED_CHANNEL PORTAMENTO
chPitchLo        PER_PITCHED_CHANNEL PORTAMENTO
chPortamento     PER_PITCHED_CHANNEL PORTAMENTO

# Envelope
attack_remainlen PER_CHANNEL         ATTACK_PHASE
attackPitch      PER_CHANNEL         ATTACK_TRACK
noteEnvVol       PER_CHANNEL
noteLegato       PER_CHANNEL
channelVolume    PER_CHANNEL         CHANNEL_VOLUME

# Pattern reading
noteRowsLeft     PER_TRACK
graceTime        PER_TRACK
noteInstrument   PER_TRACK
musicPattern     PER_TRACK
patternTranspose PER_TRACK
music_tempoLo    SINGLETON
music_tempoHi    SINGLETON
conductorWaitRows SINGLETON
pently_rows_per_beat SINGLETON       BPMMATH
pently_row_beat_part SINGLETON       BPMMATH
pently_mute_track  PER_TRACK         VARMIX

# Visualization and rehearsal
pently_vis_dutyvol PER_CHANNEL       VIS
pently_vis_pitchlo PER_CHANNEL       VIS
pently_vis_pitchhi PER_CHANNEL       VIS
pently_rowslo      PER_CHANNEL       REHEARSAL
pently_rowshi      PER_CHANNEL       REHEARSAL

"""
specs = [row.strip() for row in specs.split("\n")]
specs = [row.split() for row in specs if row and not row.startswith('#')]

def load_uses(config_path):
    """Read the set of features that Pently is configured to use."""
    useRE = re.compile(r"PENTLY_USE_([a-zA-Z0-9_]+)\s*=\s*([0-9])+\s*(?:;.*)?")
    with open(config_path, "r") as infp:
        uses = [useRE.match(line.strip()) for line in infp]
    uses = [m.groups() for m in uses if m]
    return {name for name, value in uses if int(value)}

def get_heighttypes(uses):
    hts = dict(default_heighttypes)
    if 'ATTACK_TRACK' not in uses:
        hts['PER_TRACK'] = hts['PER_CHANNEL']
    return hts

def get_needed_vars(uses):
    heighttypes = get_heighttypes(uses)
    needed_vars, unneeded_vars = [], []
    for row in specs:
        varname, heighttype = row[:2]
        height = heighttypes[heighttype]
        conditions = row[2].split("|") if len(row) > 2 else None
        met = conditions is None or bool(uses.intersection(conditions))
        if met:
            needed_vars.append((varname, height))
        else:
            unneeded_vars.append((varname, row[1], height, conditions))
    return needed_vars, unneeded_vars

def format_unneeded(unneeded_vars):
    return [
        "; %s (%s, %d %s): %s disabled"
        % (varname, heighttype, height, "rows" if height != 1 else "row",
           ", ".join(conditions))
        for varname, heighttype, height, conditions in unneeded_vars
    ]

def ffd(needed, num_cols):
    def byel1(x):
        return x[1]

    needed = sorted(needed, key=byel1, reverse=True)
    cols = [[[], 0] for x in range(num_cols)]
    for name, height in needed:
        lowest = min(cols, key=byel1)
        lowest[0].append((name, lowest[1]))
        lowest[1] += height
    cols.sort(key=byel1, reverse=True)
    return cols

def format_cols(cols, base_label):
    return [
        "%s = %s + %d" % (name, base_label, ht * len(cols) + i)
        for i, (names, totalht) in enumerate(cols)
        for name, ht in names
    ]

def parse_argv(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("configpath")
    parser.add_argument("base_label")
    parser.add_argument("-o", "--output", default='-',
                        help="write output to file")
    return parser.parse_args(argv[1:])

def main(argv=None):
    args = parse_argv(argv or sys.argv)

    uses = load_uses(args.configpath)
    needed_vars, unneeded_vars = get_needed_vars(uses)
    out = []
    if unneeded_vars:
        out.append("; Variables not needed per configuration")
        out.extend(format_unneeded(unneeded_vars))
    unneeded_vars = None

    cols = ffd(needed_vars, num_cols)
    minht = min(col[1] for col in cols)
    maxht = max(col[1] for col in cols)
    sumht = sum(col[1] for col in cols)
    belowmax = sum(1 for k, ht in cols if ht < maxht)
    bytesneeded = maxht * num_cols - belowmax

    waste = bytesneeded - sumht
    out.append("; Columns are %d-%d rows tall, total %d"
               % (minht, maxht, sumht))
    out.append("; Below max: %d; layout waste %d" % (belowmax, waste))
    out.append("%s_size = %d" % (args.base_label, bytesneeded))
    out.extend(format_cols(cols, args.base_label))
    outfp = open(args.output, "w") if args.output != '-' else sys.stdout
    with outfp:
        print("\n".join(out), file=outfp)
        

if __name__=='__main__':
    main()
