#!/usr/bin/env python3
"""Count wire-segment crossings in a .dyad component's emitted connect routes.

Parses connect(...) { "Dyad": {"edges": [...], "junctions": [...] } } blocks.
Each edge {S,M,E} is a polyline; S/E>0 = arg index pin, S/E=-k = junction k.
Pins are resolved via laygen Ctx (boundary ports = diagram box centre).

Usage: xcheck.py <file.dyad> <Component> [--verbose]
Exits non-zero when crossings, overlaps or diagonal segments are found.
"""
import json
import os
import re
import sys
import laygen as lg

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, "..", "HL20Demo", "dyad")


def edge_points(conn, args_xy, junctions):
    out = []
    for e in conn["edges"]:
        def ref(idx):
            return args_xy[idx - 1] if idx > 0 else junctions[-idx - 1]
        pts = [ref(e["S"])]
        pts += [(m["x"], m["y"]) for m in e["M"]]
        pts.append(ref(e["E"]))
        out.append(pts)
    return out


def seg_of(poly):
    return [(poly[i], poly[i + 1]) for i in range(len(poly) - 1)
            if poly[i] != poly[i + 1]]


def orth(s):
    (x1, y1), (x2, y2) = s
    return 'h' if y1 == y2 else ('v' if x1 == x2 else 'd')


def cross(s1, s2):
    (a, b), (c, d) = s1, s2
    o1, o2 = orth(s1), orth(s2)
    if o1 == 'd' or o2 == 'd':
        return None  # diagonal segments are counted once each, elsewhere
    if o1 == o2:
        if o1 == 'h' and a[1] == c[1]:
            lo1, hi1 = sorted([a[0], b[0]]); lo2, hi2 = sorted([c[0], d[0]])
            if min(hi1, hi2) - max(lo1, lo2) > 1e-6:
                return ('overlap', (max(lo1, lo2), a[1]))
        if o1 == 'v' and a[0] == c[0]:
            lo1, hi1 = sorted([a[1], b[1]]); lo2, hi2 = sorted([c[1], d[1]])
            if min(hi1, hi2) - max(lo1, lo2) > 1e-6:
                return ('overlap', (a[0], max(lo1, lo2)))
        return None
    (p1, p2), (p3, p4) = s1, s2
    if o1 == 'v':
        (p1, p2), (p3, p4) = s2, s1
    py = p1[1]; px = p3[0]
    x1, x2 = sorted([p1[0], p2[0]]); y1, y2 = sorted([p3[1], p4[1]])
    if x1 < px < x2 and y1 < py < y2:
        return ('cross', (px, py))
    return None


def check(comp, ctx, verbose=True):
    nets = []
    for c in comp.connects:
        if c["kind"] != "connect":
            continue
        args = c["args"]
        try:
            axy = [ctx.pin(a) for a in args]
        except KeyError as ex:
            print("  !! unresolved pin", ex, "in", args)
            continue
        raw = c.get("emitted") or c["raw"]
        m = re.search(r'"Dyad"\s*:\s*({.*})\s*}\s*$', raw, re.S)
        if not m:
            continue
        try:
            dy = json.loads(m.group(1))
        except Exception:
            mm = re.search(r'"edges"\s*:\s*(\[.*?\])\s*[,}]', raw, re.S)
            dy = {"edges": json.loads(mm.group(1)), "junctions": []}
        jn = [(j["x"], j["y"]) for j in dy.get("junctions", [])]
        polys = edge_points(dy, axy, jn)
        nets.append((args, [s for p in polys for s in seg_of(p)]))
    # diagonal segments are layout defects in their own right: count each
    # distinct diagonal once, not once per segment pair it touches.
    diags = []
    for args, segs in nets:
        for s in segs:
            if orth(s) == 'd':
                diags.append((s, args))
    bad = []
    for i in range(len(nets)):
        for j in range(i + 1, len(nets)):
            a1, s1 = nets[i]; a2, s2 = nets[j]
            for x in s1:
                for y in s2:
                    r = cross(x, y)
                    if r:
                        bad.append((r, a1, a2))
    ov = [b for b in bad if b[0][0] == 'overlap']
    cr = [b for b in bad if b[0][0] == 'cross']
    if verbose:
        print(f"{comp.name}: crossings={len(cr)} overlaps={len(ov)} diagonals={len(diags)}")
        for (k, pt), a1, a2 in cr:
            print(f"   X {a1}  x  {a2}  @ {pt}")
        for (k, pt), a1, a2 in ov:
            print(f"   O {a1}  x  {a2}  @ {pt}")
        for s, a1 in diags:
            print(f"   D {a1}  seg {s}")
    return cr, ov, diags


def main(argv):
    verbose = "--verbose" in argv or "-v" in argv
    argv = [a for a in argv if a not in ("--verbose", "-v")]
    if len(argv) != 2:
        print("usage: xcheck.py <file.dyad> <Component> [--verbose]",
              file=sys.stderr)
        return 2
    path, comp = argv
    segs = lg.load_file(path)
    c = next((s for s in segs
              if isinstance(s, lg.Component) and s.name == comp), None)
    if c is None:
        print(f"component {comp} not found in {path}", file=sys.stderr)
        return 2
    ctx = lg.Ctx(c, lg.library_pins(LIB))
    cr, ov, diags = check(c, ctx, verbose=verbose)
    if not verbose:
        print(f"{c.name}: crossings={len(cr)} overlaps={len(ov)} "
              f"diagonals={len(diags)}")
    return 1 if (cr or ov or diags) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
