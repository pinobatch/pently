#!/usr/bin/env python3
"""
sick
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
- Replace :+ in an expression with @ca65toasm6_anonlabel_{anon_labels_seen+1}.
- Replace :- in an expression with @ca65toasm6_anonlabel_{anon_labels_seen}.


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
    lineparts = quotesRE.findall(line.rstrip())
    if lineparts and lineparts[-1].startswith(";"): del lineparts[-1]
    return "".join(lineparts)

def openreadlines(filename, xform=None):
    with open(filename, "r", encoding="utf-8") as infp:
        return [xform(x) if xform else x for x in infp]

def fix_pc_references(s):
    # This is not ideal, but it gets the job of translating ca65 *
    # to ASM6 $ done for any reference to the current PC that is
    # adjacent to the start or end of the expression or of a
    # parenthesized subexpression.
    if s.startswith('*'):
        s = '$' + s[1:]
    if s.endswith('*'):
        s = '$' + s[1:]
    return s.replace('(*', '($').replace('*)', '$)')

filestoload = [
    "pentlyconfig.inc", "pently.inc", "pentlyseq.inc",
    "pentlysound.s", "pentlymusic.s",
]

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

allfiles = [
    openreadlines(os.path.join("../src", n),
                  lambda x: uncomment(x).strip())
    for n in filestoload
]
lines = []
for filename in filestoload:
    lines.append('.segment ""')
    lines.extend(openreadlines(os.path.join("../src", filename),
                               lambda x: uncomment(x).strip()))

known_segs = ['', 'ZEROPAGE', 'BSS']
seg_lines = OrderedDict()
for seg in known_segs:
    seg_lines[seg] = []
cur_seg = ""
delay_labels = set()

anon_labels_seen = 0
anon_label_fmt = "@ca65toasm6_anonlabel_%d"
def resolve_anon_ref(m):
    s = m.group(0)
    distance = len(s) - 2
    if s[1] == '+':
        return anon_label_fmt % (anon_labels_seen + distance + 1)
    elif s[1] == '-':
        return anon_label_fmt % (anon_labels_seen - distance)
    else:
        raise ValueError("unknown anonref %s" % s)

for line in lines:
    if not line: continue
    words = line.split(None, 1)
    label = None

    if ':' in words[0] or (len(words) > 1 and words[1].startswith(':')):
        candidatelabel, candidateline = (s.strip() for s in line.split(':', 1))
        if candidateline.startswith(("+", "-", ":")):
            pass  # actually an anonymous label reference or scope resolution
        else:
            label, line = candidatelabel, candidateline
            if label == '':
                anon_labels_seen += 1
                label = anon_label_fmt % anon_labels_seen
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

    # Suggested by Overkill/egg boy color
    if False and line and words[0] in macros_equal_0:
        name_to_zero = words[1].split(',', 1)[0].strip()
        seg_lines[''].append(name_to_zero + " = 0  ; macro will change")

    equate = equateRE.match(line)
    if equate:
        label, expr = equate.groups()
        # Not sure if I want EQU or =, as EQU is for string
        # replacement (like ca65 .define) and = is for numbers,
        # but I don't know if = is required to be constant
        # at the time that line is assembled.
        words = [label, "=", expr]
        label = None

    for j in range(1, len(words)):
        operand = fix_pc_references(words[j])
        operand = quotesRE.findall(operand)
        for i in range(len(operand)):
            randpart = operand[i]
            if randpart.startswith(("'", '"')): continue
            randpart = randpart.replace("::", "")
            randpart = anonlabelrefRE.sub(resolve_anon_ref, randpart)
            operand[i] = randpart
        words[j] = operand = "".join(operand)

    line = " ".join(words)
    if label:
        line = "%s: %s" % (label, line)
        # A label used for a zero page "dsb" must come before all
        # "=" that refer to it, or (d,X) addressing will give error
        # "Incomplete expression".  So delay any segmentless equates
        # that refer to a label and occur before its definition.
        if cur_seg in ('ZEROPAGE', 'BSS'):
            delay_labels.add(label)

    seg_lines[cur_seg].append(line)

segmentless_lines = []
delayed_lines = []
for line in seg_lines.pop(''):
    words = wordRE.findall(line)
    if delay_labels.intersection(words):
        delayed_lines.append(line)
    else:
        segmentless_lines.append(line)

seg_lines.pop('ZEROPAGE', '')
seg_lines.pop('BSS', '')
    
print(";;; SEGMENTLESS")
print("\n".join(segmentless_lines))
print(";;; SEGMENTLESS DELAYED")
print("\n".join(delayed_lines))

for segment, seglines in seg_lines.items():
    print(";;; SEGMENT %s" % segment)
    print("\n".join(seglines))
