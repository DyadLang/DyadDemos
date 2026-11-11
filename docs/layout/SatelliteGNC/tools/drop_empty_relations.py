#!/usr/bin/env python3
"""Undo the empty `relations` section `dyad format` / `layout apply` add to analyses.

Dyad 3.5.0 re-prints a whole file when it formats it or applies a layout, and
gives every `analysis` block an empty `relations` section.  It changes nothing,
but it is not layout metadata, so where the original file (same name in REFDIR)
has the analysis without one, it is taken out again.

usage: drop_empty_relations.py REFDIR DYADFILE...
"""
import os
import re
import sys

ANALYSIS = r'^analysis (\w+)[^\n]*\n(?:[ \t][^\n]*\n)*'


def without_relations(src):
    """names of the analyses that have no relations section"""
    out = set()
    for m in re.finditer(ANALYSIS + r'(\w+)', src, re.M):
        if m.group(2) != 'relations':
            out.add(m.group(1))
    return out


refdir, *paths = sys.argv[1:]
for path in paths:
    ref = os.path.join(refdir, os.path.basename(path))
    if not os.path.exists(ref):
        continue
    bare = without_relations(open(ref).read())
    src = open(path).read()
    n = 0

    def drop(m):
        global n
        if m.group(1) in bare:
            n += 1
            return m.group(0)[:-len('relations\nend')] + 'end'
        return m.group(0)

    src = re.sub(ANALYSIS + r'relations\nend\b', drop, src, flags=re.M)
    if n:
        open(path, 'w').write(src)
        print(f'{path}: dropped {n} empty relations section(s)')
