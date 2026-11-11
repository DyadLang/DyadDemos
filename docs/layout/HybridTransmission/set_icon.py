#!/usr/bin/env python3
"""set_icon.py FILE CONN=CX,CY ...

Add a `placement.icon` box (100x100, centred at CX,CY in the 0..1000 icon frame) to
each named connector's `_links` entry, in front of its existing `diagram` placement.
Without an explicit icon placement the renderer falls back to the diagram placement,
so connectors of leaf components otherwise show up wherever their diagram box is.
"""
import re, sys

f, *specs = sys.argv[1:]
s = open(f).read()
for spec in specs:
    name, xy = spec.split('=')
    cx, cy = (float(t) for t in xy.split(','))
    box = ', '.join(f'"{k}": {v:.4f}'.rstrip('0').rstrip('.') for k, v in
                    (('x1', cx - 50), ('y1', cy - 50), ('x2', cx + 50), ('y2', cy + 50)))
    icon = '"icon": {"iconName": "default", ' + box + ', "rot": 0}'
    m = re.search(r'("' + re.escape(name) + r'": \{\s*"Dyad": \{\s*"placement": \{)(\s*)', s)
    if not m:
        sys.exit(f'no placement block for connector {name}')
    if s[m.end():].lstrip().startswith('"icon"'):
        sys.exit(f'{name} already has an icon placement')
    s = s[:m.end()] + icon + ',' + m.group(2) + s[m.end():]
open(f, 'w').write(s)
