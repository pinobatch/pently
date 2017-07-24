# Pently

A music engine for NES that supports both NES playback (with sound
effects) and NSF.

Documentation can be found in `docs/` and example tracks can be found in `musicseq.pently`.

## Building

### Prerequisites

- Python 3
- Pillow (Python imaging library) for demo ROM - `pip install pillow`
- [ca65](https://cc65.github.io/cc65/)
- GNU Make and Coreutils - on Windows, install MSYS through
  [mingw-get](http://www.mingw.org/wiki/Getting_Started)

For help setting these up, see the README file for
[nrom-template](https://github.com/pinobatch/nrom-template).

### Building

Once you have the above installed, run `make`.
Then edit the score and run `make` again to hear the changes.

## License

Copyright &copy; 2009-2017 Damian Yerrick.
Pently is free software, under the zlib License.
