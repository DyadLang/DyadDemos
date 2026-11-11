#!/usr/bin/env python3
"""Hand-tweak the PowerSplitHybrid solution: drop 0.25 jogs on the left feedback entries
and push the two bottom feedback runs one half-square lower so they clear the mg2/battery labels."""
import json, sys
src, dst = sys.argv[1:]
f = json.load(open(src)); rc = {r['connectionId']: r for r in f['solution']['routedConnections']}
P = lambda *pts: [{'x': x, 'y': y} for x, y in pts]
w3 = rc['__conn_3']['waypoints']; assert (w3[3]['x'], w3[3]['y']) == (10.5, 4)
rc['__conn_3']['waypoints'] = w3[:4] + P((10.5, 12.25), (11, 12.25))
w1 = rc['__conn_1']['waypoints']
rc['__conn_1']['waypoints'] = P((37, 13.25), (37.25, 13.25), (37.25, 24), (10.5, 24), (10.5, 14.25), (11, 14.25))
w2 = rc['__conn_2']['waypoints']
rc['__conn_2']['waypoints'] = P((30, 20.25), (30.25, 20.25), (30.25, 23.75), (10.75, 23.75), (10.75, 15.25), (11, 15.25))
json.dump(f, open(dst, 'w'), indent=1)
