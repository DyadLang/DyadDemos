#!/usr/bin/env python3
"""Report connect() statements in a component that carry no `edges` route metadata.

usage: verify_edges.py DYADFILE COMPONENT   -> exit 1 if any connect lacks edges
Needed because Dyad 3.5.0 `layout apply` intermittently writes placements but no routes.
"""
import re, sys
src = open(sys.argv[1]).read(); comp = sys.argv[2]
m = re.search(r'^\s*(?:test |example |partial )*component ' + re.escape(comp) + r'\b', src, re.M)
blk = src[m.end():]; blk = blk[:re.search(r'^end\b', blk, re.M).start()]
links = blk[blk.find('"_links"'):] if '"_links"' in blk else ''
missing = []; total = 0
for mm in re.finditer(r'\bconnect\(([^)]*)\)\s*(\{\^(\w+)\})?', blk):
    total += 1
    rest = blk[mm.end():mm.end() + 20000]
    if mm.group(3):  # tag style: look the tag up in _links
        lm = re.search(r'"' + re.escape(mm.group(3)) + r'"\s*:\s*\{\s*"Dyad"\s*:\s*\{[^}]*"edges"', links)
        ok = bool(lm)
    else:
        ok = rest.lstrip().startswith('{') and '"edges"' in rest[:rest.find('connect(') if 'connect(' in rest else len(rest)]
    if not ok: missing.append(mm.group(1).strip())
print(f'{comp}: {total - len(missing)}/{total} connections have edges')
for x in missing: print('  no edges: connect(' + x + ')')
sys.exit(1 if missing else 0)
