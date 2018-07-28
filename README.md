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

For help setting these up, see the README file for
[nrom-template](https://github.com/pinobatch/nrom-template).

### Building

Once you have the above installed, run `make` to build and play
or `make pently.nes` to only build a ROM.
Then edit the score and run `make` again to hear the changes.
To use an entirely different score file, open `makefile` and change
`scorename`, or use e.g. `make NTS.nsf` or `make NTS.nes` to use
score file `src/NTS.pently`.

## License

Copyright © 2009-2018 Damian Yerrick.
Pently is free software, under the zlib License.
