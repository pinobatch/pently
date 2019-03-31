#!/bin/sh
set -e

# Make sure we have a music file
OLDCWD=$(pwd)
echo "running in $OLDCWD"
cd ..
make obj/nes/musicseq.s
cd "$OLDCWD"

python3 ../tools/pilbmp2nes.py sicktiles.png sicktiles.chr < /dev/null
python3 sick.py < /dev/null > pently.asm6
asm6 -L shell.asm6 sick.nes sick.lst.txt
Mesen.exe sick.nes
#fceux sick.nes
