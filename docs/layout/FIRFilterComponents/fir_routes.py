#!/usr/bin/env python3
"""Replace the routes of the FIRFilter solution with hand-drawn orthogonal ones (placements unchanged)."""
import json, sys
src, dst = sys.argv[1:]
f = json.load(open(src))
R = {
 '__conn_0':   [(0, 3), (3, 3)],
 '__conn_12':  [(0, 3), (1, 3), (1, 8), (2, 8)],
 '__conn_1_0': [(6, 8), (5.5, 8), (5.5, 3)],
 '__conn_1_1': [(7, 3), (5.5, 3)],
 '__conn_1_2': [(5, 3), (5.5, 3)],
 '__conn_2':   [(9, 3), (11, 3)],
 '__conn_3_0': [(14, 8), (13.5, 8), (13.5, 3)],
 '__conn_3_1': [(13, 3), (13.5, 3)],
 '__conn_3_2': [(15, 3), (13.5, 3)],
 '__conn_4':   [(17, 3), (17.5, 3), (17.5, 8), (18, 8)],
 '__conn_5':   [(8, 8), (8.5, 8), (8.5, 12.4), (9, 12.4)],
 '__conn_6':   [(4, 8), (4.5, 8), (4.5, 13.6), (9, 13.6)],
 '__conn_7':   [(11, 13), (12, 13), (12, 13.6), (17, 13.6)],
 '__conn_8':   [(16, 8), (16.5, 8), (16.5, 12.4), (17, 12.4)],
 '__conn_9':   [(20, 8), (20.5, 8), (20.5, 12.4), (21, 12.4)],
 '__conn_10':  [(19, 13), (19.5, 13), (19.5, 13.6), (21, 13.6)],
 '__conn_11':  [(23, 13), (25, 13)],
}
J = {'__junction_1': (5.5, 3), '__junction_3': (13.5, 3)}
rc = f['solution']['routedConnections']
assert {r['connectionId'] for r in rc} == set(R), {r['connectionId'] for r in rc} ^ set(R)
for r in rc:
    old = r['waypoints']
    assert (old[0]['x'], old[0]['y']) == R[r['connectionId']][0], r
    r['waypoints'] = [{'x': x, 'y': y} for x, y in R[r['connectionId']]]
for c in f['solution']['componentPlacements']:
    if c['componentId'] in J: c['center'] = {'x': J[c['componentId']][0], 'y': J[c['componentId']][1]}
json.dump(f, open(dst, 'w'), indent=1)
