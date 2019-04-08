#!/bin/sh
set -e

python3 ../tools/pilbmp2nes.py asm6shelltiles.png asm6shelltiles.chr < /dev/null
python3 ../tools/pentlybss.py --asm6 pentlyconfig.inc pentlymusicbase -o pentlybss.inc
python3 ../tools/pentlyas.py --asm6 --periods 76 ../audio/musicseq.pently -o musicseq.asm < /dev/null
python3 ca65toasm6.py pentlyconfig.inc ../src/pently.inc ../src/pentlyseq.inc ../src/pentlysound.s ../src/pentlymusic.s < /dev/null > pently.asm
asm6 -L asm6shell.asm pently-asm6.nes
Mesen.exe pently-asm6.nes
