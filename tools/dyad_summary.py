#!/usr/bin/env python3
"""Summarise .dyad components: connectors, sub-blocks, connect() nets, metadata-free view.

usage: dyad_summary.py FILE [COMPONENT...]
"""
import re
import sys


def strip_meta(src):
    # remove { ... } metadata blocks and annotation blocks after declarations/connects
    out = []
    i = 0
    depth = 0
    in_str = False
    while i < len(src):
        c = src[i]
        if in_str:
            out.append(c)
            if c == '"':
                # handle """ docstrings crudely
                if src.startswith('"""', i):
                    pass
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == '{':
            depth += 1
            i += 1
            continue
        if depth:
            if c == '}':
                depth -= 1
            i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def components(src):
    # find top-level `component NAME` ... `end` blocks
    for m in re.finditer(r'(?m)^((?:test |example |partial )*)component (\w+)\b', src):
        start = m.end()
        # matching end: next ^end at column 0
        em = re.search(r'(?m)^end\b', src[start:])
        yield m.group(1).strip(), m.group(2), src[m.start():start + em.end() if em else len(src)]


def main():
    path = sys.argv[1]
    want = sys.argv[2:]
    src = open(path).read()
    for kind, name, blk in components(src):
        if want and name not in want:
            continue
        print(f'=== {kind + " " if kind else ""}component {name} ({path})')
        body = blk
        rel = body.find('relations')
        decl = body[:rel if rel >= 0 else len(body)]
        rels = body[rel:] if rel >= 0 else ''
        decl = strip_meta(decl)
        for line in decl.splitlines():
            line = line.strip()
            if not line or line.startswith('#') or line.startswith('component') or line.startswith('"') and line.endswith('"'):
                continue
            print('  D', line[:160])
        rels2 = strip_meta(rels)
        for line in rels2.splitlines():
            line = line.strip()
            if not line or line.startswith('#') or line == 'relations' or line == 'end' or line.startswith('metadata'):
                continue
            print('  R', line[:200])


if __name__ == '__main__':
    main()
