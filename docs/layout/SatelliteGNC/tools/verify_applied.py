#!/usr/bin/env python3
"""Check that a component's diagram metadata is exactly a given layout solution.

Dyad 3.5.0 `layout apply` sometimes reports `wrote <file>` but leaves the old
placements/routes in the file.  This compares every instance placement and every
connection's route (as written by apply: {"S":1,"M":[...],"E":2}, or the
junction form written by add_junctions.py) with the solution, after working out
the half-square origin apply used.

usage: verify_applied.py DYADFILE COMPONENT PROB.json SOL.json   (exit 1 on mismatch)
"""
import json
import re
import sys

dyad_f, comp, prob_f, sol_f = sys.argv[1:]
HS = 50
prob = json.load(open(prob_f))['structure']
sol = json.load(open(sol_f))['solution']
src = open(dyad_f).read()
m = re.search(r'^\s*(?:test |example |partial )*component ' + re.escape(comp) + r'\b', src, re.M)
start = m.end()
end = start + re.search(r'^end\b', src[start:], re.M).start()
blk = src[start:end]


def match_brace(s, i):
    depth, instr, esc = 0, False, False
    for j in range(i, len(s)):
        c = s[j]
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
                return j
    raise SystemExit('unbalanced braces')


def meta_after(i):
    j = match_brace(blk, i)
    return json.loads(blk[i:j + 1])


bad = []
placed = {}
for mm in re.finditer(r'^\s*(\w+)\s*=\s*\w[\w.]*\((?:[^()]|\([^()]*\))*\)\s*\{', blk, re.M):
    md = meta_after(mm.end() - 1)
    d = md.get('Dyad', {}).get('placement', {}).get('diagram')
    if d:
        placed[mm.group(1)] = ((d['x1'] + d['x2']) / 2 / HS, (d['y1'] + d['y2']) / 2 / HS)
want = {p['componentId']: (p['center']['x'], p['center']['y']) for p in sol['componentPlacements']}
ref = next(iter(want))
if ref not in placed:
    sys.exit(f'{comp}: {ref} has no placement in the file')
ox, oy = placed[ref][0] - want[ref][0], placed[ref][1] - want[ref][1]
for cid, (x, y) in want.items():
    got = placed.get(cid)
    if got is None or abs(got[0] - (x + ox)) > 1e-6 or abs(got[1] - (y + oy)) > 1e-6:
        bad.append(f'placement of {cid}: file {got}, solution {(x + ox, y + oy)}')

ends = {c['id']: (f"{c['from']['componentId']}.{c['from']['connectorId']}", f"{c['to']['componentId']}.{c['to']['connectorId']}")
        for c in prob['connections']}
route = {ends[r['connectionId']]: [((p['x'] + ox) * HS, (p['y'] + oy) * HS) for p in r['waypoints']]
         for r in sol['routedConnections']}
for mm in re.finditer(r'\bconnect\(([^)]*)\)\s*\{', blk):
    e = tuple(x.strip() for x in mm.group(1).split(','))
    md = meta_after(mm.end() - 1)['Dyad']
    pts = route[e]
    edges = md.get('edges', [])
    if len(edges) == 1:
        got = [(p['x'], p['y']) for p in edges[0]['M']]
        if got != pts[1:-1]:
            bad.append(f'route of connect{e}: file {got}, solution {pts[1:-1]}')
    elif len(edges) == 2 and md.get('junctions'):
        j = (md['junctions'][0]['x'], md['junctions'][0]['y'])
        seq = edges[0]['M'] + edges[1]['M']
        got = [(p['x'], p['y']) for p in seq]
        if edges[0]['S'] == 2:
            pts = pts[::-1]
        # the junction lies on the route; corners other than it must match
        full = [q for q in pts[1:-1] if q != j]
        if got != full:
            bad.append(f'route of connect{e} (junction): file {got}, solution {full}')
    else:
        bad.append(f'connect{e}: unexpected edges {edges}')
for b in bad:
    print('  ' + b)
print(f'{comp}: {"MISMATCH" if bad else "matches the solution"}')
sys.exit(1 if bad else 0)
