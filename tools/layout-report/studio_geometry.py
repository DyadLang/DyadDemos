#!/usr/bin/env python3
"""Check layout-report's model of Studio's drawing against what Dyad Studio actually drew.

Reads DOM dumps of Studio's diagram view (studio_dom_dump.js, run in dyad-ui-shot's page) and the
`dyad render` SVGs of the same diagrams, and reports where layout_report.parse_svg's geometry (icon
bodies, connector glyphs, labels) differs from Studio's by more than --tol units:

    python3 studio_geometry.py --dom DOMDIR --svg SVGDIR --lib HL20Demo

DOMDIR holds <diagram>.dom.json, SVGDIR the renders as <diagram>.svg (a layout-report cache/
directory). --fixture FILE writes the compact Studio geometry the unit tests compare with.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout_report as lr  # noqa: E402

SHAPES = ("polygon", "path", "rect", "circle", "polyline", "ellipse", "image", "text", "line")


def studio(path):
    """Studio's geometry in diagram units: component frames and icon ink, connector glyph ink, labels, wires."""
    with open(path) as f:
        d = json.load(f)
    nodes = d["nodes"]
    kids = {}
    for n in nodes:
        kids.setdefault(n["parent"], []).append(n)

    def desc(n):
        out, st = [], [n]
        while st:
            for k in kids.get(st.pop()["id"], []):
                out.append(k)
                st.append(k)
        return out

    # px -> diagram units, fitted on the unturned components' placement boxes
    xs, ys = [], []
    for n in kids.get(-1, []):
        a = n["attrs"]
        if n["tag"] == "dyad-component" and a.get("rotate", "0") == "0" and "connectors-only" not in a.get("class", ""):
            x1, x2, y1, y2 = (float(a[k]) for k in ("x1", "x2", "y1", "y2"))
            r = n["r"]
            xs += [(min(x1, x2), r[0]), (max(x1, x2), r[0] + r[2])]
            ys += [(min(y1, y2), r[1]), (max(y1, y2), r[1] + r[3])]

    def fit(pairs):
        mu = sum(p[0] for p in pairs) / len(pairs)
        mp = sum(p[1] for p in pairs) / len(pairs)
        s = sum((p[0] - mu) * (p[1] - mp) for p in pairs) / sum((p[0] - mu) ** 2 for p in pairs)
        return s, mp - s * mu

    if len(xs) < 4:
        raise SystemExit(f"{path}: needs at least two unturned blocks to find the scale")
    (sx, ox), (sy, oy) = fit(xs), fit(ys)
    unit = lambda r: ((r[0] - ox) / sx, (r[1] - oy) / sy, (r[0] + r[2] - ox) / sx, (r[1] + r[3] - oy) / sy)

    def ink(n):
        bs = [unit(k["r"]) for k in desc(n) if k["tag"] in SHAPES and k["vis"] and k["r"][2] + k["r"][3] > 0]
        return (min(b[0] for b in bs), min(b[1] for b in bs), max(b[2] for b in bs), max(b[3] for b in bs)) if bs else None

    g = {"bodies": {}, "glyphs": [], "labels": [], "wires": []}
    for n in kids.get(-1, []):
        a = n["attrs"]
        if n["tag"] == "dyad-component" and "connectors-only" not in a.get("class", ""):
            icon = next((k for k in desc(n) if k["tag"] == "dyad-icon"), None)
            if icon is not None and ink(icon):
                g["bodies"][a.get("data-id")] = ink(icon)
        elif n["tag"] == "dyad-component":  # the connectors-only copy holds the block's glyphs
            for c in kids.get(n["id"], []):
                if c["tag"] == "dyad-connector" and ink(c):
                    g["glyphs"].append(ink(c))
        elif n["tag"] == "dyad-connector" and ink(n):
            g["glyphs"].append(ink(next((k for k in desc(n) if k["tag"] == "dyad-icon"), n)))
        elif n["tag"] == "dyad-connection":
            for k in desc(n):
                if k["tag"] == "use" and k["attrs"].get("class") == "edge" and k.get("ctm"):
                    svg = nodes[nodes[k["parent"]]["parent"]]
                    path = next((q for q in desc(svg) if q["tag"] == "path" and q["attrs"].get("id") == "edgePath"), None)
                    if path:
                        a_, b_, c_, d_, e_, f_ = k["ctm"]
                        v = [float(t) for t in re.findall(r"-?[\d.]+(?:e[-+]?\d+)?", path["attrs"]["d"])]
                        g["wires"].append([((a_ * x + c_ * y + e_ - ox) / sx, (b_ * x + d_ * y + f_ - oy) / sy) for x, y in zip(v[::2], v[1::2])])
        if n["tag"] in ("dyad-component", "dyad-connector") and "connectors-only" not in a.get("class", ""):
            for k in desc(n):
                if k["tag"] == "dyad-label":
                    g["labels"].append((k["attrs"].get("content"), unit(k["r"])))
    return g


def compare(st, dg, tol):
    """Differences between Studio's geometry and the model's, as messages."""
    close = lambda a, b: max(abs(u - v) for u, v in zip(a, b)) <= tol
    centre = lambda b: ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)
    out = []
    bodies = {b.name: b.body for b in dg.blocks if not b.is_port}
    for name, ink in st["bodies"].items():
        if name not in bodies:
            out.append(f"block {name}: not in the render")
        elif not close(bodies[name], ink):
            out.append(f"block {name}: icon drawn at {fmt(ink)}, modelled at {fmt(bodies[name])}")
    glyphs = [g.box for g in dg.glyphs]
    for ink in st["glyphs"]:
        if not any(close(g, ink) for g in glyphs):
            out.append(f"glyph drawn at {fmt(ink)}: no modelled glyph there")
    if len(glyphs) != len(st["glyphs"]):
        out.append(f"{len(st['glyphs'])} glyphs drawn, {len(glyphs)} modelled")
    labels = [(t, bb) for b in dg.blocks for t, bb in b.labels]
    for text, box in st["labels"]:
        if not any(t == text and close(centre(bb), centre(box)) for t, bb in labels):
            out.append(f"label {text!r} drawn at {fmt(box)}: not modelled there")
    return out


def fmt(b):
    return "(" + ", ".join(f"{v:.1f}" for v in b) + ")"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dom", required=True, help="directory of <diagram>.dom.json dumps")
    ap.add_argument("--svg", required=True, help="directory of <diagram>.svg renders")
    ap.add_argument("--lib", help="the Dyad library, for instance and boundary-port names")
    ap.add_argument("--tol", type=float, default=1.0, help="allowed difference in diagram units (default 1)")
    ap.add_argument("--fixture", help="write the compact Studio geometry of every diagram to this JSON file")
    args = ap.parse_args(argv)
    comps = {}
    if args.lib:
        lib = lr.library_name(args.lib)
        comps = {c.qualified(lib): c for c in lr.find_components(args.lib)}
    bad, fixture = 0, {}
    for fn in sorted(os.listdir(args.dom)):
        if not fn.endswith(".dom.json"):
            continue
        q = fn[: -len(".dom.json")].removesuffix(".png")
        svg = os.path.join(args.svg, q + ".svg")
        if not os.path.exists(svg):
            print(f"{q}: no render in {args.svg}")
            continue
        st = studio(os.path.join(args.dom, fn))
        sc = comps.get(q)
        with open(svg) as f:
            dg = lr.parse_svg(f.read(), lr.instance_boxes(sc.block) if sc else None)
        diffs = compare(st, dg, args.tol)
        bad += bool(diffs)
        print(f"{q}: " + ("matches Studio" if not diffs else f"{len(diffs)} differences"))
        for d in diffs[:10]:
            print("   ", d)
        r = lambda b: [round(v, 1) for v in b]
        fixture[q] = {"bodies": {k: r(v) for k, v in st["bodies"].items()}, "glyphs": [r(v) for v in st["glyphs"]],
                      "labels": [[t, r(v)] for t, v in st["labels"]]}
    if args.fixture:
        with open(args.fixture, "w") as f:
            json.dump(fixture, f, indent=0, sort_keys=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
