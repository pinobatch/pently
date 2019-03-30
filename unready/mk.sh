#!/bin/sh
set -e
python3 ../tools/pilbmp2nes.py sicktiles.png sicktiles.chr
asm6 shell.asm6 sick.nes
