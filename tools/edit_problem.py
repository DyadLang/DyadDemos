#!/usr/bin/env python3
"""Edit a dyad-layout/problem@1 file's settings/hints/constraints (never `structure`).

usage: edit_problem.py IN OUT [ops...]
ops:
  lock-orientation[=TIER]     orientation=identity for every real component (default tier required)
  keep-orientation[=TIER]     orientation = the component's current seed state
  pin-seed[=TIER]             pin every real component at its extracted (current) position
  unpin-ports                 drop the extracted `pin:<port>` locks on boundary connectors
  port-edges[=TIER]           portEdge by declared direction: input->left, output->right, none->(keep or top)
  opt:KEY=JSON                settings.options[KEY] = JSON  (e.g. opt:routingRefinement=1, opt:seedFromCurrent=false)
  grid:COLSxROWS              settings.gridColumns/gridRows
  imp:ID=X                    hints.components[ID].importance = X
  cimp:CONNID=X               hints.connections[CONNID].importance = X
  edge:PORT=left|right|top|bottom   hints.canvasConnectors[PORT].preferredEdge
  add:JSON                    append a constraint ({"id","kind":{...},"strength":{...}}); strength defaults to strong/1
  drop:ID                     remove constraint ID
"""
import json, sys
src, dst, *ops = sys.argv[1:]
p = json.load(open(src))
st = p['structure']
real = [c['id'] for c in st['components'] if not c['id'].startswith('__junction_')]
C = p['constraints']
def strength(t): return {'tier': t or 'required', 'weight': 1}
def put(cid, kind, tier):
    C[:] = [c for c in C if c['id'] != cid]
    C.append({'id': cid, 'kind': kind, 'strength': strength(tier)})
for op in ops:
    name, _, arg = op.partition('=') if not op.startswith(('opt:', 'add:', 'imp:', 'cimp:', 'edge:', 'drop:', 'grid:')) else (op.split(':', 1)[0], None, op.split(':', 1)[1])
    if name == 'lock-orientation':
        for i in real: put(f'orientation:{i}', {'kind': 'orientation', 'componentId': i, 'd4': 'identity'}, arg)
    elif name == 'keep-orientation':
        for i in real:
            d = p['hints']['components'].get(i, {}).get('initialD4State', 'identity')
            put(f'orientation:{i}', {'kind': 'orientation', 'componentId': i, 'd4': d}, arg)
    elif name == 'pin-seed':
        for i in real:
            pos = p['hints']['components'].get(i, {}).get('initialPosition')
            if pos: put(f'pin:{i}', {'kind': 'pin', 'componentId': i, 'at': pos}, arg)
    elif name == 'unpin-ports':
        ports = {k['id'] for k in st['canvasConnectors']}
        C[:] = [c for c in C if not (c['kind']['kind'] == 'pin' and c['kind']['componentId'] in ports)]
    elif name == 'port-edges':
        for k in st['canvasConnectors']:
            e = {'input': 'left', 'output': 'right'}.get(k['direction'])
            if e: put(f'portEdge:{k["id"]}', {'kind': 'portEdge', 'connectorId': k['id'], 'edge': e}, arg or 'strong')
    elif name == 'opt':
        k, v = arg.split('=', 1); p['settings']['options'][k] = json.loads(v)
    elif name == 'grid':
        a, b = arg.split('x'); p['settings']['gridColumns'], p['settings']['gridRows'] = int(a), int(b)
    elif name == 'imp':
        k, v = arg.split('='); p['hints']['components'].setdefault(k, {})['importance'] = float(v)
    elif name == 'cimp':
        k, v = arg.split('='); p['hints']['connections'].setdefault(k, {})['importance'] = float(v)
    elif name == 'edge':
        k, v = arg.split('='); p['hints']['canvasConnectors'].setdefault(k, {})['preferredEdge'] = v
    elif name == 'add':
        c = json.loads(arg); c.setdefault('strength', {'tier': 'strong', 'weight': 1}); put(c['id'], c['kind'], None); C[-1]['strength'] = c['strength']
    elif name == 'drop':
        C[:] = [c for c in C if c['id'] != arg]
    else:
        sys.exit(f'unknown op {op}')
json.dump(p, open(dst, 'w'), indent=1)
