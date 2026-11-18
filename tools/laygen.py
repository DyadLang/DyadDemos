#!/usr/bin/env python3
"""laygen.py - Dyad .dyad diagram layout toolkit.

Parses a .dyad source file into components (declarations + connects), lets a
generator script rewrite connector/instance placements and re-emit every
connect() with fresh orthogonal routes, then splices the result back.

Coordinates: diagram space, y grows downward, icon space is 0..1000 mapped
onto the instance/placement box.

Wire model (verified against rendered SVG):
  edge {"S": s, "M": [midpoints], "E": e}; s/e > 0 = connect arg index (1
  based), s/e = -k = junctions[k-1].  Polyline = S-point -> M... -> E-point.
  Boundary port pin = centre of its diagram placement box.
  Instance pin = centre of the connector's icon placement box mapped onto the
  instance's diagram box (with optional D4 "rot").
"""

import json
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------- parsing

def _scan_block(text, start):
    """Return index just past the end of the brace-balanced block starting at
    the '{' at text[start]."""
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced braces")


def _split_decls(region):
    """Split a component declaration region into chunks: each chunk is the
    docstring + decl + optional trailing {json}.  Brace depth tracking keeps
    multi-line metadata together."""
    chunks = []
    cur = ""
    depth = 0
    for line in region.split("\n"):
        cur += line + "\n"
        depth += line.count("{") - line.count("}")
        if depth == 0 and line.strip() and not line.strip().startswith('"'):
            chunks.append(cur)
            cur = ""
        elif depth == 0 and re.match(r'^\s*\w+\s*=', line):
            chunks.append(cur)
            cur = ""
    if cur.strip():
        chunks.append(cur)
    return chunks


def _parse_decl(chunk):
    """Parse one decl chunk -> dict."""
    m = re.search(r'(\w+)\s*=\s*([\w.]+)\s*\(', chunk)
    if not m:
        pm = re.search(r'parameter\s+(\w+)', chunk)
        return {"raw": chunk, "kind": "param", "name": pm.group(1) if pm else "?"}
    d = {"raw": chunk, "kind": "decl", "name": m.group(1), "type": m.group(2)}
    pl = re.search(r'"placement"\s*:\s*{', chunk)
    if pl:
        bs = pl.end() - 1
        blk = chunk[bs:_scan_block(chunk, bs)]
        d["placement"] = json.loads(blk)
        # find the placement block's span for editing
        d["_pl_span"] = (bs, _scan_block(chunk, bs))
    if re.search(r'=\s*RealInput\s*\(', chunk):
        d["dir"] = "in"
    elif re.search(r'=\s*RealOutput\s*\(', chunk):
        d["dir"] = "out"
    return d


def _split_connects(region):
    chunks = []
    cur = ""
    depth = 0
    for line in region.split("\n"):
        cur += line + "\n"
        depth += line.count("{") - line.count("}")
        if depth == 0 and line.strip():
            if line.strip().startswith("connect") or chunks or cur.strip().startswith("connect"):
                chunks.append(cur)
                cur = ""
    if cur.strip():
        chunks.append(cur)
    return chunks


def _parse_connect(chunk):
    m = re.match(r'\s*connect\s*\((.*?)\)\s*', chunk, re.S)
    if not m:
        return {"raw": chunk, "kind": "other"}
    args = [a.strip() for a in m.group(1).split(",")]
    d = {"kind": "connect", "args": args, "raw": chunk}
    return d


class Component:
    def __init__(self, name, text):
        self.name = name
        m = re.match(r'(.*?\bcomponent\s+' + re.escape(name) + r'\s*\n)(.*)',
                     text, re.S)
        self.header = m.group(1)
        body = m.group(2)
        rel = re.search(r'^relations\s*$', body, re.M)
        meta = re.search(r'^metadata\b', body, re.M)
        self.decl_region = body[:rel.start()]
        end_m = re.search(r'^end\s*$', body, re.M)
        if meta:
            self.rel_region = body[rel.end():meta.start()]
            self.meta = body[meta.start():end_m.start()]
            if not self.meta.endswith("\n"):
                self.meta += "\n"
        else:
            self.rel_region = body[rel.end():end_m.start()]
            self.meta = ""
        self.decls = [_parse_decl(c) for c in _split_decls(self.decl_region)
                      if c.strip()]
        self.connects = [_parse_connect(c) for c in _split_connects(self.rel_region)
                         if c.strip()]

    # ----- decl helpers -----
    def decl(self, name):
        for d in self.decls:
            if d.get("name") == name:
                return d
        raise KeyError(self.name + "." + name)

    def set_icon(self, name, box):
        """Set connector icon placement box {x1,y1,x2,y2}."""
        d = self.decl(name)
        pl = d["placement"]
        pl["icon"] = box
        self._rewrite_placement(d)

    def set_diagram(self, name, box, rot=None):
        """Set diagram placement box {x1,x2,y1,y2} (+optional rot)."""
        d = self.decl(name)
        pl = d.setdefault("placement", {})
        dg = dict(box)
        if rot is not None:
            dg["rot"] = rot
        elif "rot" in d["placement"].get("diagram", {}):
            dg["rot"] = d["placement"]["diagram"]["rot"]
        pl["diagram"] = dg
        self._rewrite_placement(d)

    def _rewrite_placement(self, d):
        s, e = d["_pl_span"]
        new = json.dumps(d["placement"], separators=(", ", ": "))
        d["raw"] = d["raw"][:s] + new + d["raw"][e:]
        # re-find span (length changed)
        pl = re.search(r'"placement"\s*:\s*{', d["raw"])
        bs = pl.end() - 1
        d["_pl_span"] = (bs, _scan_block(d["raw"], bs))

    def add_decl(self, raw, before=None):
        """Insert a raw decl chunk (must end with newline)."""
        d = _parse_decl(raw)
        if before:
            for i, o in enumerate(self.decls):
                if o.get("name") == before:
                    self.decls.insert(i, d)
                    return
        self.decls.append(d)

    # ----- emission -----
    def emit_connect(self, args, edges, junctions=(), indent="  "):
        """edges: list of (s, [midpoints], e)."""
        ed = [{"S": s, "M": [{"x": _f(x), "y": _f(y)} for x, y in m], "E": e}
              for s, m, e in edges]
        dd = {"edges": ed, "path": {}}
        if junctions:
            dd["junctions"] = [{"x": _f(x), "y": _f(y)} for x, y in junctions]
        argstr = ", ".join(args)
        return (indent + "connect(" + argstr + ") { \"Dyad\": " +
                json.dumps(dd, separators=(", ", ": ")) + " }\n")

    def render(self):
        out = [self.header]
        for d in self.decls:
            out.append(d["raw"])
        out.append("relations\n")
        for c in self.connects:
            if c["kind"] == "connect" and c.get("emitted"):
                out.append(c["emitted"])
            else:
                out.append(c["raw"].lstrip("\n"))
        if self.meta:
            out.append(self.meta)
        out.append("end\n")
        return "".join(out)


def _f(v):
    f = round(float(v), 4)
    return int(f) if f == int(f) else f


def load_file(path):
    """-> list of segments; components become Component objects, the rest raw.

    A component block runs from its 'component NAME' line (plus an optional
    immediately preceding \"\"\" docstring \"\"\") to the next '^end$' line.
    """
    text = Path(path).read_text()
    lines = text.split("\n")
    # find block starts/ends by line scan (components do not nest)
    segs = []
    pos = 0  # char offset of first unconsumed char
    off = 0
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        m = re.match(r'^(test\s+)?component\s+(\w+)\s*$', line)
        if not m:
            off += len(line) + 1
            i += 1
            continue
        name = m.group(2)
        start = off
        # attach an immediately preceding docstring: walk back over blank
        # lines, then over a \"\"\"...\"\"\" block ending right above.
        j = i - 1
        while j >= 0 and not lines[j].strip():
            j -= 1
        if j >= 0 and lines[j].strip().endswith('"""'):
            if lines[j].count('"""') >= 2:
                k = j
            else:
                k = j - 1
                while k >= 0 and '"""' not in lines[k]:
                    k -= 1
            # k is first line containing the opening triple quote
            if k >= 0:
                start = off - sum(len(l) + 1 for l in lines[k:i])
        # find the closing 'end' line
        e = i + 1
        eoff = off + len(line) + 1
        while e < n:
            if lines[e].strip() == "end":
                break
            eoff += len(lines[e]) + 1
            e += 1
        if e == n:
            raise ValueError(f"no 'end' for component {name} in {path}")
        end = eoff + len("end")
        if pos < start:
            segs.append(text[pos:start])
        segs.append(Component(name, text[start:end] + "\n"))
        pos = end + 1 if end < len(text) else end
        # advance scanner past this component
        while i <= e:
            off += len(lines[i]) + 1
            i += 1
    segs.append(text[pos:])
    return segs


def save_file(path, segs):
    out = []
    for s in segs:
        out.append(s.render() if isinstance(s, Component) else s)
    Path(path).write_text("".join(out))


# ---------------------------------------------------------------- geometry

def box_center(box):
    return ((box["x1"] + box["x2"]) / 2.0, (box["y1"] + box["y2"]) / 2.0)


def icon_center(icon):
    return ((icon["x1"] + icon["x2"]) / 2.0, (icon["y1"] + icon["y2"]) / 2.0)


def pin_xy(diag_box, icon_place, rot=0):
    """Map an icon placement box centre onto the diagram box, applying rot
    (degrees clockwise, icon rotates inside its frame)."""
    cx, cy = icon_center(icon_place)  # 0..1000
    if rot == 90:
        cx, cy = cy, 1000 - cx
    elif rot == 180:
        cx, cy = 1000 - cx, 1000 - cy
    elif rot == 270:
        cx, cy = 1000 - cy, cx
    x = diag_box["x1"] + cx / 1000.0 * (diag_box["x2"] - diag_box["x1"])
    y = diag_box["y1"] + cy / 1000.0 * (diag_box["y2"] - diag_box["y1"])
    return (x, y)


# ---------------------------------------------------------------- library pin db

_LIB_CACHE = {}

def library_pins(libroot):
    """{component_name: {connector: icon_place}} for every local component."""
    if libroot in _LIB_CACHE:
        return _LIB_CACHE[libroot]
    pins = {}
    for f in Path(libroot).rglob("*.dyad"):
        for seg in load_file(f):
            if not isinstance(seg, Component):
                continue
            p = {}
            for d in seg.decls:
                if "placement" in d and "icon" in d.get("placement", {}):
                    p[d["name"]] = (d["placement"]["icon"], d.get("dir"))
            pins[seg.name] = p
    _LIB_CACHE[libroot] = pins
    return pins


# Std-lib block pin fractions measured from rendered diagrams (icon centres,
# 0..1000).  Extend as needed.
STDLIB_PINS = {
    "BlockComponents.Math.Product": {"u1": {"x1": -30, "y1": 150, "x2": 30, "y2": 250},
                                    "u2": {"x1": -30, "y1": 750, "x2": 30, "y2": 850},
                                    "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Math.Add3": {"u1": {"x1": -30, "y1": 100, "x2": 30, "y2": 200},
                                  "u2": {"x1": -30, "y1": 450, "x2": 30, "y2": 550},
                                  "u3": {"x1": -30, "y1": 800, "x2": 30, "y2": 900},
                                  "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Math.Add": {"u1": {"x1": -30, "y1": 150, "x2": 30, "y2": 250},
                                 "u2": {"x1": -30, "y1": 750, "x2": 30, "y2": 850},
                                 "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Continuous.Integrator": {
        "u": {"x1": -30, "y1": 450, "x2": 30, "y2": 550},
        "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Continuous.FirstOrder": {
        "u": {"x1": -30, "y1": 450, "x2": 30, "y2": 550},
        "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Nonlinear.Limiter": {
        "u": {"x1": -30, "y1": 450, "x2": 30, "y2": 550},
        "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Nonlinear.SlewRateLimiter": {
        "u": {"x1": -30, "y1": 450, "x2": 30, "y2": 550},
        "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Math.Abs": {
        "u": {"x1": -30, "y1": 450, "x2": 30, "y2": 550},
        "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "AdjustableUpperLimit": {
        "u1": {"x1": -30, "y1": 150, "x2": 30, "y2": 250},
        "u2": {"x1": -30, "y1": 750, "x2": 30, "y2": 850},
        "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Math.Gain": {"u": {"x1": -30, "y1": 450, "x2": 30, "y2": 550},
                                  "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Math.Sum": {},
    "BlockComponents.Sources.Constant": {
        "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
    "BlockComponents.Sources.Ramp": {
        "y": {"x1": 970, "y1": 450, "x2": 1030, "y2": 550}},
}


class Ctx:
    """Resolution context for one component being generated."""

    def __init__(self, comp, pins):
        self.comp = comp
        self.pins = pins  # library_pins() map

    def pin(self, endpoint):
        """endpoint like 'cl.alpha_deg' or 'alpha_deg' (boundary port).
        -> (x, y) pin point in diagram space."""
        parts = endpoint.split(".")
        d = self.comp.decl(parts[0])
        if len(parts) == 1:
            return box_center(d["placement"]["diagram"])
        inst = d
        sub = parts[1]
        typ = inst["type"].split(".")[-1]
        ic = self.pins.get(typ, {}).get(sub) or \
            STDLIB_PINS.get(inst["type"], {}).get(sub)
        if ic is None:
            raise KeyError(f"no icon pin for {inst['type']}.{sub}")
        icon = ic[0] if isinstance(ic, tuple) else ic
        rot = inst["placement"]["diagram"].get("rot", 0)
        return pin_xy(inst["placement"]["diagram"], icon, rot)


def hv(p1, p2):
    """L route horizontal-then-vertical midpoints."""
    return [(p2[0], p1[1])] if p1[0] != p2[0] and p1[1] != p2[1] else []


def vh(p1, p2):
    return [(p1[0], p2[1])] if p1[0] != p2[0] and p1[1] != p2[1] else []
