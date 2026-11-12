#!/usr/bin/env python3
"""Resize instance boxes in a parent diagram to the children's canonical sizes.

usage: set_boxes.py DYADFILE COMPONENT inst=SIZE [inst=SIZE ...]
Keeps an existing box's centre (snapped to the 50-unit grid); instances with no
placement get a `{^inst}` tag and a box in a simple row so extract has a seed.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dyadmeta as dm  # noqa: E402

path, comp, *args = sys.argv[1:]
sizes = {a.split('=')[0]: int(a.split('=')[1]) for a in args}
src = open(path).read()
src = dm.ensure_tags(src, comp, list(sizes))
open(path, 'w').write(src)
_, meta, _, _ = dm.load(path, comp)
x = 0
for inst, S in sizes.items():
    lk = dm.link(meta, inst)
    pl = lk.setdefault('placement', {})
    d = pl.get('diagram')
    if d:
        cx = round((d['x1'] + d['x2']) / 2 / 50) * 50
        cy = round((d['y1'] + d['y2']) / 2 / 50) * 50
    else:
        cx, cy = x + S / 2, S / 2
        x += S + 200
    # keep the box corner on the grid: a centre on the grid with S a multiple of 100
    pl['diagram'] = {'iconName': 'default', 'x1': cx - S / 2, 'y1': cy - S / 2,
                     'x2': cx + S / 2, 'y2': cy + S / 2, 'rot': 0}
    for k in ('x1', 'y1', 'x2', 'y2'):
        v = pl['diagram'][k]
        pl['diagram'][k] = int(v) if v == int(v) else v
    lk.setdefault('tags', [])
dm.save(path, comp, meta)
print(f'{comp}: resized {", ".join(f"{k}={v}" for k, v in sizes.items())}')
