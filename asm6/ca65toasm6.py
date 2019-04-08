#!/usr/bin/env python3
"""
ca65toasm6
translate Pently from ca65 to ASM6

Rules for ASM6
- Assembler directives need not have a leading dot
- $ replaces * as current PC
- = behaves as .set
- If right side of = is above the definition of a ZP variable,
  indirect addressing modes may fail, so move the = down
- equ replaces .define
- db or byte replaces .byt
- dw or word replaces .addr
- dsb replaces .res
- rept (with no second argument) replaces .repeat; emulate the second
  argument with =
- rept 1 replaces .scope and .proc
- No .bss; emulate it with enum...ende and dsb (may need caller to
  allocate both zero page and BSS memory)
- No other .segment; treat code and read-only data the same
- No .assert; emulate it with if
- No variadic macros
- Unnamed labels follow the x816 convention (-, --, +foo), not the ca65
  convention (:). Change them as described below
- All symbols defined in a macro are local, but macros can reassign
  existing symbols.

Anonymous labels should be easier to translate automatically.

- At the start of translation, set a counter to 0.
- When a line's label is :, increase the counter by 1 and then emit a
  label of the form @ca65toasm6_anonlabel_1:.
- Replace :+ in an expression with @ca65toasm6_anonlabel_{anoncount+1}.
- Replace :- in an expression with @ca65toasm6_anonlabel_{anoncount}.


"""
import sys
import os
import re
from collections import OrderedDict
from itertools import chain

quotesRE = r"""[^"';]+|"[^"]*"|'[^']*'|;.*"""
quotesRE = re.compile(quotesRE)
equateRE = r"""\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|\.set)\s*(.*)"""
equateRE = re.compile(equateRE, re.IGNORECASE)
anonlabelrefRE = r""":([+]+|[-]+)"""
anonlabelrefRE = re.compile(anonlabelrefRE)
wordRE = r"""\s*([A-Za-z_][A-Za-z0-9_]*)"""
wordRE = re.compile(wordRE)

def uncomment(line):
    """Remove the comment from a line of ca65 source code."""
    lineparts = quotesRE.findall(line.rstrip())
    if lineparts and lineparts[-1].startswith(";"): del lineparts[-1]
    return "".join(lineparts)

def openreadlines(filename, xform=None):
    """Open a file and return a list of all its lines.

xform -- a function to run on all lines"""
    with open(filename, "r", encoding="utf-8") as infp:
        return [xform(x) if xform else x for x in infp]

def fix_pc_references(s):
    """Translate references to the current program counter from ca65 to ASM6.

ca65 uses * for PC; ASM6 uses $.
Only references at the start or end of an expression or of a
parenthesized subexpression get translated.  But that should be
enough for our use case, as the source code can use (*) to produce
($) in the translation.
"""
    if s.startswith('*'):
        s = '$' + s[1:]
    if s.endswith('*'):
        s = '$' + s[1:]
    return s.replace('(*', '($').replace('*)', '$)')

class AnonLabelCounter(object):
    def __init__(self, start=0, prefix="@ca65toasm6_anonlabel_"):
        self.count = start
        self.prefix = prefix

    def inc(self):
        self.count += 1

    def format(self, count=None):
        if count is None:
            count = self.count
        return "%s%d" % (self.prefix, count)

    def resolve_anonref(self, m):
        """Translate a match whose group 0 is :+, :++, :-, or :-- to a label"""
        s = m.group(0)
        distance = len(s) - 2
        if s[1] == '+':
            return self.format(self.count + distance + 1)
        elif s[1] == '-':
            if self.count - distance < 0:
                raise ValueError("anonref %s points before start" % s)
            return self.format(self.count - distance)
        else:
            raise ValueError("unknown anonref %s" % s)

    def resolve_anonrefs(self, s):
        return anonlabelrefRE.sub(self.resolve_anonref, s)

directive_ignore = {
    'import', 'export', 'importzp', 'exportzp', 'global', 'globalzp',
    'include', 'assert', 'pushseg', 'popseg',
    'res'
}
    
directive_translation = {
    'if': 'if', 'else': 'else', 'elseif': 'elseif', 'endif': 'endif',
    'ifdef': 'ifdef', 'ifndef': 'ifndef',
    'byt': 'db', 'byte': 'db', 'word': 'dw', 'addr': 'dw', 'res': 'dsb',
    'endproc': 'endr', 'endscope': 'endr',
    'macro': 'macro', 'endmacro': 'endm'
}

macros_equal_0 = {
    'sfxdef', 'instdef', 'drumdef', 'songdef', 'patdef'
}

known_segs = ['', 'ZEROPAGE', 'BSS']

def translate(filestoload):
    lines = []
    for filename in filestoload:
        lines.append('.segment ""')
        lines.extend(openreadlines(filename,
                                   lambda x: uncomment(x).strip()))

    anoncount = AnonLabelCounter()
    seg_lines = OrderedDict((k, []) for k in known_segs)
    cur_seg = ""

    for line in lines:
        if not line: continue
        words = line.split(None, 1)
        label = None

        if ':' in words[0] or (len(words) > 1 and words[1].startswith(':')):
            candidatelabel, candidateline = (s.strip() for s in line.split(':', 1))
            # Ensure it's not actually an anonymous label reference
            # or scope resolution
            if not candidateline.startswith(("+", "-", ":")):
                label, line = candidatelabel, candidateline
                if label == '':
                    anoncount.inc()
                    label = anoncount.format()
                words = line.split(None, 1)
        else:
            label = None

        # Dot-directives
        if line.startswith('.'):
            word0 = words[0].lower().lstrip('.')
            if word0 in directive_ignore:
                continue

            # Because ASM6 appears to lack any sort of support for
            # variadic macros, treat all arguments as nonblank and
            # modify pentlyas to never omit arguments.
            # https://forums.nesdev.com/viewtopic.php?f=2&t=18610
            if word0 == 'ifblank':
                seg_lines[cur_seg].append('if 0  ; was ifblank')
                continue
            if word0 == 'ifnblank':
                seg_lines[cur_seg].append('if 1  ; was ifnblank')
                continue

            if word0 == 'ifndef' and words[1].endswith('_INC'):
                seg_lines[cur_seg].append('if 1  ; was include guard')
                continue

            if word0 == 'zeropage':
                cur_seg = 'ZEROPAGE'
                continue
            if word0 == 'bss':
                cur_seg = 'BSS'
                continue
            if word0 == 'segment':
                cur_seg = words[1].strip('"').upper()
                seg_lines.setdefault(cur_seg, [])
                continue
            if word0 == 'scope':
                seg_lines[cur_seg].append('rept 1')
                continue
            if word0 == 'proc':
                seg_lines[cur_seg].append('%s: rept 1' % words[1])
                continue

            if word0 == 'define':
                dfnparts = words[1].split(None, 1)
                word0 = dfnparts[0]
                words = [word0, "equ %s" % (dfnparts[1])]
            elif word0 in directive_translation:
                words[0] = directive_translation[word0]
                word0 = words[0]
            else:
                print("unknown directive", line, file=sys.stderr)
                continue

        # EQU is for string replacement (like ca65 .define),
        # and = is for numbers.
        equate = equateRE.match(line)
        if equate:
            label, expr = equate.groups()
            words = [label, "=", expr]
            label = None

        # Translate references to the program counter,
        # to top-level scopes, and to anonymous labels
        for j in range(1, len(words)):
            operand = fix_pc_references(words[j])
            operand = quotesRE.findall(operand)
            for i in range(len(operand)):
                randpart = operand[i]
                if randpart.startswith(("'", '"')): continue
                randpart = randpart.replace("::", "")
                randpart = anoncount.resolve_anonrefs(randpart)
                operand[i] = randpart
            words[j] = operand = "".join(operand)

        # And stick it in the current segment
        line = " ".join(words)
        if label:
            line = "%s: %s" % (label, line)
        seg_lines[cur_seg].append(line)

    # These segments allocate RAM variables by stuffing them into
    # a ca65 segment with a conventional name.  Omit them from the
    # translation because ASM6 libraries instead allocate variables by
    # collecting them in a file that the app includes within an enum.
    seg_lines.pop('ZEROPAGE', '')
    seg_lines.pop('BSS', '')

    out = []
    for segment, seglines in seg_lines.items():
        out.append(";;; SEGMENT %s" % segment)
        out.extend(seglines)
    out.append("")
    return "\n".join(out)


xlated = translate(sys.argv[1:])
sys.stdout.write(xlated)
