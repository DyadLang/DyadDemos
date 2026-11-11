#!/usr/bin/env python3
"""Draw a junction dot where one connection branches off another from the same port.

`dyad layout apply` writes every two-ended connect() as a single edge
{"S": 1, "M": [...], "E": 2}.  When two connections leave the same port and share
the first part of their route (reroute.py routes them that way), the branch is
drawn without a dot and reads like a crossing.  Dyad's own junction form for a
two-ended connection, as the editor writes it, is

    "edges": [{"S": 1, "M": [...], "E": -1}, {"S": -1, "M": [...], "E": 2}],
    "junctions": [{"x": .., "y": ..}]

i.e. port -> junction -> port.  This rewrites the branching connection into that
form, with the junction where it leaves the shared route.  Only metadata changes.

usage: add_junctions.py DYADFILE COMPONENT PROB.json SOL.json
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


def ref(r):
    return f"{r['componentId']}.{r['connectorId']}"


conn_ends = {c['id']: (ref(c['from']), ref(c['to'])) for c in prob['connections']}
routes = {r['connectionId']: [(p['x'] * HS, p['y'] * HS) for p in r['waypoints']] for r in sol['routedConnections']}
by_ends = {ends: cid for cid, ends in conn_ends.items()}

stmts = []   # (ends, meta_start, meta_end, meta)
for mm in re.finditer(r'\bconnect\(([^)]*)\)\s*\{', src[start:end]):
    ends = tuple(e.strip() for e in mm.group(1).split(','))
    if len(ends) != 2:
        continue
    i = start + mm.end() - 1
    j = match_brace(src, i)
    stmts.append((ends, i, j, json.loads(src[i:j + 1])))


def unit_path(pts):
    out = [pts[0]]
    for p, q in zip(pts, pts[1:]):
        dx = (q[0] > p[0]) - (q[0] < p[0])
        dy = (q[1] > p[1]) - (q[1] < p[1])
        n = int(max(abs(q[0] - p[0]), abs(q[1] - p[1])) // HS)
        for k in range(1, n + 1):
            out.append((p[0] + dx * k * HS, p[1] + dy * k * HS))
    return out


def corners(path):
    """interior corner points of a unit path"""
    c = []
    for i in range(1, len(path) - 1):
        d0 = (path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1])
        d1 = (path[i + 1][0] - path[i][0], path[i + 1][1] - path[i][1])
        if d0 != d1:
            c.append(path[i])
    return c


info = {}
for ends, i, j, meta in stmts:
    cid = by_ends.get(ends)
    if cid is None:
        raise SystemExit(f'connect{ends} not in the solution')
    pts = routes[cid]
    e = meta['Dyad']['edges']
    if len(e) == 1:   # sanity: apply wrote exactly the solution's interior points
        got = [(p['x'], p['y']) for p in e[0]['M']]
        assert got == pts[1:-1], (ends, got, pts)
    info[ends] = (i, j, meta, unit_path(pts))

edits = []
by_port = {}
for ends in info:
    for k, port in enumerate(ends):
        by_port.setdefault(port, []).append((ends, k))
done = set()
for port, lst in by_port.items():
    if len(lst) < 2:
        continue
    assert len(lst) == 2, f'{port}: more than two connections, not handled'
    (e1, k1), (e2, k2) = lst
    p1 = info[e1][3] if k1 == 0 else info[e1][3][::-1]
    p2 = info[e2][3] if k2 == 0 else info[e2][3][::-1]
    n = 0
    while n < min(len(p1), len(p2)) and p1[n] == p2[n]:
        n += 1
    if n <= 1:
        continue          # no shared stretch: the wires only meet at the port
    J = p1[n - 1]
    # the branch is the one that turns at J; the other runs straight through it
    def turns(p):
        if n >= len(p):
            return True
        a, b = p[n - 2], p[n]
        return not (a[0] == b[0] or a[1] == b[1])
    if turns(p2) and not turns(p1):
        br, kb, path = e2, k2, p2
    elif turns(p1) and not turns(p2):
        br, kb, path = e1, k1, p1
    else:
        br, kb, path = (e2, k2, p2) if len(p2) >= len(p1) else (e1, k1, p1)
    assert br not in done, f'{br} branches twice'
    done.add(br)
    shared, rest = path[:n], path[n - 1:]
    s_idx, o_idx = kb + 1, 2 - kb
    i, j, meta, _ = info[br]
    pt = lambda q: {'x': q[0], 'y': q[1]}
    d = meta['Dyad']
    d['edges'] = [{'S': s_idx, 'M': [pt(q) for q in corners(shared)], 'E': -1},
                  {'S': -1, 'M': [pt(q) for q in corners(rest)], 'E': o_idx}]
    d['junctions'] = [pt(J)]
    edits.append((i, j, json.dumps(meta)))
    print(f'junction at {J} for connect({", ".join(br)})')

for i, j, text in sorted(edits, reverse=True):
    src = src[:i] + text + src[j + 1:]
open(dyad_f, 'w').write(src)
print(f'{comp}: {len(edits)} junction(s)')
