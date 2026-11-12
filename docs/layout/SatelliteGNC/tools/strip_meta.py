#!/usr/bin/env python3
"""Print a .dyad file with all metadata removed and whitespace normalised.

Removes inline JSON metadata ({"Dyad": ...}), {^tag} references and the
component-level `metadata ... ` section, so two versions of a file can be
compared for non-metadata changes (equations, connections, declarations).
usage: strip_meta.py FILE
"""
import re
import sys

src = open(sys.argv[1]).read()
out, i, n = [], 0, len(src)


def skip_brace(i):
    depth, instr, esc = 0, False, False
    for j in range(i, n):
        c = src[j]
        if instr:
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == '"':
                instr = False
            continue
        if c == '"':
            instr = True
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return j + 1
    raise SystemExit('unbalanced')


while i < n:
    if src[i] == '{':
        i = skip_brace(i)
        continue
    if src[i] == '#':                      # comments are kept verbatim
        j = src.find('\n', i)
        j = n if j < 0 else j
        out.append(src[i:j])
        i = j
        continue
    m = re.match(r'metadata\b', src[i:])
    if m and (i == 0 or src[i - 1] in ' \t\n'):
        # component metadata section runs to the component's `end`
        k = re.search(r'^end\b', src[i:], re.M)
        i += k.start()
        continue
    out.append(src[i])
    i += 1
text = ''.join(out)
lines = [re.sub(r'\s+', ' ', l).strip() for l in text.splitlines()]
print('\n'.join(l for l in lines if l))
