# Pently

A music engine for NES that supports both NES playback (with sound
effects) and NSF.

Documentation can be found in `docs/` and example tracks can be found in `musicseq.pently`.

## Building

### Prerequisites

- [Python] 3
- [ca65]
- GNU Make and Coreutils  
  On Windows, install [Git for Windows], and then follow
  [evanwill's instructions] to download GNU Make without Guile
  from [ezwinports] and merge it into Git Bash.
- For NES (not NSF) format: Pillow (Python imaging library)  
  UNIX: `python3 -m pip install pillow`  
  Windows: `py -3 -m pip install pillow`
- For FamiTracker conversion: [Dn-FamiTracker] and [ft2pently]

For help setting up Python, ca65, Make, and Coreutils, see the README
file for [nrom-template].

[Python]: https://www.python.org/
[ca65]: https://cc65.github.io/
[Git for Windows]: https://git-scm.com/download/win
[evanwill's instructions]: https://gist.github.com/evanwill/0207876c3243bbb6863e65ec5dc3f058
[ezwinports]: https://sourceforge.net/projects/ezwinports/files/
[Dn-FamiTracker]: https://github.com/Dn-Programming-Core-Management/Dn-FamiTracker/releases
[ft2pently]: https://github.com/NovaSquirrel/ft2pently/releases
[nrom-template]: https://github.com/pinobatch/nrom-template

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

Copyright © 2009-2020 Damian Yerrick.
Pently is free software, under the zlib License.
