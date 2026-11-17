#!/usr/bin/env python3
"""Work around Dyad 3.5.0 `layout apply` attaching multi-way connection routes to the wrong ends.

apply numbers a multi-way connection's ends in the order its routes appear in the
solution (connections.ts getEndRefs), but readers take `S` as the index of the
connect() argument. Reordering each multi-way connection's routes into argument
order before `apply` makes the two agree.

usage: fix_junction_order.py PROB SOL DYADFILE COMPONENT OUT_SOL
"""
import json, re, sys
prob_f, sol_f, dyad_f, comp, out_f = sys.argv[1:]
prob = json.load(open(prob_f))['structure']
solfile = json.load(open(sol_f))
src = open(dyad_f).read()
m = re.search(r'^\s*(?:test |example |partial )*component ' + re.escape(comp) + r'\b', src, re.M)
blk = src[m.end():]
blk = blk[:re.search(r'^end\b', blk, re.M).start()]
stmts = [[e.strip() for e in s.split(',')] for s in re.findall(r'\bconnect\(([^)]*)\)', blk)]
def key(ref):
    return f"{ref['componentId']}.{ref['connectorId']}" if ref['type'] == 'component' else ref['connectorId']
arms = {}  # connection index -> list of (arm id, end name)
for c in prob['connections']:
    mm = re.fullmatch(r'__conn_(\d+)_(\d+)', c['id'])
    if mm:
        arms.setdefault(int(mm.group(1)), []).append((c['id'], key(c['from'])))
order = {}
for idx, lst in arms.items():
    names = {n for _, n in lst}
    hits = [s for s in stmts if len(s) == len(lst) and {re.sub(r'\s+', '', e) for e in s} == names]
    if len(hits) != 1:
        sys.exit(f'connection {idx}: could not find a unique connect() with ends {sorted(names)}')
    pos = {re.sub(r'\s+', '', e): i for i, e in enumerate(hits[0])}
    for arm, n in lst:
        order[arm] = (idx, pos[n])
rc = solfile['solution']['routedConnections']
two = [r for r in rc if r['connectionId'] not in order]
multi = sorted((r for r in rc if r['connectionId'] in order), key=lambda r: order[r['connectionId']])
solfile['solution']['routedConnections'] = two + multi
json.dump(solfile, open(out_f, 'w'), indent=1)
print(f'reordered {len(multi)} arms of {len(arms)} multi-way connections')
