#!/usr/bin/make -f
#
# Makefile for Pently music engine
# Copyright 2012-2015 Damian Yerrick
#
# Copying and distribution of this file, with or without
# modification, are permitted in any medium without royalty
# provided the copyright notice and this notice are preserved.
# This file is offered as-is, without any warranty.
#

# These are used in the title of the NES program and the zip file.
title = pently
version = 0.05wip3

# Space-separated list of assembly language files that make up the
# PRG ROM.  If it gets too long for one line, you can add a backslash
# (the \ character) at the end of the line and continue on the next.
objlist := main \
  pads ppuclear paldetect bcd math bpmmath \
  pentlysound pentlymusic musicseq ntscPeriods
objlistnsf := nsfshell \
  pentlysound pentlymusic musicseq ntscPeriods

AS65 = ca65
LD65 = ld65
CFLAGS65 := 
objdir = obj/nes
srcdir = src
imgdir = tilesets

#EMU := "/C/Program Files/Nintendulator/Nintendulator.exe"
EMU := fceux --input1 GamePad.0
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

# Windows needs .exe suffixed to the names of executables; UNIX does
# not.  COMSPEC will be set to the name of the shell on Windows and
# not defined on UNIX.
ifdef COMSPEC
DOTEXE=.exe
else
DOTEXE=
endif

.PHONY: run dist zip

run: $(title).nes
	$(EMU) $<

# Rule to create or update the distribution zipfile by adding all
# files listed in zip.in.  Actually the zipfile depends on every
# single file in zip.in, but currently we use changes to the compiled
# program, makefile, and README as a heuristic for when something was
# changed.  It won't see changes to docs or tools, but usually when
# docs changes, README also changes, and when tools changes, the
# makefile changes.
dist: zip
zip: $(title)-$(version).zip
$(title)-$(version).zip: zip.in $(title).nes $(title).nsf \
  TODO.txt README.txt CHANGES.txt docs/pently_manual.html \
  $(objdir)/index.txt
	zip -9 -u $@ -@ < $<

$(objdir)/index.txt: makefile
	echo "This file forces the creation of the folder for object files. You may delete it." > $@

# Rules for PRG ROM

objlistntsc := $(foreach o,$(objlist),$(objdir)/$(o).o)
objlistnsf := $(foreach o,$(objlistnsf),$(objdir)/$(o).o)

map.txt $(title).nes: nrom128.cfg $(objlistntsc)
	$(LD65) -o $(title).nes -C $^ -m map.txt

nsfmap.txt $(title).nsf: nsf.cfg $(objlistnsf)
	$(LD65) -o $(title).nsf -C $^ -m nsfmap.txt

$(objdir)/%.o: $(srcdir)/%.s $(srcdir)/nes.inc $(srcdir)/shell.inc
	$(AS65) $(CFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(CFLAGS65) $< -o $@

# Files that depend on additional headers
$(objdir)/musicseq.o $(objdir)/pentlymusic.o: $(srcdir)/pentlyseq.inc

# Files that depend on .incbin'd files
$(objdir)/main.o: tracknames.txt $(objdir)/bggfx.chr

# Generate lookup tables at build time
$(objdir)/ntscPeriods.s: tools/mktables.py
	$< period $@

# Translate music project
$(objdir)/%.s: tools/pentlyas.py src/%.pently
	$^ > $@

# Rules for CHR ROM

$(objdir)/%.chr: $(imgdir)/%.png
	tools/pilbmp2nes.py $< $@
