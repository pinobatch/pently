#!/bin/sh
set -e

python3 ../tools/pilbmp2nes.py sicktiles.png sicktiles.chr < /dev/null
python3 ../tools/pentlyas.py --asm6 --periods 76 ../audio/musicseq.pently -o musicseq.asm6 < /dev/null
python3 sick.py < /dev/null > pently.asm6
asm6 -L shell.asm6 sick.nes sick.lst.txt
Mesen.exe sick.nes
#fceux sick.nes
