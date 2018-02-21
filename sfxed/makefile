#!/usr/bin/make -f
#
# Makefile for NES game
# Copyright 2011 Damian Yerrick
#
# Copying and distribution of this file, with or without
# modification, are permitted in any medium without royalty
# provided the copyright notice and this notice are preserved.
# This file is offered as-is, without any warranty.
#

# These are used in the title of the NES program and the zip file.
title = sfxed

CURDAY := $(shell echo $$(( ($$(date -d 'now' '+%s') / 86400) - 16305 )))
version = day$(CURDAY)

# Assembly language files that make up the PRG ROM
align_sensitive_modules := vwf7 paldetect
game_modules := \
  main editactions mouseactions bg export
lib_modules := vwf_draw ppuclear pads mouse random bcd
audio_modules := pentlysound ntscPeriods
objlist := $(align_sensitive_modules) $(game_modules) \
  $(lib_modules) $(audio_modules)
pentlyfiles := \
  tools/pentlyas.py tools/pilbmp2nes.py \
  src/pently.inc src/pentlysound.s

AS65 = ca65
LD65 = ld65
CFLAGS65 = -DUSE_DAS=1 -DDPCM_UNSAFE_PADS=1
objdir:=obj/nes
srcdir:=src
imgdir:=tilesets
PENTLY_MASTER:=..

#EMU := "/C/Program Files/Nintendulator/Nintendulator.exe"
EMU := fceux
DEBUGEMU := ~/.wine/drive_c/Program\ Files\ \(x86\)/FCEUX/fceux.exe
# other options for EMU are start (Windows) or gnome-open (GNOME)

# Occasionally, you need to make "build tools", or programs that run
# on a PC that convert, compress, or otherwise translate PC data
# files into the format that the NES program expects.  Some people
# write their build tools in C or C++; others prefer to write them in
# Perl, PHP, or Python.  This program doesn't use any C build tools,
# but if yours does, it might include definitions of variables that
# Make uses to call a C compiler.
CC = gcc
CFLAGS = -std=gnu99 -Wall -DNDEBUG -O

# Things differing between UNIX and Windows.  COMSPEC will be set
# to the name of the shell on Windows and not defined on UNIX.
ifdef COMSPEC
  PY:=py
else
  PY:=python3
endif

.PHONY: run debug dist zip clean dep

run: $(title).nes
	$(EMU) $<
debug: $(title).nes
	$(DEBUGEMU) $<

clean:
	-rm $(objdir)/*.o $(objdir)/*.ch1 $(objdir)/*.chr $(objdir)/*.s
	-rm $(pentlyfiles)

# Rule to create or update the distribution zipfile by adding all
# files listed in zip.in.  Actually the zipfile depends on every
# single file in zip.in, but currently we use changes to the compiled
# program, makefile, and README as a heuristic for when something was
# changed.  It won't see changes to docs or tools, but usually when
# docs changes, README also changes, and when tools changes, the
# makefile changes.
dist: zip
zip: $(title)-$(version).zip
$(title)-$(version).zip: zip.in $(title).nes README.md CHANGES.txt $(objdir)/index.txt
	zip -9 -u $@ -@ < $<

$(objdir)/index.txt: makefile
	echo Files produced by build tools go here, but caulk goes where? > $@

# Rules for PRG ROM

objlistntsc = $(foreach o,$(objlist),$(objdir)/$(o).o)

map.txt $(title).nes: nrom128chrram.cfg $(objlistntsc)
	$(LD65) -o $(title).nes -C $^ -m map.txt

$(objdir)/%.o: $(srcdir)/%.s $(srcdir)/nes.inc $(srcdir)/global.inc $(srcdir)/mbyt.inc
	$(AS65) $(CFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(CFLAGS65) $< -o $@

# Files that depend on .incbin'd files
$(objdir)/bg.o: $(objdir)/sprites.chr $(objdir)/coltiles.ch1

# Generate lookup tables

$(objdir)/ntscPeriods.s: tools/pentlyas.py
	$(PY) $< --periods 64 -o $@

# Rules for graphics data conversion

$(objdir)/%.chr: $(imgdir)/%.png dep
	$(PY) tools/pilbmp2nes.py $< $@

$(objdir)/%.ch1: $(imgdir)/%.png dep
	$(PY) tools/pilbmp2nes.py -1 $< $@

$(objdir)/%.s: tools/vwfbuild.py tilesets/%.png
	$(PY) $^ $@

# Files identical to files in standard Pently so that they can be 
# .gitignore'd
dep: $(pentlyfiles)
$(pentlyfiles): %: $(PENTLY_MASTER)/%
	cp $< $@
