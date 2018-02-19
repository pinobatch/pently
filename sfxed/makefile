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
audio_modules := sound ntscPeriods
objlist := $(align_sensitive_modules) $(game_modules) \
  $(lib_modules) $(audio_modules)

AS65 = ca65
LD65 = ld65
CFLAGS65 = -DUSE_DAS=1 -DDPCM_UNSAFE_PADS=1
objdir = obj/nes
srcdir = src
imgdir = tilesets

#EMU := "/C/Program Files/Nintendulator/Nintendulator.exe"
EMU := fceux
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

.PHONY: run dist zip clean

run: $(title).nes
	$(EMU) $<

clean:
	-rm $(objdir)/*.o $(objdir)/*.chr $(objdir)/*.ov53 $(objdir)/*.sav $(objdir)/*.pb53 $(objdir)/*.s

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

$(objdir)/%.o: $(srcdir)/%.s $(srcdir)/nes.h $(srcdir)/ram.h $(srcdir)/mbyt.h
	$(AS65) $(CFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(CFLAGS65) $< -o $@

# Files that depend on .incbin'd files
$(objdir)/bg.o: $(objdir)/sprites.chr $(objdir)/coltiles.ch1

# Generate lookup tables

$(objdir)/ntscPeriods.s: tools/mktables.py
	$< period $@

# Rules for graphics data conversion

$(objdir)/menu_furni.pb53: $(objdir)/menu_furni16.chr
	tools/pb53.py --block-size=4 --no-prev $< $@

$(objdir)/%.pb53: $(objdir)/%
	tools/pb53.py --raw $< $@

$(objdir)/%.chr: $(imgdir)/%.png
	tools/pilbmp2nes.py $< $@

$(objdir)/%.ch1: $(imgdir)/%.png
	tools/pilbmp2nes.py -1 $< $@

$(objdir)/%16.chr: $(imgdir)/%.png
	tools/pilbmp2nes.py -H 16 $< $@

$(objdir)/%.s: tools/vwfbuild.py tilesets/%.png
	$^ $@

# Currently unused

$(objdir)/title2.sav: $(imgdir)/titlewordmark.png
	tools/savtool.py --palette=0f1016290f1012290f0016290f161229 $< $@

$(objdir)/titlescreensprites.ov53: tools/mkspritemap.py \
$(srcdir)/titlescreensprites.in $(imgdir)/titlespritelayer.png
	$^ $@

