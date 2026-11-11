#!/usr/bin/env python3
"""Re-route the wires of a `dyad layout solve` solution on its half-square grid.

Dyad 3.5.0's router places parallel wires on channel tracks in a fixed order, so
order-preserving bundles (feedback loops, jogs between offset blocks, branches)
come out crossed even when a crossing-free routing exists.  This keeps the
solver's component placements and replaces every route with one found by a
Dijkstra search that:

  * never runs a wire along another net's wire, through a component box, a
    foreign port, another net's bend/end, or an instance label;
  * charges for length, bends (BEND) and crossings (CROSS);
  * lets wires of the same net (connections sharing an output port) share track,
    so a second connection from a port branches off the first one;
  * routes connections shortest-first, with bundles ordered so that each later
    wire nests outside the earlier ones, and prefers vertical runs close to the
    source (so offset bundles jog without crossing).

usage: reroute.py PROB.json SOL.json OUT.json [--prefer top|bottom] [--first CONN,...]
       [--last CONN,...] [--via CONN@x,y[@x,y...]] [--box x0,y0,x1,y1] [--cross C]
       [--bend B] [--label-rows N] [--list-crossings]
CONN is "comp.port->comp.port" as in the connect(); coordinates are half-squares.
The output is a solution file `dyad layout apply` accepts unchanged.
"""
import argparse
import heapq
import json
import math

BEND = 3.0
CROSS = 30.0
EPS = 1e-3

ap = argparse.ArgumentParser()
ap.add_argument('prob')
ap.add_argument('sol')
ap.add_argument('out')
ap.add_argument('--prefer', choices=['top', 'bottom'], default=None,
                help='break ties between going over / under the blocks')
ap.add_argument('--first', default='', help='comma-separated "comp.port->comp.port" routed right after the straight wires, in order')
ap.add_argument('--last', default='', help='comma-separated "comp.port->comp.port" routed last, in order')
ap.add_argument('--cross', type=float, default=CROSS, help='cost of one crossing, in half-squares of wire')
ap.add_argument('--bend', type=float, default=BEND, help='cost of one bend, in half-squares of wire')
ap.add_argument('--via', action='append', default=[], help='"comp.port->comp.port@x,y[@x,y...]": route through these grid points')
ap.add_argument('--box', default='', help='x0,y0,x1,y1: keep every wire inside this half-square box')
ap.add_argument('--list-crossings', action='store_true', help='print every crossing point and the nets meeting there')
ap.add_argument('--label-rows', type=int, default=1, help='half-squares under each box kept free for its label')
a = ap.parse_args()
CROSS, BEND = a.cross, a.bend

prob = json.load(open(a.prob))
st = prob['structure']
solf = json.load(open(a.sol))
sol = solf['solution']
comps = {c['id']: c for c in st['components']}
place = {p['componentId']: p for p in sol['componentPlacements']}
for p in sol['componentPlacements']:
    assert p['d4State'] == 'identity', 'reroute.py assumes unrotated components'
    assert float(p['center']['x']).is_integer() or comps[p['componentId']]['width'] % 2, p


def box(cid):
    c, p = comps[cid], place[cid]['center']
    return (p['x'] - c['width'] / 2, p['y'] - c['height'] / 2, p['x'] + c['width'] / 2, p['y'] + c['height'] / 2)


def port(cid, pid):
    c, p = comps[cid], place[cid]['center']
    k = next(k for k in c['connectors'] if k['id'] == pid)
    hw, hh = c['width'] / 2, c['height'] / 2
    off = {'left': (-hw, k['position'] * hh), 'right': (hw, k['position'] * hh),
           'top': (k['position'] * hw, -hh), 'bottom': (k['position'] * hw, hh)}[k['edge']]
    x, y = p['x'] + off[0], p['y'] + off[1]
    assert abs(x - round(x)) < 1e-4 and abs(y - round(y)) < 1e-4, f'{cid}.{pid} is off the grid at ({x}, {y})'
    out = {'left': (-1, 0), 'right': (1, 0), 'top': (0, -1), 'bottom': (0, 1)}[k['edge']]
    return (int(round(x)), int(round(y))), out


boxes = {cid: box(cid) for cid in place}
X0 = int(min(b[0] for b in boxes.values())) - 12
Y0 = int(min(b[1] for b in boxes.values())) - 12
X1 = int(max(b[2] for b in boxes.values())) + 12
Y1 = int(max(b[3] for b in boxes.values())) + 12
if a.box:
    X0, Y0, X1, Y1 = (int(v) for v in a.box.split(','))

blocked = set()
for cid, (bx0, by0, bx1, by1) in boxes.items():
    for x in range(math.floor(bx0), math.ceil(bx1) + 1):
        for y in range(math.floor(by0), math.ceil(by1) + 1):
            blocked.add((x, y))
    # the instance label is drawn centred under the box
    w = bx1 - bx0
    lw = max(2.0, 0.45 * len(cid) * 36 / 50 * (1 if w >= 4 else 1))
    cx = (bx0 + bx1) / 2
    for x in range(math.floor(cx - lw / 2), math.ceil(cx + lw / 2) + 1):
        for dy in range(1, a.label_rows + 1):
            blocked.add((x, int(by1) + dy))

ports = {}
for cid in place:
    for k in comps[cid]['connectors']:
        ports[(cid, k['id'])] = port(cid, k['id'])
port_pts = {pt: key for key, (pt, _) in ports.items()}


def key(r):
    return (r['componentId'], r['connectorId'])


conns = []
for c in st['connections']:
    assert c['from']['type'] == 'component' and c['to']['type'] == 'component', 'canvas connectors unsupported'
    conns.append((c['id'], key(c['from']), key(c['to'])))

# a net is everything wired to the same output port
parent = {}


def find(x):
    while parent.setdefault(x, x) != x:
        x = parent[x]
    return x


for _, f, t in conns:
    parent[find(f)] = find(t)

edge_net = {}      # ((x,y),(x2,y2)) sorted -> net
pt_use = {}        # (x,y) -> {net: set('h'|'v'|'end'|'bend')}


def ekey(p, q):
    return (p, q) if p <= q else (q, p)


def name(cid_pid):
    return f'{cid_pid[0]}.{cid_pid[1]}'


DIRS = [(1, 0), (-1, 0), (0, 1), (0, -1)]


def search(net, sp, sdir, goal_pt, goal_dir, tp, sx, avoid, straight_out=True):
    """Dijkstra from (sp, moving sdir) to goal_pt (arriving with goal_dir, or any)."""
    start = (sp, sdir)
    dist = {start: 0.0}
    prev = {}
    pq = [(0.0, sp, sdir)]
    goal = None
    while pq:
        d, p, dr = heapq.heappop(pq)
        if dist.get((p, dr), 1e18) < d:
            continue
        if p == goal_pt and (goal_dir is None or dr == goal_dir):
            goal = (p, dr)
            break
        for nd in DIRS:
            if nd == (-dr[0], -dr[1]):
                continue
            if p == sp and straight_out and nd != sdir:
                continue          # leave the source port straight out
            q = (p[0] + nd[0], p[1] + nd[1])
            if not (X0 <= q[0] <= X1 and Y0 <= q[1] <= Y1):
                continue
            if q in avoid:
                continue
            if q == tp:
                if q != goal_pt or nd != goal_dir:
                    continue
            elif q in blocked:
                continue
            if q in port_pts and q != tp and q != sp:
                continue
            ek = ekey(p, q)
            own = edge_net.get(ek)
            if own is not None and own != net:
                continue
            uses = pt_use.get(q, {})
            axis = 'h' if nd[1] == 0 else 'v'
            step = 0.0 if own == net else 1.0
            cost = step
            foreign = {n: u for n, u in uses.items() if n != net}
            if foreign:
                if any(('end' in u) or ('bend' in u) for u in foreign.values()):
                    continue
                if any(axis in u for u in foreign.values()):
                    continue
                cost += CROSS
            if nd != dr:
                cost += BEND
                if p in pt_use and any(n != net for n in pt_use[p]):
                    continue      # never turn on top of another net
            if axis == 'v' and own != net:
                cost += EPS * abs(q[0] - sx)
            if axis == 'h' and own != net and a.prefer:
                cost += EPS * 0.1 * (q[1] if a.prefer == 'top' else -q[1])
            nd_ = d + cost
            if nd_ < dist.get((q, nd), 1e18):
                dist[(q, nd)] = nd_
                prev[(q, nd)] = (p, dr)
                heapq.heappush(pq, (nd_, q, nd))
    if goal is None:
        return None, None, None
    path = [goal[0]]
    st_ = goal
    while st_ != start:
        st_ = prev[st_]
        path.append(st_[0])
    path.reverse()
    return path, goal[1], dist[goal]


def route(cid, f, t):
    net = find(f)
    (sp, sdir), (tp, tdir) = ports[f], ports[t]
    want_in = (-tdir[0], -tdir[1])   # arrive moving into the target box
    legs = vias.get(label(f, t), []) + [tp]
    path, cur, dr, total = [sp], sp, sdir, 0.0
    for i, g in enumerate(legs):
        last_leg = i == len(legs) - 1
        avoid = set(path[:-1])        # a later leg may not run back over an earlier one
        seg, dr, c = search(net, cur, dr, g, want_in if last_leg else None, tp, sp[0], avoid, straight_out=(i == 0))
        if seg is None:
            raise SystemExit(f'no route for {name(f)} -> {name(t)}' + (f' from {cur}' if i else '') + ('' if last_leg else f' to via {g}'))
        path += seg[1:]
        cur, total = g, total + c
    # record usage
    for i in range(len(path) - 1):
        edge_net[ekey(path[i], path[i + 1])] = net
    for i, p in enumerate(path):
        u = pt_use.setdefault(p, {}).setdefault(net, set())
        if i == 0 or i == len(path) - 1:
            u.add('end')
            continue
        d0 = (p[0] - path[i - 1][0], p[1] - path[i - 1][1])
        d1 = (path[i + 1][0] - p[0], path[i + 1][1] - p[1])
        if d0 != d1:
            u.add('bend')
        u.add('h' if d0[1] == 0 else 'v')
        u.add('h' if d1[1] == 0 else 'v')
    # compress to corners
    pts = [path[0]]
    for i in range(1, len(path) - 1):
        d0 = (path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1])
        d1 = (path[i + 1][0] - path[i][0], path[i + 1][1] - path[i][1])
        if d0 != d1:
            pts.append(path[i])
    pts.append(path[-1])
    return pts, total


# reserve every connected port's stub (the first half-square out of the box) for
# its net, so no earlier wire runs across the front of a port wired later
for _, f, t in conns:
    for end in (f, t):
        (p, d) = ports[end]
        q = (p[0] + d[0], p[1] + d[1])
        net = find(end)
        edge_net[ekey(p, q)] = net
        pt_use.setdefault(p, {}).setdefault(net, set()).add('end')
        pt_use.setdefault(q, {}).setdefault(net, set()).add('h' if d[1] == 0 else 'v')


def L1(f, t):
    (p, _), (q, _) = ports[f], ports[t]
    return abs(p[0] - q[0]) + abs(p[1] - q[1])


def label(f, t):
    return f'{name(f)}->{name(t)}'


first = [s for s in a.first.split(',') if s]
vias = {}
for v in a.via:
    lab, *pts = v.split('@')
    vias[lab] = [tuple(int(c) for c in p.split(',')) for p in pts]
last = [s for s in a.last.split(',') if s]


def order_key(c):
    cid, f, t = c
    lab = label(f, t)
    (p, _), (q, _) = ports[f], ports[t]
    forward = q[0] > p[0]
    if forward and p[1] == q[1]:
        return (0, L1(f, t), p[1])      # straight wires first
    if lab in first:
        return (1, first.index(lab), 0)
    if lab in last:
        return (3, last.index(lab), 0)
    # forward wires jogging up are routed top wire first, jogging down bottom
    # wire first (each then takes the free vertical track nearest its source, so
    # the bundle staircases without crossings); backward (feedback) wires go
    # shortest first so each later one nests outside the earlier ones
    if forward:
        return (2, 0, p[1]) if q[1] < p[1] else (2, 1, -p[1])
    return (2, 2, L1(f, t))


for lab in first + last + list(vias):
    assert any(label(f, t) == lab for _, f, t in conns), f'unknown connection {lab}'

routes = {}
total = 0.0
for cid, f, t in sorted(conns, key=order_key):
    pts, cost = route(cid, f, t)
    routes[cid] = pts
    total += cost

# crossings report
cross = 0
for p, uses in pt_use.items():
    nets = [n for n, u in uses.items() if 'h' in u or 'v' in u]
    if len(nets) > 1:
        cross += len(nets) - 1
        if a.list_crossings:
            print('  crossing at', p, ' x '.join(name(n) for n in nets))
for r in sol['routedConnections']:
    r['waypoints'] = [{'x': x, 'y': y} for x, y in routes[r['connectionId']]]
    r.pop('usedFallback', None)
length = sum(abs(p[0] - q[0]) + abs(p[1] - q[1]) for pts in routes.values() for p, q in zip(pts, pts[1:]))
turns = sum(len(pts) - 2 for pts in routes.values())
obj = sol['objective']
obj.update({'crossings': cross, 'totalLength': length, 'turns': turns})
obj.pop('illegalRoutes', None)   # every route above is legal by construction
obj['reroutedBy'] = 'reroute.py'
json.dump(solf, open(a.out, 'w'), indent=1)
print(f'rerouted {len(routes)} connections; crossings {cross}; cost {total:.1f}')
