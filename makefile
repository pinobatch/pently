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
title := pently
version := 0.05wip11

# Name of Pently score for main targets "pently.nes" and "pently.nsf"
# is audio/$(scorename).pently, such as audio/musicseq.pently.
# To make a ROM or NSF based on a different score, such as
# audio/pino-a53.pently, use "make pino-a53.nsf".
scorename := musicseq

# Space-separated list of asm files that make up the ROM,
# whether source code or generated
objlist := main \
  pads ppuclear paldetect math bpmmath profiler vis \
  pentlysound pentlymusic
objlistnsf := pentlysound pentlymusic

# List of documents included in zipfile
docs_md := usage bytecode pentlyas famitracker

AS65 := ca65
ASFLAGS65 :=
LD65 := ld65
objdir := obj/nes
srcdir := src
imgdir := tilesets

FT2P := ../ft2pently/ft2p
FAMITRACKER := wine '/home/pino/.wine/drive_c/Program Files (x86)/FamiTracker/j0CC-Famitracker-j0.6.1.exe'
EMU := fceux --input1 GamePad.0
DEBUGEMU := ~/.wine/drive_c/Program\ Files\ \(x86\)/FCEUX/fceux.exe
# other options for EMU are start (Windows) or xdg-open (*n?x)

# Work around a quirk of how the Python 3 for Windows installer
# sets up the PATH
ifdef COMSPEC
PY:=py
else
PY:=
endif


.PHONY: run debug clean dist zip all zip.in

run: $(title).nes
	$(EMU) $<
debug: $(title).nes
	$(DEBUGEMU) $<
clean:
	-rm $(objdir)/*.o $(objdir)/*.s $(objdir)/*.chr $(objdir)/*.inc

# Rule to create or update the distribution zipfile by adding all
# files listed in zip.in.  Actually the zipfile depends on every
# single file in zip.in, but currently we use changes to the compiled
# program, makefile, and README as a heuristic for when something was
# changed.  It won't see changes to docs or tools, but usually when
# docs changes, README also changes, and when tools changes, the
# makefile changes.
dist: zip
zip: $(title)-$(version).zip
$(title)-$(version).zip: zip.in all CHANGES.txt \
  README.md CHANGES.txt $(foreach o,$(docs_md),docs/$(o).md) \
  $(objdir)/index.txt
	zip -9 -u $@ -@ < $<

# Build zip.in from the list of files in the Git tree
zip.in:
	git ls-files | grep -e "^[^.]" > $@
	echo pently.nes >> $@
	echo pently.nsf >> $@
	echo pently.nsfe >> $@
	echo zip.in >> $@

$(objdir)/index.txt: makefile
	echo "This file forces the creation of the folder for object files. You may delete it." > $@

# Rules for PRG ROM

objlisto := $(foreach o,$(objlist),$(objdir)/$(o).o)
objlistnsf := $(foreach o,$(objlistnsf),$(objdir)/$(o).o)

all: $(title).nes $(title).nsf $(title).nsfe

# These two build the main binary target
map.txt $(title).nes: nrom128.cfg $(objlisto) $(objdir)/tracknames-$(scorename).o $(objdir)/$(scorename)-rmarks.o
	$(LD65) -o $(title).nes -C $^ -m map.txt

nsfmap.txt $(title).nsf: nsf.cfg $(objdir)/nsfshell-$(scorename).o $(objlistnsf) $(objdir)/$(scorename).o
	$(LD65) -o $(title).nsf -C $^ -m nsfmap.txt

nsfemap.txt $(title).nsfe: nsfe.cfg $(objdir)/nsfeshell-$(scorename).o $(objlistnsf) $(objdir)/$(scorename).o
	$(LD65) -o $(title).nsfe -C $^ -m nsfemap.txt

# These two are for "make pino-a53.nsf" functionality
%.nes: nrom128.cfg $(objlisto) $(objdir)/tracknames-%.o $(objdir)/%-rmarks.o
	$(LD65) -o $@ -C $^

%.nsf: nsf.cfg $(objdir)/nsfshell-%.o $(objlistnsf) $(objdir)/%.o
	$(LD65) -o $@ -C $^

%.nsfe: nsfe.cfg $(objdir)/nsfeshell-%.o $(objlistnsf) $(objdir)/%.o
	$(LD65) -o $@ -C $^

$(objdir)/%.o: \
  $(srcdir)/%.s $(srcdir)/nes.inc $(srcdir)/shell.inc $(srcdir)/pently.inc
	$(AS65) $(ASFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(ASFLAGS65) $< -o $@

# Files that depend on additional headers
$(objdir)/musicseq.o $(objdir)/pentlymusic.o: $(srcdir)/pentlyseq.inc
$(objdir)/pentlysound.o $(objdir)/pentlymusic.o \
$(objdir)/bpmmath.o $(objdir)/vis.o $(objdir)/main.o: \
  $(srcdir)/pentlyconfig.inc
$(objdir)/nsfeshell-%.o $(objdir)/nsfshell-%.o: \
  $(srcdir)/pentlyconfig.inc $(srcdir)/nsfechunks.inc

$(objdir)/pentlymusic.o: $(objdir)/pentlybss.inc

# Files that depend on .incbin'd files
$(objdir)/main.o: \
  $(srcdir)/pentlyconfig.inc $(objdir)/bggfx.chr $(objdir)/spritegfx.chr

# Build RAM map
$(objdir)/pentlybss.inc: tools/pentlybss.py $(srcdir)/pentlyconfig.inc
	$(PY) $^ pentlymusicbase -o $@

# Translate music project
$(objdir)/%.s: tools/pentlyas.py audio/%.pently
	$(PY) $^ -o $@ --write-inc $(@:.s=-titles.inc) --periods 76
$(objdir)/%-titles.inc: $(objdir)/%.s
	touch $@
$(objdir)/nsfshell-%.s: $(objdir)/%-titles.inc $(srcdir)/nsfshell.s
	cat $^ > $@
$(objdir)/nsfeshell-%.s: $(objdir)/%-titles.inc $(srcdir)/nsfeshell.s
	cat $^ > $@

# Translate music project with bookmarks/rehearsal marks
$(objdir)/%-rmarks.s: tools/pentlyas.py audio/%.pently
	$(PY) $^ -o $@ --write-inc $(@:-rmarks.s=-titles.inc) --periods 76 --rehearse
$(objdir)/tracknames-%.s: $(objdir)/%-titles.inc $(srcdir)/tracknames.s
	cat $^ > $@

# Translate FamiTracker music project

$(objdir)/%.ftm.txt: audio/%.ftm
	$(FAMITRACKER) $< -export $@
$(objdir)/%.ftm.txt: audio/%.0cc
	$(FAMITRACKER) $< -export $@
$(objdir)/%.pently: $(objdir)/%.ftm.txt
	$(FT2P) -i $< -o $@

$(objdir)/%.s: tools/pentlyas.py $(objdir)/%.pently
	$(PY) $^ -o $@ --write-inc $(@:.s=-titles.inc) --periods 76
$(objdir)/%-rmarks.s: tools/pentlyas.py $(objdir)/%.pently
	$(PY) $^ -o $@ --write-inc $(@:-rmarks.s=-titles.inc) --periods 76 --rehearse

# Rules for CHR ROM

$(objdir)/%.chr: $(imgdir)/%.png
	$(PY) tools/pilbmp2nes.py $< $@
