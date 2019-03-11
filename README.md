# Pently

A music engine for NES that supports both NES playback (with sound
effects) and NSF.

Documentation can be found in `docs/` and example tracks can be found in `musicseq.pently`.

## Building

### Prerequisites

- Python 3
- [ca65](https://cc65.github.io/cc65/)
- GNU Make and Coreutils - on Windows, install MSYS through
  [mingw-get](http://www.mingw.org/wiki/Getting_Started)
- For NES (not NSF) format: Pillow (Python imaging library)  
  UNIX: `python3 -m pip install pillow`  
  Windows: `py -3 -m pip install pillow`
- For FamiTracker conversion:
  [j0CC-FamiTracker](https://github.com/jimbo1qaz/j0CC-FamiTracker)
  and [ft2pently](https://github.com/NovaSquirrel/ft2pently)

For help setting up Python, ca65, Make, and Coreutils, see the README
file for [nrom-template](https://github.com/pinobatch/nrom-template).

### Building

Once you have the above installed, run `make` to build and play
or `make pently.nes` to only build a ROM.
Then edit the score and run `make` again to hear the changes.
To use an entirely different score file, open `makefile` and change
`scorename`, or use e.g. `make NTS.nsfe` or `make NTS.nes` to use
score file `audio/NTS.pently`.
To use a FamiTracker module, edit the `FAMITRACKER` and `FT2P` paths
in `makefile` to reflect executable paths on your system, then run
`make Foothills.nsf` to use score file `audio/Foothills.ftm`.

## License

Copyright © 2009-2018 Damian Yerrick.
Pently is free software, under the zlib License.
