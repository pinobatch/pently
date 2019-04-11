#!/bin/sh
set -e

# Only if you've changed the driver
python3 ca65toasm6.py ../src/pently.inc ../src/pentlyseq.inc < /dev/null > pently-asm6.inc
python3 ca65toasm6.py ../src/pentlysound.s ../src/pentlymusic.s < /dev/null > pently-asm6.asm

# If you've changed pentlyconfig.inc
python3 ../tools/pentlybss.py --asm6 pentlyconfig.inc pentlymusicbase -o pentlybss.inc

# If you've changed the score
python3 ../tools/pentlyas.py --asm6 --periods 76 ../audio/musicseq.pently -o musicseq.asm < /dev/null

# Building and running the application
python3 ../tools/pilbmp2nes.py asm6shelltiles.png asm6shelltiles.chr < /dev/null
asm6 -L asm6shell.asm pently-asm6.nes
Mesen.exe pently-asm6.nes
