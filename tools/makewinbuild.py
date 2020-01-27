#!/usr/bin/env python3
"""
Make a Windows batch file for building ca65 Pently.
Usage:
make clean && make -n COMSPEC=cmd pently.nes | tools/makewinbuild.py
"""
import sys

prolog = """@echo off
echo Building from batch file
@echo on
"""
linesuffix = " || goto :error\n"
epilog = """goto EOF
:error
echo Failed with error #%errorlevel%.
pause
"""

lines = [prolog]
for line in sys.stdin:
    words = line.split()
    if words[0] in ("touch", "rm") or words[0].startswith("make["):
        continue
    if words[0] == "python3":
        words[0] = "py -3"
    if words[0] == "cat":
        lpart, rpart = line.split(">", 1)
        words = lpart.split()
        words = ["copy", "+".join(words[1:]).replace("/", "\\"), rpart.strip()]
    lines.append(" ".join(words) + linesuffix)
lines.append(epilog)

with open("winbuild.bat", "w", newline="\r\n") as outfp:
    outfp.writelines(lines)
