#!/usr/bin/env python3
"""layout-report: diagram-quality metrics for Dyad component diagrams.

Measures each diagram as Dyad draws it: the `dyad render` SVG gives the wires
with their real port endpoints, the block boxes and the labels. The `.dyad`
source gives the connect() statements and whether each one carries route
metadata. Optionally, `dyad layout extract` and dyad-layout's own WASM scorer
add the solver's verdict on the same geometry. See README.md.

Python 3.9+ standard library only. Node >= 18 is needed only for
--dyad-layout-wasm.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field

SVGNS = "{http://www.w3.org/2000/svg}"
HALF_SQUARE = 50.0  # Dyad units per dyad-layout half-square (DEFAULT_HALF_SQUARE_SIZE)
HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# geometry helpers


def mat_mul(a, b):
    """Compose affine matrices (a, b, c, d, e, f) as in SVG: a after b."""
    a1, b1, c1, d1, e1, f1 = a
    a2, b2, c2, d2, e2, f2 = b
    return (
        a1 * a2 + c1 * b2,
        b1 * a2 + d1 * b2,
        a1 * c2 + c1 * d2,
        b1 * c2 + d1 * d2,
        a1 * e2 + c1 * f2 + e1,
        b1 * e2 + d1 * f2 + f1,
    )


IDENT = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def translate(tx, ty):
    return (1.0, 0.0, 0.0, 1.0, tx, ty)


class UnsupportedSVG(ValueError):
    """The SVG uses a structure the parser does not model; measuring it would be wrong."""


TRANSFORM_ARGS = {"translate": (1, 2), "scale": (1, 2), "rotate": (1, 3), "matrix": (6,)}


def parse_transform(s: str | None):
    """An SVG transform list as one affine matrix: translate, scale, rotate and matrix.

    Anything else (skewX, skewY, malformed arguments) raises UnsupportedSVG
    rather than being dropped, which would silently misplace the geometry.
    """
    m = IDENT
    if not s or not s.strip():
        return m
    rest = re.sub(r"(\w+)\s*\(([^)]*)\)", "", s)
    if rest.strip(" \t\r\n,"):
        raise UnsupportedSVG(f"transform={s!r}: cannot parse {rest.strip()!r}")
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", s):
        if name not in TRANSFORM_ARGS:
            raise UnsupportedSVG(f"transform={s!r}: {name}() is not supported")
        try:
            v = [float(x) for x in re.split(r"[\s,]+", args.strip()) if x]
        except ValueError:
            raise UnsupportedSVG(f"transform={s!r}: bad {name}() arguments")
        if len(v) not in TRANSFORM_ARGS[name]:
            raise UnsupportedSVG(f"transform={s!r}: {name}() takes {' or '.join(map(str, TRANSFORM_ARGS[name]))} arguments")
        if name == "translate":
            t = translate(v[0], v[1] if len(v) > 1 else 0.0)
        elif name == "scale":
            sx = v[0]
            sy = v[1] if len(v) > 1 else sx
            t = (sx, 0.0, 0.0, sy, 0.0, 0.0)
        elif name == "rotate":
            a = math.radians(v[0])
            r = (math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0.0, 0.0)
            if len(v) == 3:
                r = mat_mul(translate(v[1], v[2]), mat_mul(r, translate(-v[1], -v[2])))
            t = r
        elif name == "matrix":
            t = tuple(v)
        m = mat_mul(m, t)
    return m


def apply(m, x, y):
    a, b, c, d, e, f = m
    return (a * x + c * y + e, b * x + d * y + f)


def map_box(m, x0, y0, x1, y1):
    pts = [apply(m, x, y) for x, y in ((x0, y0), (x1, y0), (x0, y1), (x1, y1))]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (min(xs), min(ys), max(xs), max(ys))


def box_overlap_area(a, b):
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    return w * h if w > 0 and h > 0 else 0.0


def shrink(b, d):
    return (b[0] + d, b[1] + d, b[2] - d, b[3] - d)


def seg_len(p, q):
    return math.hypot(q[0] - p[0], q[1] - p[1])


def clip_len_in_box(p, q, b):
    """Length of segment pq inside the open box b (Liang-Barsky)."""
    x0, y0 = p
    dx, dy = q[0] - x0, q[1] - y0
    t0, t1 = 0.0, 1.0
    for pk, qk in ((-dx, x0 - b[0]), (dx, b[2] - x0), (-dy, y0 - b[1]), (dy, b[3] - y0)):
        if abs(pk) < 1e-12:
            if qk <= 0:
                return 0.0
            continue
        r = qk / pk
        if pk < 0:
            t0 = max(t0, r)
        else:
            t1 = min(t1, r)
        if t0 >= t1:
            return 0.0
    return (t1 - t0) * math.hypot(dx, dy)


def _cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def seg_contact(p1, p2, p3, p4, tol=0.25):
    """Classify the contact of two segments.

    Returns ("cross", point) for a proper crossing, ("overlap", length) for a
    collinear overlap, ("touch", point) when an endpoint of one lies on the
    other, or None.
    """
    if (max(p1[0], p2[0]) < min(p3[0], p4[0]) - tol or max(p3[0], p4[0]) < min(p1[0], p2[0]) - tol
            or max(p1[1], p2[1]) < min(p3[1], p4[1]) - tol or max(p3[1], p4[1]) < min(p1[1], p2[1]) - tol):
        return None
    l1, l2 = seg_len(p1, p2), seg_len(p3, p4)
    if l1 < 1e-9 or l2 < 1e-9:
        return None
    d1 = _cross(p3, p4, p1) / l2
    d2 = _cross(p3, p4, p2) / l2
    d3 = _cross(p1, p2, p3) / l1
    d4 = _cross(p1, p2, p4) / l1
    if abs(d1) <= tol and abs(d2) <= tol:  # collinear
        ux, uy = (p2[0] - p1[0]) / l1, (p2[1] - p1[1]) / l1
        a0, a1 = 0.0, l1
        b0 = (p3[0] - p1[0]) * ux + (p3[1] - p1[1]) * uy
        b1 = (p4[0] - p1[0]) * ux + (p4[1] - p1[1]) * uy
        lo, hi = max(a0, min(b0, b1)), min(a1, max(b0, b1))
        if hi - lo > tol:
            return ("overlap", hi - lo)
        if hi - lo >= -tol:
            t = (lo + hi) / 2
            return ("touch", (p1[0] + ux * t, p1[1] + uy * t))
        return None
    if ((d1 > tol and d2 < -tol) or (d1 < -tol and d2 > tol)) and ((d3 > tol and d4 < -tol) or (d3 < -tol and d4 > tol)):
        # proper crossing
        den = (p1[0] - p2[0]) * (p3[1] - p4[1]) - (p1[1] - p2[1]) * (p3[0] - p4[0])
        if abs(den) < 1e-12:
            return None
        t = ((p1[0] - p3[0]) * (p3[1] - p4[1]) - (p1[1] - p3[1]) * (p3[0] - p4[0])) / den
        return ("cross", (p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1])))

    def on_seg(a, b, c, d):
        return abs(d) <= tol and min(a[0], b[0]) - tol <= c[0] <= max(a[0], b[0]) + tol and \
            min(a[1], b[1]) - tol <= c[1] <= max(a[1], b[1]) + tol

    for a, b, c, d in ((p3, p4, p1, d1), (p3, p4, p2, d2), (p1, p2, p3, d3), (p1, p2, p4, d4)):
        if on_seg(a, b, c, d):
            return ("touch", c)
    return None


def normalize_polyline(pts, tol=0.25):
    """Drop repeated vertices and vertices in the middle of a straight run.

    A waypoint that does not change direction draws nothing, so it must not
    change what the wire's contacts are classified as. Reversals (a run that
    doubles back on itself) are kept: they draw ink beyond the turn.
    """
    out = []
    for p in pts:
        p = (float(p[0]), float(p[1]))
        if out and seg_len(out[-1], p) <= 1e-9:
            continue
        out.append(p)
        while len(out) >= 3:
            a, b, c = out[-3], out[-2], out[-1]
            lac = seg_len(a, c)
            dot = (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1])
            if lac > 1e-9 and abs(_cross(a, c, b)) / lac <= tol and dot > 0:
                del out[-2]
            else:
                break
    return out


# ---------------------------------------------------------------------------
# library / source discovery

COMP_RE = re.compile(r"^((?:(?:test|example|partial|external)\s+)*)component\s+(\w+)\b", re.M)


def library_name(libdir):
    with open(os.path.join(libdir, "Project.toml")) as f:
        for line in f:
            m = re.match(r'\s*name\s*=\s*"([^"]+)"', line)
            if m:
                return m.group(1)
    raise SystemExit(f"no name in {libdir}/Project.toml")


@dataclass
class SourceComponent:
    name: str
    module: str  # dotted module path below dyad/, '' for the top
    file: str
    kind: str  # '', 'test', 'example'
    block: str

    def qualified(self, lib):
        return ".".join(x for x in (lib, self.module, self.name) if x)


def find_components(libdir):
    root = os.path.join(libdir, "dyad")
    out = []
    for dp, _dn, fns in os.walk(root):
        for fn in sorted(fns):
            if not fn.endswith(".dyad"):
                continue
            path = os.path.join(dp, fn)
            rel = os.path.relpath(dp, root)
            module = "" if rel == "." else rel.replace(os.sep, ".")
            with open(path, encoding="utf-8") as f:
                src = f.read()
            for m in COMP_RE.finditer(src):
                prefix = m.group(1).split()
                if "partial" in prefix or "external" in prefix:
                    continue
                endm = re.compile(r"^end\b", re.M).search(src, m.end())
                block = src[m.end(): endm.start() if endm else len(src)]
                if "connect(" not in block:
                    continue
                kind = "test" if "test" in prefix else ("example" if "example" in prefix else "")
                out.append(SourceComponent(m.group(2), module, path, kind, block))
    out.sort(key=lambda c: (c.module, c.name))
    return out


def connect_route_status(block):
    """(connect statements, those without route metadata, arms) from the source."""
    links = block[block.find('"_links"'):] if '"_links"' in block else ""
    total = missing = arms = looped = 0
    for mm in re.finditer(r"^([ \t]*)connect\(([^)]*)\)[ \t]*(\{\^(\w+)\})?", block, re.M):
        if len(mm.group(1).expandtabs(2)) > 2:
            looped += 1  # inside a for loop: no per-connection route metadata is possible
            continue
        total += 1
        nargs = len([a for a in mm.group(2).split(",") if a.strip()])
        arms += 1 if nargs <= 2 else nargs
        if mm.group(4):
            lm = re.search(r'"' + re.escape(mm.group(4)) + r'"\s*:\s*\{\s*"Dyad"', links)
            if lm:
                nxt = re.compile(r'"\w+"\s*:\s*\{\s*"Dyad"').search(links, lm.end())
                ok = '"edges"' in links[lm.end(): nxt.start() if nxt else len(links)]
            else:
                ok = False
        else:
            rest = block[mm.end(): mm.end() + 20000]
            nxt = rest.find("connect(")
            ok = rest.lstrip().startswith(("{", "[")) and '"edges"' in rest[: nxt if nxt >= 0 else len(rest)]
        if not ok:
            missing += 1
    return total, missing, arms, looped


def instance_boxes(block):
    """name -> (x1, y1, x2, y2) of each instance's diagram placement in the source (inline or via `{^link}`)."""
    return {n: bb for n, _t, bb in _placements(block, "diagram")}


TYPED_DECL_RE = re.compile(r"^\s{2}(\w+)\s*=\s*([A-Za-z_][\w.]*)\s*\(", re.M)
ANY_COMP_RE = re.compile(r"^(?:(?:test|example|partial|external)\s+)*component\s+(\w+)\b", re.M)


def _close_paren(text, i):
    """The index just past the ')' closing the '(' before text[i], skipping strings and comments;
    len(text) if it is never closed."""
    depth, q = 1, None
    while i < len(text):
        c = text[i]
        if q:
            if c == "\\":
                i += 1
            elif c == q:
                q = None
        elif c == '"':
            q = c
        elif c == "#":  # a comment, to the end of the line
            i = text.find("\n", i)
            if i < 0:
                return len(text)
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def _placements(block, key):
    """[(name, type, (x1, y1, x2, y2))] of the declarations in a component body with a `key` placement,
    inline or through a `{^link}` into the metadata's "_links"."""
    tail = re.search(r"^(?:relations|metadata)\b", block, re.M)
    decl_part = block[: tail.start()] if tail else block
    links = block[block.find('"_links"'):] if '"_links"' in block else ""
    decls = list(TYPED_DECL_RE.finditer(decl_part))
    out = []
    for i, d in enumerate(decls):
        seg = decl_part[d.end(): decls[i + 1].start() if i + 1 < len(decls) else len(decl_part)]
        m = re.search(r'"' + key + r'"\s*:\s*\{([^}]*)\}', seg)
        # the `{^link}` follows the constructor's closing parenthesis, however many lines its arguments take
        ref = re.match(r"\s*\{\^(\w+)\}", decl_part[_close_paren(decl_part, d.end()):])
        if not m and ref and links:
            m = re.search(r'"' + re.escape(ref.group(1)) + r'"\s*:\s*\{\s*"Dyad"\s*:\s*\{\s*"placement"\s*:\s*\{[^{}]*?(?:\{[^}]*\}[^{}]*?)*?"'
                          + key + r'"\s*:\s*\{([^}]*)\}', links)
        if not m:
            continue
        kv = dict(re.findall(r'"(x1|x2|y1|y2)"\s*:\s*(-?[\d.eE+-]+)', m.group(1)))
        try:
            x1, x2, y1, y2 = (float(kv[k]) for k in ("x1", "x2", "y1", "y2"))
        except (KeyError, ValueError):
            continue
        out.append((d.group(1), d.group(2), (min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))))
    return out


def connector_index(dirs):
    """Component name -> [(connector, its icon placement box)], from the .dyad files under `dirs`,
    with `extends` followed. Earlier directories win. Only used to name connector glyphs."""
    own, bases = {}, {}
    for root in dirs:
        for dp, _dn, fns in os.walk(root):
            for fn in sorted(fns):
                if not fn.endswith(".dyad"):
                    continue
                try:
                    with open(os.path.join(dp, fn), encoding="utf-8") as f:
                        src = f.read()
                except OSError:
                    continue
                for m in ANY_COMP_RE.finditer(src):
                    if m.group(1) in own:
                        continue
                    endm = re.compile(r"^end\b", re.M).search(src, m.end())
                    block = src[m.end(): endm.start() if endm else len(src)]
                    own[m.group(1)] = [(n, bb) for n, _t, bb in _placements(block, "icon")]
                    bases[m.group(1)] = [b.split(".")[-1] for b in re.findall(r"^\s{2}extends\s+([\w.]+)", block, re.M)]

    def resolve(name, seen=()):
        out = list(own.get(name, []))
        for b in bases.get(name, []):
            if b not in seen:
                out += resolve(b, seen + (name,))
        return out
    return {n: resolve(n) for n in own}


def package_dyad_dirs(libdir):
    """The dyad/ folders of the packages in the Julia depot (newest version of each), for connector names."""
    depots = [d for d in os.environ.get("JULIA_DEPOT_PATH", "").split(os.pathsep) if d] or [os.path.expanduser("~/.julia")]
    out = []
    for dep in depots:
        pk = os.path.join(dep, "packages")
        if not os.path.isdir(pk):
            continue
        for name in sorted(os.listdir(pk)):
            if not os.path.isdir(os.path.join(pk, name)):
                continue
            vers = [os.path.join(pk, name, v, "dyad") for v in os.listdir(os.path.join(pk, name))]
            vers = [v for v in vers if os.path.isdir(v)]
            if vers:
                out.append(max(vers, key=os.path.getmtime))
    return out


_PKG_INDEX = {}


def instance_connectors(libdir, block):
    """Instance name -> [(connector, icon placement box)] for the instances declared in a component body."""
    key = os.path.abspath(libdir)
    if key not in _PKG_INDEX:
        _PKG_INDEX[key] = connector_index([os.path.join(libdir, "dyad")] + package_dyad_dirs(libdir))
    idx = _PKG_INDEX[key]
    return {n: idx.get(t.split(".")[-1], []) for n, t, _bb in _placements(block, "diagram")}


# ---------------------------------------------------------------------------
# SVG parsing


@dataclass
class Block:
    name: str
    box: tuple  # blocks: the placement box; boundary ports: the glyph Studio draws in it
    is_port: bool
    rot: float = 0.0
    labels: list = field(default_factory=list)  # (text, bbox) of each label drawn with the block
    frame: tuple = None  # the placement box (x1..x2, y1..y2 of the diagram metadata)
    body: tuple = None  # the icon as Studio draws it: fitted into the frame with its aspect ratio kept
    art: tuple = None  # (frame matrix, viewBox size, ink) of its icon's art, for refitting it into another box


@dataclass
class Glyph:
    """A connector glyph as Studio draws it: a boundary port, or a port of a block."""
    owner: str  # the block it belongs to; '' for a boundary port
    name: str
    frame: tuple  # its placement box
    box: tuple  # the ink of its icon, fitted into the frame with the aspect ratio kept
    pin: tuple  # where wires attach: the centre of the frame
    shape: list = None  # its outline: the convex hull of the icon's ink (the box if it is not known)
    fm: tuple = None  # the matrix mapping its 1000-unit frame into the diagram
    vb: tuple = (1.0, 1.0)  # its art's viewBox size
    ink: list = None  # its art's ink (art_ink), for refitting it into another frame

    def outline(self):
        return self.shape or [(self.box[0], self.box[1]), (self.box[2], self.box[1]), (self.box[2], self.box[3]), (self.box[0], self.box[3])]


@dataclass
class Wire:
    pts: list
    net: int = -1
    name: str = ""
    ends: tuple = ("?", "?")


@dataclass
class Diagram:
    blocks: list = field(default_factory=list)
    wires: list = field(default_factory=list)
    junctions: list = field(default_factory=list)
    free_labels: list = field(default_factory=list)  # (text, bbox)
    glyphs: list = field(default_factory=list)  # every connector glyph (Glyph), boundary ports included
    issues: dict = field(default_factory=dict)  # geometry of each finding, for the overlay
    ink_notes: list = field(default_factory=list)  # (icon, why) for each icon whose ink is only estimated


CHAR_W = 0.6  # average glyph width / font size for the sans-serif labels


def text_box(el, m):
    """Approximate global bbox of an SVG text element; m maps its user space (its own transform included)."""
    txt = "".join(el.itertext()).strip()
    try:
        fs = float(el.get("font-size", "16"))
        x = float(el.get("x", "0"))
        y = float(el.get("y", "0"))
    except ValueError:
        return txt, None
    w = CHAR_W * fs * max(len(txt), 1)
    anchor = el.get("text-anchor", "start")
    x0 = x - w / 2 if anchor == "middle" else (x - w if anchor == "end" else x)
    base = el.get("dominant-baseline", "")
    y0 = y - fs / 2 if base == "central" else y - 0.8 * fs
    return txt, map_box(m, x0, y0, x0 + w, y0 + fs)


def parse_path(d):
    toks = re.findall(r"[MLHVZmlhvz]|-?[\d.]+(?:[eE][-+]?\d+)?", d)
    pts = []
    cmd = None
    i = 0
    cur = (0.0, 0.0)
    while i < len(toks):
        t = toks[i]
        if re.match(r"[A-Za-z]", t):
            cmd = t
            i += 1
            continue
        if cmd in ("M", "L"):
            cur = (float(toks[i]), float(toks[i + 1]))
            i += 2
        elif cmd in ("m", "l"):
            cur = (cur[0] + float(toks[i]), cur[1] + float(toks[i + 1]))
            i += 2
        elif cmd == "H":
            cur = (float(t), cur[1]); i += 1
        elif cmd == "V":
            cur = (cur[0], float(t)); i += 1
        elif cmd == "h":
            cur = (cur[0] + float(t), cur[1]); i += 1
        elif cmd == "v":
            cur = (cur[0], cur[1] + float(t)); i += 1
        else:
            i += 1
            continue
        if not pts or seg_len(pts[-1], cur) > 1e-9:
            pts.append(cur)
    return pts


def _num(el, attr, default=None):
    v = el.get(attr)
    if v is None:
        return default
    v = v.strip()
    if v.endswith("px"):
        v = v[:-2]
    try:
        return float(v)
    except ValueError:
        raise UnsupportedSVG(f"<svg {attr}={el.get(attr)!r}>: only plain user-unit lengths are supported")


class Label(tuple):
    """A label as Studio draws it: unpacks as (text, box), where box is its element's box (what the DOM
    gives, for calibration); `ink` is the box of its painted letters (for collisions)."""

    def __new__(cls, text, box, ink=None):
        self = super().__new__(cls, (text, box))
        self.ink = ink if ink is not None else box
        return self


def studio_label_box(txt, anchor, sideways=False):
    """The box of a block or port label as Studio draws it: fixed size, centred on its anchor, and
    turned on its side when `sideways` (a block turned a quarter turn)."""
    return studio_label(txt, anchor, 90 if sideways else 0)[1]


def studio_label(txt, anchor, turn=0):
    """A block or port label as Studio draws it (Label): fixed size, centred on its anchor, turned with
    its block by `turn` (0, 90, 180 or 270 degrees clockwise; on a half turn the text is turned back
    upright within its line box). Studio's <dyad-label> is a 2-unit top margin (LABEL_MARGIN) over a
    line box 1.4 em high, the text on its baseline in the middle of it: the ink is the letters' extent
    above and below that baseline (Inter's glyph bounds) and from the first letter's ink to the last's."""
    W = label_width(txt)
    fs = LABEL_FONT / _INTER["units_per_em"]
    inks = [_INTER["ink"].get(c, _INTER["ink"]["n"]) for c in txt]
    lit = [i for i, c in enumerate(txt) if not c.isspace() and inks[i][0] + inks[i][1] > 0]
    if lit:
        adv = [_INTER["advance"].get(c, _INTER["advance"]["n"]) for c in txt]
        line = LABEL_HEIGHT - LABEL_MARGIN
        base = LABEL_MARGIN + (line - (_INTER["ascent"] + _INTER["descent"]) * fs) / 2 + _INTER["ascent"] * fs
        if turn == 180:
            base -= LABEL_MARGIN  # the host turns over (its margin to the bottom), the text turns back
        u0 = fs * (sum(adv[:lit[0]]) + inks[lit[0]][2])
        u1 = W - fs * (sum(adv[lit[-1] + 1:]) + inks[lit[-1]][3])
        v0 = base - fs * max(inks[i][0] for i in lit)
        v1 = base + fs * max(inks[i][1] for i in lit)
        ink = (u0, v0, u1, v1)
    else:
        ink = None
    sideways = turn in (90, 270)
    w, h = (LABEL_HEIGHT, W) if sideways else (W, LABEL_HEIGHT)
    box = (anchor[0] - w / 2, anchor[1] - h / 2, anchor[0] + w / 2, anchor[1] + h / 2)
    if ink is None:
        return Label(txt, box, (anchor[0], anchor[1], anchor[0], anchor[1]))

    def place(u, v):
        x, y = u - W / 2, v - LABEL_HEIGHT / 2
        if turn == 90:  # clockwise: the top of the letters faces right
            x, y = -y, x
        elif turn == 270:
            x, y = y, -x
        return (anchor[0] + x, anchor[1] + y)
    return Label(txt, box, bbox([place(ink[0], ink[1]), place(ink[2], ink[3])]))


INK_SKIP = ("defs", "style", "title", "desc", "metadata", "filter", "clipPath", "marker", "symbol", "mask", "pattern",
            "linearGradient", "radialGradient", "stop", "animate", "animateTransform", "animateMotion", "set", "script")
_NUM = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"


def path_outline(d):
    """Points on every subpath of an SVG path `d` (see path_subpaths)."""
    return [p for sub, _closed in path_subpaths(d) for p in sub]


def path_subpaths(d):
    """[(points, closed)] for each subpath of an SVG path `d` (all commands): line ends exactly, curves
    and arcs sampled finely enough that their convex hull is the path's within a fraction of a percent."""
    toks = re.findall(r"[MLHVCSQTAZmlhvcsqtaz]|" + _NUM, d)
    subs, pts, i, cmd = [], [], 0, None
    cur = start = (0.0, 0.0)
    prev_ctrl = None  # the last control point, for S and T

    def num():
        nonlocal i
        v = float(toks[i]); i += 1
        return v

    def flag():
        # arc flags may be written without separators ("a1 1 0 01 5 5")
        nonlocal i
        t = toks[i]
        if t in ("0", "1"):
            i += 1
            return int(t)
        if t[0] in "01":
            toks[i] = t[1:]
            return int(t[0])
        raise ValueError(f"arc flag {t!r}")

    def bez(p0, *c, n=16):
        for k in range(1, n + 1):
            t = k / n
            q = [p0, *c]
            while len(q) > 1:
                q = [(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t) for a, b in zip(q, q[1:])]
            pts.append(q[0])

    def arc(p0, rx, ry, phi, large, sweep, p1):
        # SVG 1.1 F.6.5: endpoint to centre parameterisation
        if rx == 0 or ry == 0 or p0 == p1:
            pts.append(p1)
            return
        rx, ry = abs(rx), abs(ry)
        c, s_ = math.cos(math.radians(phi)), math.sin(math.radians(phi))
        dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
        x1, y1 = c * dx + s_ * dy, -s_ * dx + c * dy
        lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lam > 1:
            rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
        num_ = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        k = math.sqrt(max(0.0, num_ / (rx * rx * y1 * y1 + ry * ry * x1 * x1)))
        if large == sweep:
            k = -k
        cx1, cy1 = k * rx * y1 / ry, -k * ry * x1 / rx
        cx, cy = c * cx1 - s_ * cy1 + (p0[0] + p1[0]) / 2, s_ * cx1 + c * cy1 + (p0[1] + p1[1]) / 2
        ang = lambda ux, uy: math.atan2(uy, ux)
        t0 = ang((x1 - cx1) / rx, (y1 - cy1) / ry)
        dt = ang((-x1 - cx1) / rx, (-y1 - cy1) / ry) - t0
        if sweep and dt < 0:
            dt += 2 * math.pi
        elif not sweep and dt > 0:
            dt -= 2 * math.pi
        for k in range(1, 33):
            t = t0 + dt * k / 32
            pts.append((cx + rx * math.cos(t) * c - ry * math.sin(t) * s_, cy + rx * math.cos(t) * s_ + ry * math.sin(t) * c))

    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]; i += 1
            if cmd in "Zz":
                if len(pts) > 1:
                    subs.append((pts, True))
                cur, pts = start, [start]  # drawing on without a moveto starts from the subpath's start
                prev_ctrl = None
                continue
        if cmd is None:
            raise ValueError("path data does not start with a command")
        rel = cmd.islower()
        o = cur if rel else (0.0, 0.0)
        C = cmd.upper()
        if C == "M":
            cur = start = (o[0] + num(), o[1] + num())
            if len(pts) > 1:
                subs.append((pts, False))
            pts = [cur]
            cmd = "l" if rel else "L"  # further pairs are lines
            prev_ctrl = None
            continue
        if C == "L":
            cur = (o[0] + num(), o[1] + num()); pts.append(cur); prev_ctrl = None
        elif C == "H":
            cur = ((cur[0] if rel else 0.0) + num(), cur[1]); pts.append(cur); prev_ctrl = None
        elif C == "V":
            cur = (cur[0], (cur[1] if rel else 0.0) + num()); pts.append(cur); prev_ctrl = None
        elif C in "CSQT":
            kind = "C" if C in "CS" else "Q"
            if C in "CQ":
                c1 = (o[0] + num(), o[1] + num())
            elif prev_ctrl and prev_ctrl[0] == kind:  # S, T: the previous control point reflected
                c1 = (2 * cur[0] - prev_ctrl[1][0], 2 * cur[1] - prev_ctrl[1][1])
            else:
                c1 = cur
            ctrl = [c1] + ([(o[0] + num(), o[1] + num())] if kind == "C" else [])
            p1 = (o[0] + num(), o[1] + num())
            bez(cur, *ctrl, p1)
            prev_ctrl, cur = (kind, ctrl[-1]), p1
        elif C == "A":
            rx, ry, phi = num(), num(), num()
            large, sweep = flag(), flag()
            p1 = (o[0] + num(), o[1] + num())
            arc(cur, rx, ry, phi, large, sweep, p1)
            cur, prev_ctrl = p1, None
        else:
            raise ValueError(f"path data: a number after {cmd}")
    if len(pts) > 1:
        subs.append((pts, False))
    return subs


def art_ink(el, strokes=True):
    """The outline of an icon <svg>'s ink: the convex hull of its shapes, as fractions of its
    viewBox, or None for the whole viewBox. See art_ink_info."""
    return art_ink_info(el, strokes=strokes)[0]


PAINT_PROPS = ("fill", "stroke", "stroke-width", "stroke-linejoin", "stroke-linecap", "stroke-miterlimit")
_UNITS = {"": 1.0, "px": 1.0, "mm": 96 / 25.4, "cm": 96 / 2.54, "in": 96.0, "pt": 96 / 72, "pc": 16.0}


def _decls(text):
    """The declarations of a CSS block or style attribute, {property: value}."""
    out = {}
    for d in (text or "").split(";"):
        if ":" in d:
            k, v = d.split(":", 1)
            out[k.strip().lower()] = v.replace("!important", "").strip()
    return out


def _css_rules(el, notes):
    """The rules of the <style> elements in an icon that select by tag, class and id, in cascade order:
    [(tag or None, [('.' or '#', name)], {property: value})]. Other selectors that set paint are noted."""
    rules = []
    for st in el.iter(SVGNS + "style"):
        text = re.sub(r"/\*.*?\*/", "", "".join(st.itertext()), flags=re.S)
        for sels, body in re.findall(r"([^{}]+)\{([^{}]*)\}", text):
            decls = {k: v for k, v in _decls(body).items() if k in PAINT_PROPS}
            if not decls:
                continue
            for sel in sels.split(","):
                m = re.fullmatch(r"([a-zA-Z][\w-]*)?((?:[.#][\w-]+)*)", sel.strip())
                if not m or not sel.strip():
                    notes.add("stroke style estimated")
                    continue
                parts = re.findall(r"([.#])([\w-]+)", m.group(2))
                spec = (sum(k == "#" for k, _ in parts), sum(k == "." for k, _ in parts), 1 if m.group(1) else 0)
                rules.append((spec, len(rules), m.group(1), parts, decls))
    return [(tag, parts, decls) for _s, _o, tag, parts, decls in sorted(rules, key=lambda r: (r[0], r[1]))]


def _length(v, ref, notes):
    m = re.fullmatch(r"\s*(" + _NUM + r")\s*([a-z%]*)\s*", v or "")
    if not m:
        raise ValueError(f"length {v!r}")
    if m.group(2) == "%":
        notes.add("stroke width estimated")
        return float(m.group(1)) / 100 * ref
    if m.group(2) not in _UNITS:
        raise ValueError(f"length {v!r}")
    return float(m.group(1)) * _UNITS[m.group(2)]


def stroke_outline(subs, h, join="miter", cap="butt", miterlimit=4.0):
    """Points whose convex hull holds the stroke of half-width `h` along subpaths [(points, closed)]:
    each segment offset to both sides, miter tips (within the miter limit) or round joins, and caps."""
    out = []
    circle = lambda v: [(v[0] + h / math.cos(math.pi / 16) * math.cos(k * math.pi / 8),
                         v[1] + h / math.cos(math.pi / 16) * math.sin(k * math.pi / 8)) for k in range(16)]
    unit = lambda a, b: ((b[0] - a[0]) / seg_len(a, b), (b[1] - a[1]) / seg_len(a, b))
    for pts, closed in subs:
        pts = [p for i, p in enumerate(pts) if i == 0 or seg_len(p, pts[i - 1]) > 1e-9]
        if closed and len(pts) > 1 and seg_len(pts[0], pts[-1]) <= 1e-9:
            pts = pts[:-1]
        n = len(pts)
        if n == 1:
            out += circle(pts[0]) if cap == "round" else [(pts[0][0] + dx, pts[0][1] + dy) for dx in (-h, h) for dy in (-h, h)] if cap == "square" else []
            continue
        segs = list(zip(pts, pts[1:])) + ([(pts[-1], pts[0])] if closed else [])
        for a, b in segs:
            ux, uy = unit(a, b)
            out += [(q[0] + sg * -uy * h, q[1] + sg * ux * h) for q in (a, b) for sg in (-1, 1)]
        for k in (range(n) if closed else range(1, n - 1)):
            v, a, b = pts[k], pts[k - 1], pts[(k + 1) % n]
            if join == "round":
                out += circle(v)
            elif join in ("miter", "miter-clip", "arcs"):
                u1, u2 = unit(v, a), unit(v, b)
                sin_half = math.sqrt(max(0.0, (1 - (u1[0] * u2[0] + u1[1] * u2[1])) / 2))
                bx, by = u1[0] + u2[0], u1[1] + u2[1]
                bl = math.hypot(bx, by)
                if sin_half > 1e-9 and bl > 1e-9 and 1 / sin_half <= miterlimit:
                    out.append((v[0] - bx / bl * h / sin_half, v[1] - by / bl * h / sin_half))
        if not closed:
            for e, nb in ((pts[0], pts[1]), (pts[-1], pts[-2])):
                if cap == "round":
                    out += circle(e)
                elif cap == "square":
                    dx, dy = unit(nb, e)
                    out += [(e[0] + dx * h + sg * -dy * h, e[1] + dy * h + sg * dx * h) for sg in (-1, 1)]
    return out


def art_ink_info(el, skip_labels=False, strokes=True):
    """(outline, note): the convex hull of an icon <svg>'s ink as fractions of its viewBox (None: the
    whole viewBox), and why it is only an estimate (None if it is exact).

    Shapes are measured through nested <g> and <svg> elements and their transforms: polygon, polyline,
    rect, circle, ellipse, line, path (every command), image and foreignObject (their boxes). With
    `strokes`, a shape is what it paints: its fill (unless `fill: none`) and its stroke (width, joins,
    miter limit and caps), styled by presentation attributes, the icon's <style> rules (tag, class and
    id selectors) and `style` attributes, inherited down the tree; without, its geometry (what the DOM's
    bounding boxes give, for calibration). Each nested <svg> clips what it holds to its viewport, and
    the icon's own viewBox clips the rest. Text is estimated from its font size and length (CHAR_W).
    Anything else (<use>, a malformed shape) makes the whole viewBox the ink. With `skip_labels`, the
    <svg>'s own <text> children are labels (parse_svg's), not ink.
    """
    vb = el.get("viewBox")
    if not vb:
        return None, "no viewBox"
    try:
        vx, vy, vw, vh = (float(v) for v in re.split(r"[\s,]+", vb.strip()))
    except ValueError:
        return None, f"viewBox={vb!r}"
    if vw <= 0 or vh <= 0:
        return None, f"viewBox={vb!r}"
    notes = set()
    rules = _css_rules(el, notes)
    f = lambda v, d=0.0: float(v) if v not in (None, "") else d
    none = lambda v: (v or "").strip().lower() in ("none", "transparent")

    def style(c, t, inh):
        st = dict(inh)
        own = {k: c.get(k) for k in PAINT_PROPS if c.get(k) is not None}
        classes, cid = (c.get("class") or "").split(), c.get("id")
        for tag, parts, decls in rules:
            if (not tag or tag == t) and all((name in classes) if k == "." else (name == cid) for k, name in parts):
                own.update(decls)
        own.update({k: v for k, v in _decls(c.get("style")).items() if k in PAINT_PROPS})
        st.update({k: v for k, v in own.items() if v != "inherit"})
        return st

    def shape(c, t, vp):
        """[(points, closed)] of a basic shape, in its own user space; and whether it can be filled."""
        if t in ("polygon", "polyline"):
            v = [float(x) for x in re.findall(_NUM, c.get("points") or "")]
            return [(list(zip(v[0::2], v[1::2])), t == "polygon")], True
        if t == "rect":
            x, y, w, h = f(c.get("x")), f(c.get("y")), f(c.get("width")), f(c.get("height"))
            return ([([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], True)] if w > 0 and h > 0 else []), True
        if t in ("circle", "ellipse"):
            cx, cy = f(c.get("cx")), f(c.get("cy"))
            rx = f(c.get("r") if t == "circle" else c.get("rx")); ry = f(c.get("r") if t == "circle" else c.get("ry"))
            return [([(cx + rx * math.cos(k * math.pi / 16), cy + ry * math.sin(k * math.pi / 16)) for k in range(32)], True)], True
        if t == "line":
            return [([(f(c.get("x1")), f(c.get("y1"))), (f(c.get("x2")), f(c.get("y2")))], False)], False
        if t == "path":
            return path_subpaths(c.get("d") or ""), True
        return None, False

    def walk(e, vp, inh):
        """The convex outlines of what `e` holds, in its user space."""
        polys = []
        for c in e:
            t = c.tag.replace(SVGNS, "") if isinstance(c.tag, str) else ""
            if t in INK_SKIP or not t or c.get("display") == "none" or c.get("visibility") == "hidden":
                continue
            if t == "text" and skip_labels and e is el:
                continue
            T = parse_transform(c.get("transform"))
            st = style(c, t, inh)
            sub = []
            if t in ("g", "a", "switch"):
                sub = walk(c, vp, st)
            elif t == "svg":
                vm, (x, y, w, h) = viewport_matrix(c, *vp)
                inner = tuple(float(v) for v in re.split(r"[\s,]+", c.get("viewBox").strip())[2:4]) if c.get("viewBox") else (w, h)
                sub = [[apply(vm, *p) for p in P] for P in walk(c, inner, st)]
                if (c.get("overflow") or _decls(c.get("style")).get("overflow") or "hidden") not in ("visible", "auto"):
                    sub = [clip_poly_box(P, (x, y, x + w, y + h)) for P in sub]  # a nested viewport clips
            elif t in ("image", "foreignObject"):
                x, y = f(c.get("x")), f(c.get("y"))
                w, h = f(c.get("width"), vp[0]), f(c.get("height"), vp[1])
                sub = [[(x, y), (x + w, y), (x + w, y + h), (x, y + h)]]
            elif t == "text":
                _txt, bb = text_box(c, IDENT)
                if bb:
                    sub = [[(bb[0], bb[1]), (bb[2], bb[1]), (bb[2], bb[3]), (bb[0], bb[3])]]
                    notes.add("text estimated")
            else:
                subs, fillable = shape(c, t, vp)
                if subs is None:
                    raise ValueError(f"<{t}>")
                pts = []
                if not strokes or (fillable and not none(st.get("fill", "black"))):
                    pts += [p for q, _closed in subs for p in q]
                if strokes and not none(st.get("stroke", "none")):
                    w = _length(st.get("stroke-width", "1"), math.hypot(*vp) / math.sqrt(2), notes)
                    if w > 0:
                        pts += stroke_outline(subs, w / 2, st.get("stroke-linejoin", "miter"),
                                              st.get("stroke-linecap", "butt"), float(st.get("stroke-miterlimit", "4")))
                hull = convex_hull(pts)
                sub = [hull] if len(hull) >= 3 else []
            polys += [[apply(T, *p) for p in P] for P in sub if len(P) >= 3]
        return polys

    try:
        polys = walk(el, (vw, vh), style(el, "svg", {}))  # the icon <svg>'s own paint is inherited too
    except (ValueError, TypeError, IndexError, ZeroDivisionError) as e:
        return None, f"cannot measure {e}" if str(e).startswith("<") else f"cannot measure the art ({type(e).__name__}: {e})"
    hull = convex_hull([p for P in polys for p in P])
    if len(hull) >= 3:
        hull = clip_poly_box(hull, (vx, vy, vx + vw, vy + vh))
    if len(hull) < 3:
        return None, "no area"
    note = "; ".join(sorted(notes)) or None
    return convex_hull([((x - vx) / vw, (y - vy) / vh) for x, y in hull]), note


def convex_hull(pts):
    """Convex hull (Andrew's monotone chain), counter-clockwise in a y-down frame."""
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2 and _cross(out[-2], out[-1], p) <= 1e-12:
                out.pop()
            out.append(p)
        return out[:-1]
    return half(pts) + half(pts[::-1])


def view_size(art):
    """(width, height) of an icon <svg>'s viewBox; (1, 1) if it has none."""
    if art is not None and art.get("viewBox"):
        try:
            vw, vh = (float(v) for v in re.split(r"[\s,]+", art.get("viewBox").strip())[2:4])
        except ValueError:
            return 1.0, 1.0
        if vw > 0 and vh > 0:
            return vw, vh
    return 1.0, 1.0


def fit_icon(m, vb=(1.0, 1.0), ink=None):
    """The outline Studio draws an icon with: art with viewBox size `vb` fitted into the frame `m`
    maps 0..1000 to, aspect ratio kept, centred, and turned as `m` turns it. `ink` (from art_ink)
    narrows it to the drawn shapes. Returns the outline's points.

    Only quarter turns and mirrors are modelled (Dyad's D4 placements); any other rotation raises
    UnsupportedSVG rather than fitting the art into the turned frame's bounding box."""
    fx0, fy0, fx1, fy1 = map_box(m, 0, 0, ICON_SIZE, ICON_SIZE)
    vw, vh = vb
    a, b, c, d = m[:4]
    ref = max(abs(a), abs(b), abs(c), abs(d), 1e-300)
    if not ((abs(b) < 1e-6 * ref and abs(c) < 1e-6 * ref) or (abs(a) < 1e-6 * ref and abs(d) < 1e-6 * ref)):
        raise UnsupportedSVG(f"an icon turned {math.degrees(math.atan2(b, a)):.4g} degrees: only quarter turns are modelled")
    sg = lambda v: 0.0 if abs(v) < 1e-6 * ref else math.copysign(1.0, v)
    o = (sg(a), sg(b), sg(c), sg(d))
    turned = abs(b) > abs(a)  # a quarter turn swaps the art's width and height
    W, H = (vh, vw) if turned else (vw, vh)
    k = min((fx1 - fx0) / W, (fy1 - fy0) / H)
    cx, cy = (fx0 + fx1) / 2, (fy0 + fy1) / 2
    out = []
    for u, v in ink or ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)):
        x, y = (u - 0.5) * vw * k, (v - 0.5) * vh * k
        out.append((cx + o[0] * x + o[2] * y, cy + o[1] * x + o[3] * y))
    return out


def bbox(pts):
    return (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))


def viewport_matrix(el, default_w=None, default_h=None, sized=False):
    """Mapping from a nested <svg>'s user space to its parent's: x/y offset plus viewBox scaling.

    Implements the default preserveAspectRatio (xMidYMid meet) and "none".
    Width and height default to the given values; with neither, the nested
    viewport's size is unknown and the SVG is rejected. With `sized`, the given
    size is used whatever the element says (a Dyad icon frame is 1000 units).
    """
    x = _num(el, "x", 0.0)
    y = _num(el, "y", 0.0)
    w = default_w if sized else _num(el, "width", default_w)
    h = default_h if sized else _num(el, "height", default_h)
    vb = el.get("viewBox")
    if not vb:
        return translate(x, y), (x, y, w, h)
    if w is None or h is None:
        raise UnsupportedSVG("nested <svg> with a viewBox but no width/height: its viewport is unknown")
    vx, vy, vw, vh = (float(v) for v in re.split(r"[\s,]+", vb.strip()))
    if vw <= 0 or vh <= 0:
        raise UnsupportedSVG(f"nested <svg viewBox={vb!r}>")
    sx, sy = w / vw, h / vh
    par = (el.get("preserveAspectRatio") or "xMidYMid meet").split()
    if par[0] != "none":
        if par[0] != "xMidYMid" or (len(par) > 1 and par[1] != "meet"):
            raise UnsupportedSVG(f"nested <svg preserveAspectRatio={el.get('preserveAspectRatio')!r}>")
        s = min(sx, sy)
        tx = x + (w - vw * s) / 2 - vx * s
        ty = y + (h - vh * s) / 2 - vy * s
        return (s, 0.0, 0.0, s, tx, ty), (x, y, w, h)
    return (sx, 0.0, 0.0, sy, x - vx * sx, y - vy * sy), (x, y, w, h)


ICON_SIZE = 1000.0  # Dyad draws every block and port icon as <svg viewBox="0 0 1000 1000"> in a 1000x1000 frame

# How Dyad Studio draws a placement box (the diagram view of Studio 3.5.1, checked against its DOM; see README):
# - the box is the frame; the icon is fitted into it with its aspect ratio kept and centred (CSS/SVG
#   "meet"). `dyad render` stretches the icon to the box instead, so a 200x800 block draws as a
#   200x200 square in the middle of its box, and the pins on the box edge float away from it.
# - connector glyphs are placed the same way: the frame from the connector's icon placement, mapped
#   through the block's (non-uniform) box; the glyph is fitted into that frame.
# - labels are drawn at a fixed size, centred on their anchor; the anchor is mapped through the box.
#   They are upright, except on a block turned a quarter turn, where they are drawn on their side.
#   A boundary port's name is drawn at (500, 1100) of its frame grown by PORT_PAD.
LABEL_FONT = 16.035  # Studio's label font size (em) in diagram units, whatever the size of the box (fitted to its DOM)
LABEL_HEIGHT = 24.45  # the height of Studio's label element: LABEL_MARGIN over a line box 1.4 em high
LABEL_MARGIN = 2.0  # Studio's label (`dyad-label`) has a 2px `margin-block-start` above its line box
PORT_PAD = 20.0  # Studio's host element for a boundary port is its frame grown by this much on every side
with open(os.path.join(HERE, "inter_metrics.json"), encoding="utf-8") as _f:
    # Advance widths, pair kerning and glyph ink of Inter, Studio's label font, per 1000 em (inter_metrics.mjs).
    # With them, label widths agree with Studio's DOM within 0.1 units for 1151 of the 1152 HL20Demo labels.
    _INTER = json.load(_f)


def label_width(txt):
    """Width of a label as Studio draws it: Inter's advances and pair kerning at LABEL_FONT."""
    adv, kern = _INTER["advance"], _INTER["kern"]
    w = sum(adv.get(c, adv["n"]) for c in txt) + sum(kern.get(txt[i:i + 2], 0) for i in range(len(txt) - 1))
    return LABEL_FONT * w / _INTER["units_per_em"]


def _local(el, center):
    m = parse_transform(el.get("transform"))
    if el.get("transform-origin", "").startswith("center"):
        m = mat_mul(translate(*center), mat_mul(m, translate(-center[0], -center[1])))
    elif el.get("transform-origin"):
        raise UnsupportedSVG(f"transform-origin={el.get('transform-origin')!r}")
    return m


def parse_svg(svg_text, src_boxes=None, src_ports=None, strokes=True):
    """Parse a `dyad render` SVG into blocks, wires, junctions and labels, in root user units.

    Transforms are accumulated down the tree (translate/scale/rotate/matrix on
    any element, the <svg> element included, and nested <svg> viewport
    mappings); any other transform is rejected. Groups are classified by
    content: Dyad wraps each block and boundary-port icon in a <g> with a direct
    <svg> child (a drop shadow on blocks only), and icons hold no wires. A <g>
    whose subtree holds a wire is a plain group whatever it wraps, so its
    wires, junctions and labels are measured like top-level ones, through any
    nested <svg> viewports.

    Icons and glyphs are measured as painted, strokes included (art_ink_info); with `strokes=False`,
    by their geometry, as the DOM's bounding boxes give them (studio_geometry's calibration).
    """
    # embedded icon SVGs carry their own XML declarations and doctypes
    svg_text = re.sub(r"<\?xml[^>]*\?>|<!DOCTYPE[^>]*>", "", svg_text)
    root = ET.fromstring(svg_text)
    dg = Diagram()
    center = (ICON_SIZE / 2, ICON_SIZE / 2)
    counter = [0]

    def tag_of(el):
        return el.tag.replace(SVGNS, "") if isinstance(el.tag, str) else ""

    def is_wire(el):
        return tag_of(el) == "path" and el.get("fill") == "transparent"

    def block(ch, m):
        shadow = "shadow" in (ch.get("filter") or "")
        icons = [sub for sub in ch if tag_of(sub) == "svg"]
        top = icons[0]
        # The frame is the icon's 1000x1000 viewport, in the group's coordinates, moved by the icon's own
        # transform. Dyad sizes every frame for 1000 units: the <svg>'s own width and height (210 on a
        # connector glyph) do not change where Studio draws it.
        fm = mat_mul(m, _local(top, center))
        frame_m = mat_mul(fm, translate(_num(top, "x", 0.0), _num(top, "y", 0.0)))
        box = map_box(frame_m, 0, 0, ICON_SIZE, ICON_SIZE)
        rot = math.degrees(math.atan2(fm[1], fm[0])) % 360
        im = mat_mul(fm, viewport_matrix(top, ICON_SIZE, ICON_SIZE, sized=True)[0])
        # The icon's own <svg> holds the art; a block wraps it in a <g> covering the whole frame,
        # followed by one <g> per connector glyph.
        parts = []
        for g in top:
            if tag_of(g) == "g":
                sub = next((x for x in g if tag_of(x) == "svg"), None)
                if sub is not None:
                    gm = mat_mul(mat_mul(_local(g, center), _local(sub, center)), translate(_num(sub, "x", 0.0), _num(sub, "y", 0.0)))
                    parts.append((sub, gm))
        art, art_m = top, frame_m
        if parts and all(abs(u - v) < 1e-6 for u, v in zip(map_box(parts[0][1], 0, 0, ICON_SIZE, ICON_SIZE), (0, 0, ICON_SIZE, ICON_SIZE))):
            (art, gm), parts = parts[0], parts[1:]
            art_m = mat_mul(im, gm)
        notes = []

        def ink(sub, what):
            outline, note = art_ink_info(sub, skip_labels=sub is top, strokes=strokes)
            if note:
                notes.append((what, note))
            return outline
        # a block's frame <svg> also holds its glyphs and labels: without a wrapped icon, it is all icon
        art_ink_ = None if shadow and art is top else ink(art, None)
        body = bbox(fit_icon(art_m, view_size(art), art_ink_))
        texts = []
        for icon in icons:
            im_i = mat_mul(mat_mul(m, _local(icon, center)), viewport_matrix(icon, ICON_SIZE, ICON_SIZE, sized=True)[0])
            for t in icon:
                if tag_of(t) == "text":
                    txt = "".join(t.itertext()).strip()
                    _local(t, center)  # rejects what the parser does not model
                    # Dyad turns a label about its own centre (CSS `text { transform-origin: center }` in
                    # the icon) to keep it readable: the rotation does not move its anchor. Studio draws
                    # it upright on a block turned 0 or 180 degrees and on its side on a quarter turn.
                    upright = re.sub(r"rotate\s*\([^)]*\)", "", t.get("transform") or "")
                    tm = mat_mul(im_i, parse_transform(upright))
                    try:
                        anchor = apply(tm, float(t.get("x", "0")), float(t.get("y", "0")))
                    except ValueError:
                        continue
                    if txt:
                        texts.append(studio_label(txt, anchor, int(round(rot / 90.0)) % 4 * 90))
        name, label = None, None
        if texts:
            # the instance-name label names the block; parameter labels are kept too
            named = [t for t in texts if src_boxes and t[0] in src_boxes]
            name = (named or texts)[0][0]
            label = texts
        if not shadow:
            counter[0] += 1
        if name is None and src_boxes:
            c = ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2)
            best = min(src_boxes.items(), key=lambda kv: math.hypot((kv[1][0] + kv[1][2]) / 2 - c[0], (kv[1][1] + kv[1][3]) / 2 - c[1]))
            if math.hypot((best[1][0] + best[1][2]) / 2 - c[0], (best[1][1] + best[1][3]) / 2 - c[1]) < 2:
                name = best[0]
        named_port = name is not None
        if name is None:
            name = f"{'port' if not shadow else 'block'}#{counter[0]}"
        dg.ink_notes.extend((what or name, note) for what, note in notes)
        if shadow:
            dg.blocks.append(Block(name, box, False, rot, label or [], frame=box, body=body, art=(art_m, view_size(art), art_ink_)))
            known = (src_ports or {}).get(name) or []
            for k, (sub, gm) in enumerate(parts):
                local = map_box(gm, 0, 0, ICON_SIZE, ICON_SIZE)  # in the block's 1000-unit icon space
                cname = next((n for n, bb in known if all(abs(u - v) <= 1.0 for u, v in zip(local, bb))), None)
                gfm = mat_mul(im, gm)
                fr = map_box(gfm, 0, 0, ICON_SIZE, ICON_SIZE)
                gname = f"{name}.{cname or '#%d' % (k + 1)}"
                vb, (gink, note) = view_size(sub), art_ink_info(sub, strokes=strokes)
                if note:
                    dg.ink_notes.append((gname, note))
                shape = fit_icon(gfm, vb, gink)
                dg.glyphs.append(Glyph(name, gname, fr, bbox(shape), ((fr[0] + fr[2]) / 2, (fr[1] + fr[3]) / 2), shape,
                                       fm=gfm, vb=vb, ink=gink))
        else:
            labels = []
            if named_port:  # Studio writes a boundary port's name under its glyph
                # its host element is the frame grown by PORT_PAD on every side; the label sits at (500, 1100) of that
                h = box[3] - box[1] + 2 * PORT_PAD
                labels.append(studio_label(name, ((box[0] + box[2]) / 2, box[1] - PORT_PAD + 1.1 * h)))
            shape = fit_icon(art_m, view_size(art), art_ink_)
            dg.blocks.append(Block(name, body, True, rot, labels, frame=box, body=body))
            dg.glyphs.append(Glyph("", name, box, body, ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2), shape,
                                   fm=art_m, vb=view_size(art), ink=art_ink_))

    def inner_size(el, w, h):
        """Size of the viewport an <svg> establishes for its children (None if unknown)."""
        vb = el.get("viewBox")
        if vb:
            vw, vh = (float(v) for v in re.split(r"[\s,]+", vb.strip())[2:4])
            return vw, vh
        return (w, h) if w is not None and h is not None else None

    def walk(parent, m, vp):
        for ch in parent:
            tag = tag_of(ch)
            if tag in ("defs", "style", "title", "desc", "metadata", "filter", "clipPath", "marker", "symbol", ""):
                continue
            lm = mat_mul(m, _local(ch, center))
            if tag == "g":
                if any(tag_of(sub) == "svg" for sub in ch) and not any(is_wire(el) for el in ch.iter()):
                    block(ch, lm)
                else:
                    walk(ch, lm, vp)
            elif tag == "svg":
                # width and height default to 100% of the parent viewport
                vm, (_x, _y, w, h) = viewport_matrix(ch, *(vp or (None, None)))
                walk(ch, mat_mul(lm, vm), inner_size(ch, w, h))
            elif is_wire(ch):
                pts = normalize_polyline([apply(lm, x, y) for x, y in parse_path(ch.get("d", ""))])
                if len(pts) >= 2:
                    dg.wires.append(Wire(pts))
            elif tag == "circle":
                dg.junctions.append(apply(lm, float(ch.get("cx", 0)), float(ch.get("cy", 0))))
            elif tag == "text":
                txt, bb = text_box(ch, lm)
                if bb:
                    dg.free_labels.append(Label(txt, bb))
            elif tag in ("use", "image", "foreignObject", "switch", "a"):
                raise UnsupportedSVG(f"<{tag}> at diagram level is not supported")

    try:  # the root's own size only matters to a nested <svg> that leaves out its width or height
        root_vp = inner_size(root, _num(root, "width"), _num(root, "height"))
    except (UnsupportedSVG, ValueError):
        root_vp = None
    walk(root, _local(root, center), root_vp)
    return dg


# ---------------------------------------------------------------------------
# metrics


class UF:
    def __init__(self, n):
        self.p = list(range(n))

    def find(self, i):
        while self.p[i] != i:
            self.p[i] = self.p[self.p[i]]
            i = self.p[i]
        return i

    def union(self, a, b):
        self.p[self.find(a)] = self.find(b)


def point_on_polyline(p, pts, tol=0.5):
    for a, b in zip(pts, pts[1:]):
        l = seg_len(a, b)
        if l < 1e-9:
            continue
        if abs(_cross(a, b, p)) / l <= tol and min(a[0], b[0]) - tol <= p[0] <= max(a[0], b[0]) + tol \
                and min(a[1], b[1]) - tol <= p[1] <= max(a[1], b[1]) + tol:
            return True
    return False


def assign_nets(dg):
    n = len(dg.wires)
    uf = UF(n)
    key = lambda p: (round(p[0], 1), round(p[1], 1))
    ends = {}
    for i, w in enumerate(dg.wires):
        for p in (w.pts[0], w.pts[-1]):
            ends.setdefault(key(p), []).append(i)
    for ids in ends.values():
        for j in ids[1:]:
            uf.union(ids[0], j)
    # junction dots join every wire that passes through them
    for jp in dg.junctions:
        hit = [i for i, w in enumerate(dg.wires) if point_on_polyline(jp, w.pts, 1.0)]
        for j in hit[1:]:
            uf.union(hit[0], j)
    for i, w in enumerate(dg.wires):
        w.net = uf.find(i)


def owner_of(p, blocks, junctions=(), tol=12.0):
    for j in junctions:
        if seg_len(p, j) <= 6:
            return "junction"
    best, bd = "?", tol
    for b in blocks:
        x0, y0, x1, y1 = b.box
        dx = max(x0 - p[0], 0, p[0] - x1)
        dy = max(y0 - p[1], 0, p[1] - y1)
        d = math.hypot(dx, dy)
        if d < bd or (d == bd == 0 and not b.is_port):
            best, bd = b.name, d
    return best


def largest_empty_square(grid):
    rows, cols = len(grid), len(grid[0]) if grid else 0
    best = 0
    prev = [0] * (cols + 1)
    for r in range(rows):
        cur = [0] * (cols + 1)
        for c in range(cols):
            if not grid[r][c]:
                cur[c + 1] = 1 + min(prev[c], prev[c + 1], cur[c])
                best = max(best, cur[c + 1])
        prev = cur
    return best


def merge_overlaps(runs, tol=0.25):
    """Merge the collinear segment overlaps of one wire pair into contiguous runs.

    Returns [(length, [segment pairs])]: one entry per contiguous shared run,
    however many segments of either wire it spans.
    """
    ivs = []
    for p1, p2, p3, p4 in runs:
        l = seg_len(p1, p2)
        ux, uy = (p2[0] - p1[0]) / l, (p2[1] - p1[1]) / l
        if ux < -1e-9 or (abs(ux) <= 1e-9 and uy < 0):
            ux, uy = -ux, -uy
        off = -uy * p1[0] + ux * p1[1]  # signed distance of the supporting line from the origin
        a0, a1 = sorted((p1[0] * ux + p1[1] * uy, p2[0] * ux + p2[1] * uy))
        b0, b1 = sorted((p3[0] * ux + p3[1] * uy, p4[0] * ux + p4[1] * uy))
        ivs.append(((round(ux, 3), round(uy, 3)), off, max(a0, b0), min(a1, b1), (p1, p2, p3, p4)))
    ivs.sort(key=lambda v: (v[0], v[1], v[2]))
    out = []
    for d, off, lo, hi, seg in ivs:
        if out and out[-1][0] == d and abs(out[-1][1] - off) <= tol and lo <= out[-1][3] + tol:
            out[-1][3] = max(out[-1][3], hi)
            out[-1][4].append(seg)
        else:
            out.append([d, off, lo, hi, [seg]])
    return [(hi - lo, segs) for _d, _o, lo, hi, segs in out]


# Glyph checks: tolerances, in diagram units unless stated (see README).
GLYPH_GAP = 0.1  # glyphs closer than this fraction of the smaller one's size touch (glyph_overlap)
BODY_DEPTH = 1.0  # a glyph reaching this far into another block's icon lies on it (glyph_overlap)
DETACH_GAP = 0.25  # a block's glyph further than this fraction of its size (and 2 units) from the drawn icon is detached
# (each beyond what it is with the block at the default size STD_BLOCK: that is the child's icon's design)
OVERHANG = 0.5  # a glyph with more than this fraction of its length past the end of its side of the icon overhangs,
OVERHANG_OUT = (0.75, 30.0)  # and so does one this much more outside the icon (area fraction), or this much outside
# that sticks out this many units further than the same glyph, scaled, at the default size
LABEL_COVER = 25.0  # a label with more than this much of its text's ink under a glyph (a quarter of a character's) is covered
STD_BLOCK = 100.0  # Dyad's default placement size: a block's own glyphs cover its own labels this much by design
PIN_TOL = 0.5  # a wire end this close to a glyph's pin is wired to it (`dyad render` ends wires exactly on the pin)
# A wire or junction dot is on a glyph once it gets this far inside the outline: half the depth of the
# outline's centre, or GRAZE units, whichever is less. Closer to the edge it runs along the glyph's stroke.
THRU_DEPTH = 0.6
GRAZE = 2.0
# A wire running along a glyph, nearer its edge, still counts when one passage is long: at least RUN_FRAC
# of the glyph's size and RUN_MIN units, at least RUN_DEPTH units inside the painted outline.
RUN_FRAC, RUN_MIN, RUN_DEPTH = 0.5, 20.0, 1.0
JUNCTION_R = 2.5  # radius of Studio's junction dot
NEAR_DIAG = (0.001, 0.5)  # a segment off the horizontal or vertical by this much is a near-diagonal


def box_size(b):
    return min(b[2] - b[0], b[3] - b[1])


def box_poly(b):
    return [(b[0], b[1]), (b[2], b[1]), (b[2], b[3]), (b[0], b[3])]


def poly_sep(P, Q):
    """Signed separation of two convex polygons along the best separating axis: > 0 apart by at
    least that much, <= 0 overlapping by that depth."""
    best = -math.inf
    for poly in (P, Q):
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            ex, ey = b[0] - a[0], b[1] - a[1]
            n = math.hypot(ex, ey)
            if n < 1e-12:
                continue
            ax, ay = -ey / n, ex / n
            pp = [x * ax + y * ay for x, y in P]
            qq = [x * ax + y * ay for x, y in Q]
            best = max(best, min(qq) - max(pp), min(pp) - max(qq))
    return best


def clip_poly_box(P, b):
    """The part of convex polygon P inside box b (Sutherland-Hodgman)."""
    out = list(P)
    for inside, cut in ((lambda p: p[0] >= b[0], lambda p, q: (b[0], p[1] + (q[1] - p[1]) * (b[0] - p[0]) / (q[0] - p[0]))),
                        (lambda p: p[0] <= b[2], lambda p, q: (b[2], p[1] + (q[1] - p[1]) * (b[2] - p[0]) / (q[0] - p[0]))),
                        (lambda p: p[1] >= b[1], lambda p, q: (p[0] + (q[0] - p[0]) * (b[1] - p[1]) / (q[1] - p[1]), b[1])),
                        (lambda p: p[1] <= b[3], lambda p, q: (p[0] + (q[0] - p[0]) * (b[3] - p[1]) / (q[1] - p[1]), b[3]))):
        src, out = out, []
        for i, q in enumerate(src):
            p = src[i - 1]
            if inside(q):
                if not inside(p):
                    out.append(cut(p, q))
                out.append(q)
            elif inside(p):
                out.append(cut(p, q))
        if not out:
            break
    return out


def poly_area(P):
    return abs(sum(P[i - 1][0] * P[i][1] - P[i][0] * P[i - 1][1] for i in range(len(P)))) / 2 if len(P) >= 3 else 0.0


def clip_t_in_poly(p, q, P):
    """The parameter interval (t0, t1) of segment pq inside convex polygon P (Cyrus-Beck), or None."""
    cx = sum(x for x, _ in P) / len(P)
    cy = sum(y for _, y in P) / len(P)
    t0, t1 = 0.0, 1.0
    dx, dy = q[0] - p[0], q[1] - p[1]
    for i in range(len(P)):
        a, b = P[i], P[(i + 1) % len(P)]
        nx, ny = -(b[1] - a[1]), b[0] - a[0]
        if nx * (cx - a[0]) + ny * (cy - a[1]) < 0:
            nx, ny = -nx, -ny  # inward normal
        num = nx * (p[0] - a[0]) + ny * (p[1] - a[1])
        den = nx * dx + ny * dy
        if abs(den) < 1e-12:
            if num < 0:
                return None
            continue
        t = -num / den
        if den > 0:
            t0 = max(t0, t)
        else:
            t1 = min(t1, t)
        if t0 >= t1:
            return None
    return t0, t1


def clip_len_in_poly(p, q, P):
    """Length of segment pq inside convex polygon P."""
    t = clip_t_in_poly(p, q, P)
    return (t[1] - t[0]) * seg_len(p, q) if t else 0.0


def poly_depth(P, p):
    """How far point p is inside convex polygon P: its distance to the nearest edge (negative outside)."""
    cx = sum(x for x, _ in P) / len(P)
    cy = sum(y for _, y in P) / len(P)
    best = math.inf
    for i in range(len(P)):
        a, b = P[i], P[(i + 1) % len(P)]
        n = seg_len(a, b)
        if n < 1e-12:
            continue
        d = _cross(a, b, p) / n
        best = min(best, d if _cross(a, b, (cx, cy)) >= 0 else -d)
    return best


def poly_centroid(P):
    A = sum(P[i - 1][0] * P[i][1] - P[i][0] * P[i - 1][1] for i in range(len(P))) / 2
    if abs(A) < 1e-12:
        return (sum(x for x, _ in P) / len(P), sum(y for _, y in P) / len(P))
    cx = sum((P[i - 1][0] + P[i][0]) * (P[i - 1][0] * P[i][1] - P[i][0] * P[i - 1][1]) for i in range(len(P))) / (6 * A)
    cy = sum((P[i - 1][1] + P[i][1]) * (P[i - 1][0] * P[i][1] - P[i][0] * P[i - 1][1]) for i in range(len(P))) / (6 * A)
    return (cx, cy)


@dataclass
class Passage:
    """One continuous run of a wire inside a glyph's outline."""
    length: float = 0.0
    depth: float = -math.inf  # the furthest it gets from the outline
    segs: list = field(default_factory=list)  # its pieces, as (p, q)
    ends: list = field(default_factory=list)  # the wire's own ends it holds
    first: tuple = None  # where it enters (or starts)
    last: tuple = None  # where it leaves (or ends)


def passages(pts, P, eps=1e-9):
    """The continuous runs of polyline `pts` inside convex polygon P. A run goes on across a waypoint
    inside P, so a zigzag that never leaves P is one passage however short each leg is."""
    out, cur = [], None
    n = len(pts) - 1
    for k, (p, q) in enumerate(zip(pts, pts[1:])):
        t = clip_t_in_poly(p, q, P)
        if t is None or (t[1] - t[0]) * seg_len(p, q) <= eps:
            cur = None
            continue
        a = (p[0] + (q[0] - p[0]) * t[0], p[1] + (q[1] - p[1]) * t[0])
        b = (p[0] + (q[0] - p[0]) * t[1], p[1] + (q[1] - p[1]) * t[1])
        if cur is None or t[0] > eps:
            cur = Passage(first=a)
            out.append(cur)
        cur.length += seg_len(a, b)
        cur.segs.append((a, b))
        cur.last = b
        cur.depth = max(cur.depth, max(poly_depth(P, (a[0] + (b[0] - a[0]) * j / 32, a[1] + (b[1] - a[1]) * j / 32)) for j in range(33)))
        if k == 0 and t[0] <= eps:
            cur.ends.append(pts[0])
        if k == n - 1 and t[1] >= 1 - eps:
            cur.ends.append(pts[-1])
        if t[1] < 1 - eps:
            cur = None
    return out


def glyph_edge(box, body):
    """The side of the drawn icon a block's glyph sits on, and the fraction of the glyph's length past the end of it."""
    x0, y0, x1, y1 = body
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    side = min((abs(cx - x0), "left"), (abs(cx - x1), "right"), (abs(cy - y0), "top"), (abs(cy - y1), "bottom"))[1]
    lo, hi, a, b = (box[1], box[3], y0, y1) if side in ("left", "right") else (box[0], box[2], x0, x1)
    past = max(0.0, a - lo) + max(0.0, hi - b)
    return side, min(1.0, past / max(hi - lo, 1e-9))


def to_default_size(block):
    """The matrix that resizes a block's frame to Dyad's default STD_BLOCK square about its centre."""
    x0, y0, x1, y1 = block.frame
    sx, sy = STD_BLOCK / max(x1 - x0, 1e-9), STD_BLOCK / max(y1 - y0, 1e-9)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return (sx, 0.0, 0.0, sy, cx - sx * cx, cy - sy * cy)


def at_default_size(g, block):
    """(glyph outline, icon body) of a block's glyph `g` with the block at Dyad's default size, or None
    if they cannot be refitted: what the child's icon draws whatever this diagram does."""
    if g.fm is None or block is None or block.frame is None or block.art is None:
        return None
    S = to_default_size(block)
    fm, vb, ink = block.art
    return fit_icon(mat_mul(S, g.fm), g.vb, g.ink), bbox(fit_icon(mat_mul(S, fm), vb, ink))


def glyph_fit(outline, body):
    """How a block's glyph sits on its icon: (gap to it, the side it is on, fraction of its length past
    the end of that side, fraction of its area outside the icon, how far it sticks out)."""
    box = bbox(outline)
    gap = poly_sep(outline, box_poly(body))
    side, past = glyph_edge(box, body)
    out = 1 - box_overlap_area(box, body) / max((box[2] - box[0]) * (box[3] - box[1]), 1e-9)
    sticks = max(body[0] - box[0], box[2] - body[2], body[1] - box[1], box[3] - body[3])
    return gap, side, past, out, sticks


WIRE_HALF = 0.75  # half the width of a wire as Studio draws it (a 1.5-unit stroke)


def expand(bb, d):
    return (bb[0] - d, bb[1] - d, bb[2] + d, bb[3] + d)


def own_label_baseline(g, block, lb):
    """How much of label `lb`'s text a block's own glyph `g` covers with the block at Dyad's default size
    (STD_BLOCK square, same centre): the overlap the child's icon causes whatever this diagram does.
    The label keeps its size (Studio draws labels at a fixed size); its anchor scales with the block."""
    if g.fm is None or block.frame is None:
        return 0.0
    S = to_default_size(block)
    outline = fit_icon(mat_mul(S, g.fm), g.vb, g.ink)
    box, ink = lb[1], lb.ink
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2  # the anchor: the centre of the line box
    ax, ay = apply(S, cx, cy)
    return poly_area(clip_poly_box(outline, (ink[0] + ax - cx, ink[1] + ay - cy, ink[2] + ax - cx, ink[3] + ay - cy)))


def glyph_metrics(dg):
    """Defects of connector glyphs and labels as Studio draws them (see README, "Glyph checks")."""
    m, det = {}, {}
    gl = dg.glyphs
    bodies = {b.name: b.body for b in dg.blocks if not b.is_port and b.body}
    blocks = {b.name: b for b in dg.blocks if not b.is_port}
    iss = dg.issues
    at_pin = lambda g, p: seg_len(p, g.pin) <= PIN_TOL
    # the nets wired to each glyph: wires that end on its pin
    nets = [{w.net for w in dg.wires for p in (w.pts[0], w.pts[-1]) if at_pin(g, p)} for g in gl]
    outl = [g.outline() for g in gl]
    # how deep each outline is at its centre, the yardstick for how far a wire or a dot gets into it
    core = [max(poly_depth(o, poly_centroid(o)), 1e-9) if len(o) >= 3 else 1e-9 for o in outl]
    # glyph_overlap: glyph pairs that overlap or touch, and glyphs on another block's icon. Two
    # unwired glyphs of one block piled up are the child's icon's doing: glyph_overlap_unwired.
    ov, unwired = [], []
    for i in range(len(gl)):
        for j in range(i + 1, len(gl)):
            a, b = gl[i], gl[j]
            if poly_sep(outl[i], outl[j]) < GLYPH_GAP * min(box_size(a.box), box_size(b.box)):
                if a.owner and a.owner == b.owner and not nets[i] and not nets[j]:
                    unwired.append(f"{a.name} / {b.name}")
                    iss.setdefault("glyph_unwired", []).extend((a.box, b.box))
                    continue
                ov.append(f"{a.name} / {b.name}")
                iss.setdefault("glyph", []).extend((a.box, b.box))
        for name, body in bodies.items():
            if name != gl[i].owner and poly_sep(outl[i], box_poly(body)) < -BODY_DEPTH:
                ov.append(f"{gl[i].name} on {name}")
                iss.setdefault("glyph", []).append(gl[i].box)
    m["glyph_overlap"], m["glyph_overlap_unwired"] = len(ov), len(unwired)
    det["glyph_overlap"], det["glyph_overlap_unwired"] = ov, unwired
    # glyph_detached / glyph_overhang: a block's glyphs against the icon Studio draws. What the glyph
    # already does with the block at Dyad's default size (at_default_size) is the child's icon's doing:
    # only what this diagram's placement adds counts.
    dt, oh = [], []
    for i, g in enumerate(gl):
        body = bodies.get(g.owner)
        if not g.owner or body is None:
            continue
        size = box_size(g.box)
        gap, side, past, out, sticks = glyph_fit(outl[i], body)
        std = at_default_size(g, blocks.get(g.owner))
        b_gap, _s, b_past, b_out, b_sticks = glyph_fit(*std) if std else (0.0, side, 0.0, 0.0, 0.0)
        b_size = box_size(bbox(std[0])) if std else size
        # compared as fractions of the glyph's size, which scales with the block: a standard pin on a big
        # block is a big pin standing as far off its big icon, which is no defect of the layout
        if gap > 2.0 and gap / max(size, 1e-9) - max(b_gap, 0.0) / max(b_size, 1e-9) > DETACH_GAP:
            dt.append(f"{g.name} ({gap:.0f} from {g.owner})")
            iss.setdefault("glyph", []).append(g.box)
            continue
        if past - b_past > OVERHANG + 0.01:  # a glyph centred on the corner is half past, however its stroke is drawn
            oh.append(f"{g.name} ({int(100 * past)}% past the end of the {side} side of {g.owner})")
            iss.setdefault("glyph", []).append(g.box)
        elif out - b_out > OVERHANG_OUT[0] or (out > OVERHANG_OUT[0] and sticks - max(b_sticks, 0.0) * size / max(b_size, 1e-9) > OVERHANG_OUT[1]):
            oh.append(f"{g.name} ({sticks:.0f} outside the {side} side of {g.owner})")
            iss.setdefault("glyph", []).append(g.box)
    m["glyph_detached"], m["glyph_overhang"] = len(dt), len(oh)
    det["glyph_detached"], det["glyph_overhang"] = dt, oh
    # label_covered: labels (block, port and free) a glyph lies on, a block's own glyphs over its own
    # labels included. When the block at Dyad's default size already covers its label as much, less
    # LABEL_COVER (own_label_baseline), the child's icon puts a glyph where Studio writes the name: that
    # is label_covered_by_icon, the child component's finding, not this layout's.
    lc, lci = [], []
    for owner, L in [("" if b.is_port else b.name, L) for b in dg.blocks for L in b.labels] + [("", L) for L in dg.free_labels]:
        txt, lb = L[0], L.ink  # the text's ink, not its line box: the padding round it is not covered
        hit, icon = [], []
        for i, g in enumerate(gl):
            if box_overlap_area(g.box, lb) <= 0:
                continue
            area = poly_area(clip_poly_box(outl[i], lb))
            if area <= LABEL_COVER:
                continue
            base = own_label_baseline(g, blocks[owner], L) if owner and g.owner == owner else 0.0
            if base > LABEL_COVER and area - base <= LABEL_COVER:
                icon.append(f"{g.name} ({area:.0f}; {base:.0f} at the default {STD_BLOCK:g}-unit size)")
            else:
                hit.append(g.name + (f" (its own: {area:.0f}, {base:.0f} at the default size)" if owner and g.owner == owner else ""))
        if hit:
            lc.append(f"{txt} under {', '.join(hit)}")
            iss.setdefault("label", []).append(lb)
        elif icon:
            lci.append(f"{txt} under {', '.join(icon)}")
            iss.setdefault("label_icon", []).append(lb)
    m["label_covered"], m["label_covered_by_icon"] = len(lc), len(lci)
    det["label_covered"], det["label_covered_by_icon"] = lc, lci
    # wire_thru_glyph: a wire running through a glyph, every glyph whatever its size. Wires of the net
    # wired to the glyph's pin may run over it: that is the connection (and a spur `dyad render` leaves
    # past the pin is on that net). Any other wire counts, along its route as drawn, once one continuous
    # passage through the outline gets deep enough (`deep`), or runs long enough along it: a zigzag is
    # one passage.
    deep = [min(THRU_DEPTH * c, GRAZE) for c in core]
    tg = []
    for w in dg.wires:
        wb = (min(p[0] for p in w.pts) - 1, min(p[1] for p in w.pts) - 1, max(p[0] for p in w.pts) + 1, max(p[1] for p in w.pts) + 1)
        for i, g in enumerate(gl):
            if len(outl[i]) < 3 or w.net in nets[i] or box_overlap_area(g.box, wb) <= 0:
                continue
            run = max(RUN_FRAC * box_size(g.box), RUN_MIN)
            bad = [ps for ps in passages(w.pts, outl[i]) if ps.depth >= deep[i] or (ps.length >= run and ps.depth >= RUN_DEPTH)]
            if bad:
                tg.append((w.name, g, max(ps.length for ps in bad)))
                iss.setdefault("through", []).extend(sg for ps in bad for sg in ps.segs)
    m["wire_thru_glyph"] = len(tg)
    m["wire_through_port"] = sum(1 for _w, g, _l in tg if not g.owner)
    det["wire_thru_glyph"] = [f"{n} through {g.name} ({L:.0f} inside)" for n, g, L in tg]
    # junction_on_glyph: a junction dot on or touching a glyph. On the glyph's own net, a dot at its pin
    # or not deep inside (at the rim, where the wire leaves it) is part of the connection.
    jg = []
    for jp in dg.junctions:
        dot = [(jp[0] + JUNCTION_R * math.cos(k * math.pi / 4), jp[1] + JUNCTION_R * math.sin(k * math.pi / 4)) for k in range(8)]
        jnets = {w.net for w in dg.wires if point_on_polyline(jp, w.pts, 1.0)}
        for i, g in enumerate(gl):
            if len(outl[i]) < 3 or poly_sep(dot, outl[i]) > 0:
                continue
            if jnets & nets[i] and (at_pin(g, jp) or poly_depth(outl[i], jp) < deep[i]):
                continue
            jg.append(f"({jp[0]:g}, {jp[1]:g}) on {g.name}")
            iss.setdefault("junction", []).append(jp)
    m["junction_on_glyph"] = len(jg)
    det["junction_on_glyph"] = jg
    # near_diagonal: segments a hair off the horizontal or vertical (a rounded waypoint against an unrounded pin)
    nd = []
    for w in dg.wires:
        for p, q in zip(w.pts, w.pts[1:]):
            dx, dy = abs(q[0] - p[0]), abs(q[1] - p[1])
            if NEAR_DIAG[0] < min(dx, dy) <= NEAR_DIAG[1] and max(dx, dy) > NEAR_DIAG[1]:
                nd.append(f"{w.name} at ({p[0]:g}, {p[1]:g})-({q[0]:g}, {q[1]:g})")
                iss.setdefault("near_diagonal", []).append((p, q))
    m["near_diagonal"] = len(nd)
    det["near_diagonal"] = nd
    return m, det


def compute_metrics(dg, cell=50.0, jog=10.0, outside_tol=30.0):
    assign_nets(dg)
    comps = [b for b in dg.blocks if not b.is_port]
    ports = [b for b in dg.blocks if b.is_port]
    for w in dg.wires:
        w.ends = (owner_of(w.pts[0], dg.blocks, dg.junctions), owner_of(w.pts[-1], dg.blocks, dg.junctions))
        w.name = f"{w.ends[0]}->{w.ends[1]}"
    m = {}
    m["blocks"] = len(comps)
    m["ports"] = len(ports)
    m["wires"] = len(dg.wires)
    m["nets"] = len({w.net for w in dg.wires})
    m["junctions"] = len(dg.junctions)

    # per-wire shape
    bends, lengths, detours, micro, diag = [], [], [], 0, 0
    detour_wires = []
    for w in dg.wires:
        segs = list(zip(w.pts, w.pts[1:]))
        L = sum(seg_len(a, b) for a, b in segs)
        lengths.append(L)
        nb = 0
        for (a, b), (c, d) in zip(segs, segs[1:]):
            v1 = (b[0] - a[0], b[1] - a[1])
            v2 = (d[0] - c[0], d[1] - c[1])
            if abs(v1[0] * v2[1] - v1[1] * v2[0]) > 1e-6 * (seg_len(a, b) * seg_len(c, d) + 1e-12):
                nb += 1
        bends.append(nb)
        for i, (a, b) in enumerate(segs):
            if abs(b[0] - a[0]) > 0.5 and abs(b[1] - a[1]) > 0.5:
                diag += 1
            if 0 < i < len(segs) - 1 and seg_len(a, b) < jog:
                micro += 1
        man = abs(w.pts[-1][0] - w.pts[0][0]) + abs(w.pts[-1][1] - w.pts[0][1])
        det = L / max(man, cell)
        detours.append(det)
        if det >= 2.5 and L >= 4 * cell:
            detour_wires.append((round(det, 1), w.name))
    nw = max(len(dg.wires), 1)
    m["bends_total"] = sum(bends)
    m["bends_mean"] = round(sum(bends) / nw, 2)
    m["bends_max"] = max(bends, default=0)
    m["micro_jogs"] = micro
    m["diagonal_segments"] = diag
    m["wire_len_total"] = round(sum(lengths), 1)
    m["wire_len_max"] = round(max(lengths, default=0), 1)
    m["detour_max"] = round(max(detours, default=0), 2)
    m["detour_wires"] = len(detour_wires)

    # pairwise wire contacts
    crossings, touches, overlap_runs, overlap_len = 0, 0, 0, 0.0
    cross_pts = []
    bbs = []
    for w in dg.wires:
        xs = [p[0] for p in w.pts]
        ys = [p[1] for p in w.pts]
        bbs.append((min(xs), min(ys), max(xs), max(ys)))
    per_wire_cross = [0] * len(dg.wires)
    for i in range(len(dg.wires)):
        wi = dg.wires[i]
        for j in range(i + 1, len(dg.wires)):
            wj = dg.wires[j]
            if wi.net == wj.net:
                continue
            a, b = bbs[i], bbs[j]
            if a[2] < b[0] - 1 or b[2] < a[0] - 1 or a[3] < b[1] - 1 or b[3] < a[1] - 1:
                continue
            seen = set()
            runs = []  # collinear shared runs of this pair, merged below
            for p1, p2 in zip(wi.pts, wi.pts[1:]):
                for p3, p4 in zip(wj.pts, wj.pts[1:]):
                    c = seg_contact(p1, p2, p3, p4)
                    if c is None:
                        continue
                    if c[0] == "overlap":
                        runs.append((p1, p2, p3, p4))
                    else:
                        k = (c[0], round(c[1][0]), round(c[1][1]))
                        if k in seen:
                            continue
                        seen.add(k)
                        if c[0] == "cross":
                            crossings += 1
                            per_wire_cross[i] += 1
                            per_wire_cross[j] += 1
                            cross_pts.append(c[1])
                        else:
                            touches += 1
                            dg.issues.setdefault("touch", []).append(c[1])
            for length, segs in merge_overlaps(runs):
                overlap_runs += 1
                overlap_len += length
                dg.issues.setdefault("overlap", []).extend(segs)
    m["crossings"] = crossings
    dg.issues["cross"] = cross_pts
    m["crossings_per_wire"] = round(crossings / nw, 2)
    m["false_junctions"] = touches
    m["overlap_runs"] = overlap_runs
    m["overlap_len"] = round(overlap_len, 1)

    # wires through blocks (through glyphs: glyph_metrics)
    through, through_len, through_list = 0, 0.0, []
    for w in dg.wires:
        for b in comps:
            inner = shrink(b.box, 1.0)
            if inner[2] <= inner[0] or inner[3] <= inner[1]:
                continue
            L = sum(clip_len_in_box(p, q, inner) for p, q in zip(w.pts, w.pts[1:]))
            if L > 1.0:
                through += 1
                through_len += L
                through_list.append((w.name, b.name))
                dg.issues.setdefault("through", []).extend(
                    (p, q) for p, q in zip(w.pts, w.pts[1:]) if clip_len_in_box(p, q, inner) > 1.0)
    m["wire_through_block"] = through
    m["wire_through_block_len"] = round(through_len, 1)
    gm, gdet = glyph_metrics(dg)
    m.update(gm)

    # block / label overlaps
    block_ov = 0
    allb = dg.blocks
    for i in range(len(allb)):
        for j in range(i + 1, len(allb)):
            if box_overlap_area(allb[i].box, allb[j].box) > 1:
                block_ov += 1
    m["block_overlaps"] = block_ov
    m["ink_estimated"] = len(dg.ink_notes)
    # every label Studio draws: blocks' (name and parameters), boundary ports' names, free text. They
    # collide by their text's ink; the line boxes (`boxes`) only size the drawing.
    labels = [(b.name, L.ink) for b in dg.blocks for L in b.labels] + [(L[0], L.ink) for L in dg.free_labels]
    boxes = [bb for b in dg.blocks for _t, bb in b.labels] + [bb for _t, bb in dg.free_labels]
    owners = {b.name for b in dg.blocks}
    lb_block = lb_label = lb_wire = 0
    lb_list = []
    for name, lb in labels:
        for b in dg.blocks:
            if b.name == name:
                continue
            if box_overlap_area(lb, b.box) > 1:
                lb_block += 1
                lb_list.append((name, b.name))
    for i in range(len(labels)):
        for j in range(i + 1, len(labels)):
            if labels[i][0] == labels[j][0] and labels[i][0] in owners:
                continue  # one block's own labels are laid out by its icon
            if box_overlap_area(labels[i][1], labels[j][1]) > 1:
                lb_label += 1
                lb_list.append((labels[i][0], labels[j][0]))
    lb_hit = []
    for name, lb in labels:
        hit = [w.name for w in dg.wires if any(clip_len_in_box(p, q, expand(lb, WIRE_HALF)) > 1 for p, q in zip(w.pts, w.pts[1:]))]
        if hit:
            lb_wire += 1
            lb_hit.append(f"{name} under {', '.join(sorted(set(hit)))}")
    m["label_block_overlaps"] = lb_block
    m["label_label_overlaps"] = lb_label
    m["labels_hit_by_wires"] = lb_wire

    # extents, outside routing, whitespace
    def union(boxes):
        boxes = list(boxes)
        if not boxes:
            return (0, 0, 1, 1)
        return (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))

    content = union([b.box for b in dg.blocks])
    outer, excursion = 0, 0.0
    for w in dg.wires:
        e = max(max(content[0] - p[0], p[0] - content[2], content[1] - p[1], p[1] - content[3]) for p in w.pts)
        excursion = max(excursion, e)
        if e > outside_tol:
            outer += 1
    m["outer_wires"] = outer
    m["outer_excursion_max"] = round(max(excursion, 0), 1)
    full = union([b.box for b in dg.blocks] + list(bbs) + boxes)
    W, H = full[2] - full[0], full[3] - full[1]
    m["width"] = round(W, 1)
    m["height"] = round(H, 1)
    m["aspect"] = round(W / H, 2) if H > 0 else None
    cols = max(1, int(math.ceil(W / cell)))
    rows = max(1, int(math.ceil(H / cell)))
    occ = [[False] * cols for _ in range(rows)]

    def mark_box(b):
        c0 = int((b[0] - full[0]) // cell); c1 = int(math.ceil((b[2] - full[0]) / cell))
        r0 = int((b[1] - full[1]) // cell); r1 = int(math.ceil((b[3] - full[1]) / cell))
        for r in range(max(r0, 0), min(r1, rows)):
            for c in range(max(c0, 0), min(c1, cols)):
                occ[r][c] = True

    for b in dg.blocks:
        mark_box(b.box)
    for lb in boxes:
        mark_box(lb)
    for w in dg.wires:
        for p, q in zip(w.pts, w.pts[1:]):
            n = max(1, int(seg_len(p, q) / (cell / 4)))
            for k in range(n + 1):
                x = p[0] + (q[0] - p[0]) * k / n
                y = p[1] + (q[1] - p[1]) * k / n
                r = min(rows - 1, int((y - full[1]) // cell))
                c = min(cols - 1, int((x - full[0]) // cell))
                occ[r][c] = True
    empty = sum(1 for r in occ for v in r if not v)
    m["whitespace"] = round(empty / (rows * cols), 2)
    m["largest_gap"] = round(largest_empty_square(occ) * cell, 0)
    m["block_area_frac"] = round(sum((b.box[2] - b.box[0]) * (b.box[3] - b.box[1]) for b in comps) / max(W * H, 1), 3)

    # port pitch: closest wire endpoints that belong to different nets
    endpts = [(p, w.net) for w in dg.wires for p in (w.pts[0], w.pts[-1])]
    pitch = None
    for i in range(len(endpts)):
        for j in range(i + 1, len(endpts)):
            if endpts[i][1] == endpts[j][1]:
                continue
            d = seg_len(endpts[i][0], endpts[j][0])
            if pitch is None or d < pitch:
                pitch = d
    m["min_pin_pitch"] = round(pitch, 1) if pitch is not None else None

    worst_wires = sorted(
        ((per_wire_cross[i] + 3 * bends[i] / 4, dg.wires[i].name, per_wire_cross[i], bends[i], round(lengths[i]))
         for i in range(len(dg.wires))), reverse=True)[:5]
    detail = {
        "worst_wires": [{"wire": n, "crossings": c, "bends": b, "length": L} for _s, n, c, b, L in worst_wires],
        "through_block": [f"{a} through {b}" for a, b in through_list[:20]],
        "label_overlaps": [f"{a} / {b}" for a, b in lb_list[:20]],
        "labels_hit_by_wires": lb_hit[:20],
        "ink_estimated": [f"{what}: {why}" for what, why in dg.ink_notes[:20]],
        "detours": [f"{n} ({d}x)" for d, n in sorted(detour_wires, reverse=True)[:10]],
    }
    detail.update({k: v[:20] for k, v in gdet.items()})
    return m, detail


def overlay_svg(dg, title=""):
    """A plain schematic of the measured geometry with every finding marked."""
    xs, ys = [], []
    for b in dg.blocks:
        xs += [b.box[0], b.box[2]]; ys += [b.box[1], b.box[3]]
    for w in dg.wires:
        xs += [p[0] for p in w.pts]; ys += [p[1] for p in w.pts]
    for _t, lb in dg.free_labels:
        xs += [lb[0], lb[2]]; ys += [lb[1], lb[3]]
    if not xs:
        return "<svg xmlns='http://www.w3.org/2000/svg'/>"
    pad = 60
    x0, y0, x1, y1 = min(xs) - pad, min(ys) - pad - 40, max(xs) + pad, max(ys) + pad
    sw = max(x1 - x0, y1 - y0) / 1000.0
    esc = lambda t: t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    o = [f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='{x0:g} {y0:g} {x1 - x0:g} {y1 - y0:g}' "
         f"width='{min(2400, int((x1 - x0) / sw * 1.6))}' height='{min(2400, int((y1 - y0) / sw * 1.6))}'>",
         f"<rect x='{x0:g}' y='{y0:g}' width='{x1 - x0:g}' height='{y1 - y0:g}' fill='white'/>",
         f"<text x='{x0 + pad / 2:g}' y='{y0 + 30 * sw:g}' font-size='{12 * sw:g}' font-family='sans-serif'>{esc(title)}  "
         "(red dot = crossing, magenta = false junction, red line = through a block or glyph, orange = shared run, "
         "orange box = glyph finding (dashed: unwired glyphs piled up), purple box = covered label (dashed: by its own block's glyph, the child's icon), orange ring = junction on a glyph, green = near-diagonal)</text>"]
    for b in dg.blocks:
        x, y, X, Y = b.frame or b.box
        # the placement box dashed; the icon as Studio draws it (ports: their glyph, below) solid
        o.append(f"<rect x='{x:g}' y='{y:g}' width='{X - x:g}' height='{Y - y:g}' fill='none' stroke='#999' "
                 f"stroke-dasharray='{4 * sw:g}' stroke-width='{0.8 * sw:g}'/>")
        if not b.is_port:
            x, y, X, Y = b.body or b.box
            o.append(f"<rect x='{x:g}' y='{y:g}' width='{X - x:g}' height='{Y - y:g}' fill='#f4f4f4' stroke='#333' stroke-width='{1.2 * sw:g}'/>")
        x, y, X, Y = b.box
        for txt, (lx, ly, LX, LY) in b.labels:
            o.append(f"<rect x='{lx:g}' y='{ly:g}' width='{LX - lx:g}' height='{LY - ly:g}' fill='none' stroke='#9a9' "
                     f"stroke-dasharray='{3 * sw:g}' stroke-width='{0.8 * sw:g}'/>")
            o.append(f"<text x='{(lx + LX) / 2:g}' y='{(ly + LY) / 2:g}' font-size='{(LY - ly) * 0.8:g}' text-anchor='middle' "
                     f"dominant-baseline='central' font-family='sans-serif' fill='#353'>{esc(txt)}</text>")
        if b.is_port:
            o.append(f"<text x='{(x + X) / 2:g}' y='{(y + Y) / 2:g}' font-size='{max(8 * sw, (Y - y) * 0.3):g}' text-anchor='middle' "
                     f"dominant-baseline='central' font-family='sans-serif' fill='#558'>{esc(b.name)}</text>")
    for g in dg.glyphs:
        pts = " ".join(f"{x:g},{y:g}" for x, y in g.outline())
        o.append(f"<polygon points='{pts}' fill='#dde' stroke='#558' stroke-width='{0.8 * sw:g}'/>")
    for x, y, X, Y in dg.issues.get("glyph_unwired", []):
        o.append(f"<rect x='{x:g}' y='{y:g}' width='{X - x:g}' height='{Y - y:g}' fill='none' stroke='#e07000' "
                 f"stroke-dasharray='{2 * sw:g}' stroke-width='{1.5 * sw:g}'/>")
    for x, y, X, Y in dg.issues.get("glyph", []):
        o.append(f"<rect x='{x:g}' y='{y:g}' width='{X - x:g}' height='{Y - y:g}' fill='none' stroke='#e07000' stroke-width='{2.5 * sw:g}'/>")
    for x, y, X, Y in dg.issues.get("label_icon", []):
        o.append(f"<rect x='{x:g}' y='{y:g}' width='{X - x:g}' height='{Y - y:g}' fill='none' stroke='#c0c' "
                 f"stroke-dasharray='{2 * sw:g}' stroke-width='{1.5 * sw:g}'/>")
    for x, y, X, Y in dg.issues.get("label", []):
        o.append(f"<rect x='{x:g}' y='{y:g}' width='{X - x:g}' height='{Y - y:g}' fill='none' stroke='#c0c' stroke-width='{2 * sw:g}'/>")
    for t, (lx, ly, LX, LY) in dg.free_labels:
        o.append(f"<text x='{(lx + LX) / 2:g}' y='{(ly + LY) / 2:g}' font-size='{(LY - ly) * 0.8:g}' text-anchor='middle' "
                 f"dominant-baseline='central' font-family='sans-serif' fill='#777'>{esc(t)}</text>")
    for w in dg.wires:
        d = " ".join(f"{'M' if i == 0 else 'L'}{x:g},{y:g}" for i, (x, y) in enumerate(w.pts))
        o.append(f"<path d='{d}' fill='none' stroke='#2a4d9b' stroke-width='{1.5 * sw:g}' stroke-opacity='0.75'/>")
    for p, q in dg.issues.get("through", []):
        o.append(f"<line x1='{p[0]:g}' y1='{p[1]:g}' x2='{q[0]:g}' y2='{q[1]:g}' stroke='red' stroke-width='{3 * sw:g}'/>")
    for p1, p2, p3, p4 in dg.issues.get("overlap", []):
        for a, b in ((p1, p2), (p3, p4)):
            o.append(f"<line x1='{a[0]:g}' y1='{a[1]:g}' x2='{b[0]:g}' y2='{b[1]:g}' stroke='orange' stroke-width='{3 * sw:g}' stroke-opacity='0.6'/>")
    for x, y in dg.issues.get("cross", []):
        o.append(f"<circle cx='{x:g}' cy='{y:g}' r='{3.5 * sw:g}' fill='red'/>")
    for x, y in dg.issues.get("touch", []):
        o.append(f"<circle cx='{x:g}' cy='{y:g}' r='{5 * sw:g}' fill='none' stroke='magenta' stroke-width='{2 * sw:g}'/>")
    for x, y in dg.junctions:
        o.append(f"<circle cx='{x:g}' cy='{y:g}' r='{3 * sw:g}' fill='#2a4d9b'/>")
    for x, y in dg.issues.get("junction", []):
        o.append(f"<circle cx='{x:g}' cy='{y:g}' r='{7 * sw:g}' fill='none' stroke='#e07000' stroke-width='{2 * sw:g}'/>")
    for p, q in dg.issues.get("near_diagonal", []):
        o.append(f"<line x1='{p[0]:g}' y1='{p[1]:g}' x2='{q[0]:g}' y2='{q[1]:g}' stroke='#0a0' stroke-width='{3 * sw:g}'/>")
    o.append("</svg>")
    return "\n".join(o)


# Badness weights, per finding (see README, "Badness"). Roughly: how hard the defect is to see past
# when reading the diagram. 20: the drawing is wrong (wires sharing a run, touching another net, through
# a block, diagonal; blocks on blocks). 10: a connector glyph is misdrawn (on another glyph or icon,
# away from its block, crossed by another net's wire or a junction dot). 5: a connect() with no route
# (Dyad invents one), a glyph past the end of its side, a label under a glyph. 3: a crossing. 2: label
# collisions, wires leaving the diagram, detours. 1: a near-diagonal (a hair off the axis, which shows
# as a jag only when zoomed in), and a pair of unwired glyphs piled up or a label under its own block's
# glyph by the child's icon (visible, but only the child component can fix it). Bends and jogs cost a fraction.
WEIGHTS = {
    "overlap_runs": 20, "diagonal_segments": 20, "wire_through_block": 20, "false_junctions": 20, "block_overlaps": 20,
    "glyph_overlap": 10, "glyph_detached": 10, "wire_thru_glyph": 10, "junction_on_glyph": 10,
    "unrouted_connects": 5, "glyph_overhang": 5, "label_covered": 5,
    "crossings": 3,
    "label_block_overlaps": 2, "label_label_overlaps": 2, "outer_wires": 2, "detour_wires": 2,
    "near_diagonal": 1, "glyph_overlap_unwired": 1, "label_covered_by_icon": 1,
    "labels_hit_by_wires": 0.5, "micro_jogs": 0.5, "bends_total": 0.25,
}


def badness(m):
    s = sum(w * (m.get(k) or 0) for k, w in WEIGHTS.items())
    if m.get("whitespace", 0) > 0.6:
        s += 100 * (m["whitespace"] - 0.6)
    if m.get("min_pin_pitch") is not None and m["min_pin_pitch"] < 10:
        s += 10
    return round(s, 1)


# ---------------------------------------------------------------------------
# dyad CLI and dyad-layout


def run_dyad(dyad, args, cwd, timeout=1800):
    # stdout goes through a file: through a pipe, `dyad render` can exit before
    # the whole SVG is flushed.
    import tempfile
    with tempfile.TemporaryFile("w+") as out:
        p = subprocess.run([dyad] + args, cwd=cwd, stdout=out, stderr=subprocess.PIPE, text=True, timeout=timeout)
        out.seek(0)
        return p.returncode, out.read(), p.stderr


ERROR_RE = re.compile(r"\bERROR\b|^\s*(?:error|Error|fatal)\b\s*:")


def primary_error(log, context=12):
    """The first error in a dyad/Julia log and its message, without the stack trace.

    Julia prints the cause first (`ERROR: ...` and the lines after it) and
    then pages of stack trace and follow-on failures, so the first ERROR is the
    one that matters. Falls back to the last lines when there is no ERROR.
    """
    lines = [l.rstrip() for l in log.splitlines() if not l.startswith("Julia stderr (exit 0)")]
    for i, l in enumerate(lines):
        if ERROR_RE.search(l):
            out = [l]
            for nxt in lines[i + 1: i + 1 + context]:
                if not nxt.strip() or nxt.lstrip().startswith(("Stacktrace:", "[1]", "in expression starting")):
                    break
                out.append(nxt)
            return "\n".join(out)
    tail = [l for l in lines if l.strip()]
    return "\n".join(tail[-8:])


def dyad_failure(cache, q, step, log):
    """Save the full log next to the report and return (primary error, log path)."""
    path = os.path.join(cache, f"{q}.{step}.log")
    with open(path, "w") as f:
        f.write(log)
    return primary_error(log), path


def first_line(text):
    """One-line summary of an error for lists: its first line naming an error, else its first line."""
    lines = [l for l in (text or "").splitlines() if l.strip()]
    return next((l for l in lines if "rror" in l), lines[0] if lines else "")


# dyad-layout's D4 states, names and maths as in its rust/core/src/d4.rs
# (apply_d4): the flip comes before the rotation, flipH negates y, flipV
# negates x, and r90 maps (x, y) to (-y, x).
D4_PTS = {
    "identity": lambda x, y: (x, y), "r90": lambda x, y: (-y, x), "r180": lambda x, y: (-x, -y),
    "r270": lambda x, y: (y, -x), "flipH": lambda x, y: (x, -y), "flipV": lambda x, y: (-x, y),
    "flipH_r90": lambda x, y: (y, x), "flipV_r90": lambda x, y: (-y, -x),
}


def apply_d4(state, x, y):
    try:
        return D4_PTS[state](x, y)
    except KeyError:
        raise ValueError(f"unknown dyad-layout D4 state {state!r} (expected one of {', '.join(D4_PTS)})") from None


def connector_offset(comp, connector_id, d4):
    """Offset of a component connector from the component centre, after its D4 transform."""
    cd = next((k for k in comp["connectors"] if k["id"] == connector_id), None)
    if cd is None:
        return None
    hw, hh = comp["width"] / 2, comp["height"] / 2
    e, t = cd["edge"], cd["position"]
    lx, ly = {"top": (t * hw, -hh), "bottom": (t * hw, hh), "left": (-hw, t * hh), "right": (hw, t * hh)}[e]
    return apply_d4(d4, lx, ly)


def problem_to_layout(prob):
    """A dyad-layout/problem@1 file -> the LayoutProblem the WASM entry points take."""
    st = prob["structure"]
    hints = prob.get("hints", {})
    comps = []
    for c in st["components"]:
        c = dict(c)
        imp = hints.get("components", {}).get(c["id"], {}).get("importance")
        if imp is not None:
            c["importance"] = imp
        comps.append(c)
    conns = []
    for c in st["connections"]:
        c = dict(c)
        imp = hints.get("connections", {}).get(c["id"], {}).get("importance")
        if imp is not None:
            c["importance"] = imp
        conns.append(c)
    return {
        "gridColumns": prob["settings"]["gridColumns"], "gridRows": prob["settings"]["gridRows"],
        "components": comps, "canvasConnectors": [dict(c) for c in st["canvasConnectors"]],
        "connections": conns,
    }


def solution_from_drawing(prob, dg):
    """Express the drawn diagram as a dyad-layout LayoutSolution (half-grid units).

    Placements are the extracted seeds (where the diagram draws each block);
    routes are the drawn wire polylines, each matched to the problem
    connection whose two connector positions are nearest its two ends.
    """
    st = prob["structure"]
    hints = prob.get("hints", {}).get("components", {})
    pins = {c["kind"]["componentId"]: c["kind"]["at"] for c in prob.get("constraints", []) if c["kind"]["kind"] == "pin"}
    by_name = {b.name: b for b in dg.blocks}
    # origin of the half-grid in Dyad units, from blocks present in both
    offs = []
    for c in st["components"]:
        h = hints.get(c["id"], {}).get("initialPosition")
        b = by_name.get(c["id"])
        if h and b:
            offs.append(((b.box[0] + b.box[2]) / 2 / HALF_SQUARE - h["x"], (b.box[1] + b.box[3]) / 2 / HALF_SQUARE - h["y"]))
    if offs:
        offs.sort()
        ox = sorted(o[0] for o in offs)[len(offs) // 2]
        oy = sorted(o[1] for o in offs)[len(offs) // 2]
        ox, oy = round(ox), round(oy)
    else:
        ox = oy = 0
    tohg = lambda p: (p[0] / HALF_SQUARE - ox, p[1] / HALF_SQUARE - oy)
    placements, comp_at = [], {}
    for c in st["components"]:
        h = hints.get(c["id"], {})
        b = by_name.get(c["id"])
        if b:
            ctr = tohg(((b.box[0] + b.box[2]) / 2, (b.box[1] + b.box[3]) / 2))
        elif c["id"] in pins:
            ctr = (pins[c["id"]]["x"], pins[c["id"]]["y"])
        elif "initialPosition" in h:
            ctr = (h["initialPosition"]["x"], h["initialPosition"]["y"])
        else:
            continue
        d4 = h.get("initialD4State", "identity")
        apply_d4(d4, 0, 0)  # reject unknown states here rather than mis-place every connector
        placements.append({"componentId": c["id"], "center": {"x": ctr[0], "y": ctr[1]}, "d4State": d4})
        comp_at[c["id"]] = (c, ctr, d4)
    canvas = []
    canvas_at = {}
    for k in st["canvasConnectors"]:
        b = by_name.get(k["id"])
        if b:
            pos = tohg(((b.box[0] + b.box[2]) / 2, (b.box[1] + b.box[3]) / 2))
        elif k["id"] in pins:
            pos = (pins[k["id"]]["x"], pins[k["id"]]["y"])
        else:
            continue
        canvas.append({"connectorId": k["id"], "position": {"x": pos[0], "y": pos[1]}})
        canvas_at[k["id"]] = pos

    def ref_pos(r):
        if r["type"] == "canvas":
            return canvas_at.get(r["connectorId"])
        got = comp_at.get(r["componentId"])
        if not got:
            return None
        c, ctr, d4 = got
        if c["width"] == 0 and c["height"] == 0:
            return ctr
        off = connector_offset(c, r["connectorId"], d4)
        if off is None:
            return ctr
        return (ctr[0] + off[0], ctr[1] + off[1])

    wires = [[tohg(p) for p in w.pts] for w in dg.wires]
    cands = []
    for ci, c in enumerate(st["connections"]):
        a, b = ref_pos(c["from"]), ref_pos(c["to"])
        if a is None or b is None:
            continue
        for wi, w in enumerate(wires):
            f = seg_len(a, w[0]) + seg_len(b, w[-1])
            r = seg_len(a, w[-1]) + seg_len(b, w[0])
            cands.append((min(f, r), ci, wi, r < f))
    cands.sort()
    used_c, used_w, routed = set(), set(), {}
    for cost, ci, wi, rev in cands:
        if ci in used_c or wi in used_w or cost > 6:
            continue
        used_c.add(ci)
        used_w.add(wi)
        pts = wires[wi][::-1] if rev else wires[wi]
        routed[ci] = pts
    # Only drawn routes are scored. A connection no drawn wire matched gets no
    # route at all: inventing one (say, a straight line between its ends) would
    # be scored as if Dyad had drawn it.
    rcs, unmatched = [], []
    for ci, c in enumerate(st["connections"]):
        pts = routed.get(ci)
        if pts is None:
            unmatched.append(c["id"])
            continue
        rcs.append({"connectionId": c["id"], "waypoints": [{"x": x, "y": y} for x, y in pts]})
    zero = {"crossings": 0, "totalLength": 0, "centralityPenalty": 0, "hintPenalty": 0, "turns": 0, "spacingPenalty": 0, "value": 0}
    sol = {"componentPlacements": placements, "canvasConnectorPlacements": canvas, "routedConnections": rcs, "objective": zero}
    return sol, unmatched


# dyad-layout WASM builds this tool has been checked against: release tag ->
# the sha256 of the files dyad_layout_score.mjs loads, and the string the
# WASM's version() returns. v0.1.1 (commit bb4582c) is what the Dyad 3.5.0 CLI
# ships; its crate version was never bumped, so it reports 0.0.1.
PINNED_SCORERS = {
    "v0.1.1": {
        "reports": "0.0.1",
        "sha256": {
            "dyad_layout_wasm_bg.wasm": "75dd69d9fc2bc213b073ac8f2b86e05c3af3d02ba34cd67fb8665cc3049bb3db",
            "dyad_layout_wasm.js": "867d0bf744646d3bac1e6b1471d8642ed0fe7f9727aaa68c9451dedb71d6ae01",
        },
    },
}


def check_scorer(wasm_dir, allow_unpinned=False, node="node"):
    """Check the dyad-layout scorer before any diagram is measured.

    Returns {"version", "release", "pinned", "sha256"}, plus "error" if it cannot be used. The files must match a
    pinned build unless allow_unpinned; the version the WASM reports must
    match the pin.
    """
    import hashlib
    info = {"dir": os.path.abspath(wasm_dir)}
    sums = {}
    for fn in ("dyad_layout_wasm_bg.wasm", "dyad_layout_wasm.js"):
        path = os.path.join(wasm_dir, fn)
        if not os.path.isfile(path):
            return dict(info, error=f"dyad-layout scorer not found: {path} is missing (give the wasm/pkg directory of dyad-layout v0.1.1)")
        with open(path, "rb") as f:
            sums[fn] = hashlib.sha256(f.read()).hexdigest()
    info["sha256"] = sums
    pinned = next((tag for tag, pin in PINNED_SCORERS.items() if pin["sha256"] == sums), None)
    info["pinned"] = pinned is not None
    info["release"] = pinned
    if pinned is None and not allow_unpinned:
        return dict(info, error=f"dyad-layout scorer in {wasm_dir} does not match a pinned build "
                                f"({', '.join(PINNED_SCORERS)}); "
                                "use --allow-unpinned-scorer to score with it anyway")
    if not shutil.which(node):
        return dict(info, error=f"Node is needed for --dyad-layout-wasm and was not found ({node})")
    try:
        p = subprocess.run([node, os.path.join(HERE, "dyad_layout_score.mjs"), "--version"],
                           input=json.dumps({"wasmDir": info["dir"]}), capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError) as e:
        return dict(info, error=f"cannot run the dyad-layout scorer: {e}")
    if p.returncode != 0:
        return dict(info, error="the dyad-layout scorer failed to load: " + primary_error(p.stderr))
    info["version"] = p.stdout.strip()
    if pinned is not None and info["version"] != PINNED_SCORERS[pinned]["reports"]:
        return dict(info, error=f"dyad-layout scorer reports version {info['version']}, but its files are the "
                                f"pinned {pinned} build, which reports {PINNED_SCORERS[pinned]['reports']}")
    return info


def score_with_wasm(wasm_dir, prob, dg, options, node="node"):
    lp = problem_to_layout(prob)
    sol, unmatched = solution_from_drawing(prob, dg)
    total = len(prob["structure"]["connections"])
    payload = {"wasmDir": os.path.abspath(wasm_dir), "problem": lp, "solution": sol, "options": options or {}}
    base = {"connections": total, "unmatchedConnections": len(unmatched), "unmatchedIds": unmatched,
            # partial: the drawn-route score covers only the matched connections
            "status": "partial" if unmatched else "complete"}
    if total and len(unmatched) == total:
        base["status"] = "unavailable"
    try:
        p = subprocess.run([node, os.path.join(HERE, "dyad_layout_score.mjs")], input=json.dumps(payload),
                           capture_output=True, text=True, timeout=600)
    except (OSError, subprocess.SubprocessError) as e:
        return dict(base, status="unavailable", error=f"cannot run the dyad-layout scorer: {e}")
    if p.returncode != 0:
        return dict(base, status="unavailable", error=primary_error(p.stderr))
    out = json.loads(p.stdout)
    if base["status"] == "unavailable":
        out.pop("existing", None)  # nothing drawn was matched: there is no drawn geometry to score
    out.update(base)
    return out


SOLVE_RE = re.compile(r"Solved: (\d+) crossings, wire length ([\d.]+), (\d+) turns")


def summarize_solve(stderr, sol):
    s = {}
    m = SOLVE_RE.search(stderr)
    if m:
        s.update(crossings=int(m.group(1)), wire_length=float(m.group(2)), turns=int(m.group(3)))
    m = re.search(r"(\d+) connection\(s\) could not be routed legally", stderr)
    s["illegal_routes"] = int(m.group(1)) if m else 0
    if sol:
        s["dropped"] = sol.get("dropped", [])
        s["unsatisfiable"] = sol.get("unsatisfiable", [])
        s["warnings"] = sol.get("warnings", [])
        s["objective"] = sol.get("solution", {}).get("objective")
    return s


# ---------------------------------------------------------------------------
# reporting

TABLE_COLS = [
    ("badness", "bad"), ("wires", "wires"), ("crossings", "X"), ("false_junctions", "T"),
    ("overlap_runs", "ovl"), ("wire_through_block", "thru"), ("wire_thru_glyph", "thru glyph"), ("diagonal_segments", "diag"),
    ("near_diagonal", "near diag"), ("glyph_overlap", "g ovl"), ("glyph_overlap_unwired", "g ovl unw"),
    ("glyph_detached", "g detach"), ("glyph_overhang", "g hang"),
    ("label_covered", "lbl/glyph"), ("label_covered_by_icon", "lbl/icon"), ("junction_on_glyph", "jct/glyph"),
    ("unrouted_connects", "unrt"), ("block_overlaps", "blk ovl"), ("label_block_overlaps", "lbl/blk"), ("label_label_overlaps", "lbl/lbl"),
    ("labels_hit_by_wires", "lbl/wire"), ("bends_mean", "bends/w"), ("bends_max", "bends max"),
    ("micro_jogs", "jogs"), ("wire_len_total", "len"), ("wire_len_max", "len max"), ("detour_wires", "detours"),
    ("outer_wires", "outer"), ("whitespace", "white"), ("largest_gap", "gap"), ("aspect", "aspect"),
    ("min_pin_pitch", "pitch"), ("ink_estimated", "ink est"),
]
DL_COLS = [("dl_crossings", "dl X"), ("dl_illegal", "dl illegal"), ("dl_turns", "dl turns"),
           ("dl_spacing", "dl spacing"), ("dl_unmatched", "dl unmatched"),
           ("dl_rerouted_crossings", "reroute X"), ("dl_rerouted_illegal", "reroute illegal")]
# drawn-route scores that only cover part of the diagram are marked in the table
DL_PARTIAL = {"dl_crossings", "dl_illegal", "dl_turns", "dl_spacing"}


def fmt(v):
    if v is None:
        return "–"
    if isinstance(v, float):
        return f"{v:g}"
    return str(v)


def markdown(rows, sort_key):
    cols = list(TABLE_COLS)
    if any("dl_status" in r["metrics"] for r in rows):
        cols += DL_COLS

    def cell(m, k):
        v = fmt(m.get(k))
        if k in DL_PARTIAL and m.get("dl_status") == "partial" and m.get(k) is not None:
            v += "*"
        return v

    rows = sorted(rows, key=lambda r: (-(r["metrics"].get(sort_key) or 0) if isinstance(r["metrics"].get(sort_key), (int, float)) else 0))
    out = ["| diagram | " + " | ".join(h for _, h in cols) + " |", "|---|" + "---:|" * len(cols)]
    for r in rows:
        out.append(f"| {r['diagram']} | " + " | ".join(cell(r["metrics"], k) for k, _ in cols) + " |")
    return "\n".join(out)


def scorer_section(scorer, rows):
    """Markdown lines on the dyad-layout scorer: which build ran, or why it did not."""
    if not scorer:
        return []
    out = ["", "## dyad-layout scorer", ""]
    if "error" in scorer:
        out.append(f"Not run: {scorer['error']}. The geometry metrics above do not depend on it.")
        return out
    out.append(f"dyad-layout {scorer.get('release') or 'build'} (reports version {scorer.get('version')}) from `{scorer['dir']}`"
               + ("" if scorer.get("pinned") else " (**not a pinned build**: checksums differ from every known release)") + ".")
    partial = [r for r in rows if r.get("dyad_layout", {}).get("status") == "partial"]
    missing = [r for r in rows if r.get("dyad_layout", {}).get("status") == "unavailable" or r.get("extract_error")]
    reroute_failed = [r for r in rows if r.get("dyad_layout", {}).get("reroutedError")]
    if partial:
        out += ["", "Partial scores (marked * in the table): the drawn-route score covers only the connections a drawn wire was "
                "matched to. Unmatched connections are not scored, and no route is invented for them.", ""]
        out += [f"- {r['diagram']}: {r['dyad_layout']['unmatchedConnections']} of {r['dyad_layout']['connections']} "
                "connections unmatched" for r in partial]
    if missing:
        out += ["", "Not scored:", ""]
        for r in missing:
            why = r.get("dyad_layout", {}).get("error") or (
                "all connections unmatched" if r.get("dyad_layout", {}).get("status") == "unavailable" else "")
            if r.get("extract_error"):
                why = f"`dyad layout extract` failed: {first_line(r['extract_error'])} (log: `{r.get('extract_log')}`)"
            out.append(f"- {r['diagram']}: {first_line(why)}")
    if reroute_failed:
        out += ["", "Re-route failed (no `reroute` columns; the drawn-route score stands):", ""]
        out += [f"- {r['diagram']}: {first_line(r['dyad_layout']['reroutedError'])}" for r in reroute_failed]
    return out


LEGEND = """Columns: bad = composite badness (see README); X = wire crossings between different nets;
T = false junctions (a wire end or bend touching another net's wire); ovl = collinear runs shared by
two different nets; thru = (wire, block) pairs where the wire passes through a block; thru glyph = (wire, glyph)
pairs where the wire crosses a connector glyph it is not wired to; diag = non-orthogonal segments; near diag =
segments a hair (0.001 to 0.5 units) off the axis; g ovl = connector glyphs that overlap or touch another glyph or
lie on another block's icon; g ovl unw = unwired glyphs of one block piled up by its icon; g detach = a block's glyphs away from its icon as Studio draws it; g hang = glyphs
past the end of their side of the icon, or sticking far out of it; lbl/glyph = labels covered by a glyph; lbl/icon = labels under their own block's glyph,
as at the block's default size (the child's icon);
jct/glyph = junction dots on a glyph; unrt = connect() statements with no route metadata; lbl/blk,
lbl/lbl, lbl/wire = label overlaps; bends/w, bends max = bends per wire; jogs = interior segments
shorter than 10 units; len = Dyad units; detours = wires >= 2.5x their Manhattan distance;
outer = wires leaving the blocks' bounding box by > 30 units; white = fraction of 50x50 cells with
no block, label or wire; gap = side of the largest empty square; pitch = closest pins on different
nets; ink est = icons whose drawn ink could only be estimated (see "Estimated icon ink"). dl X / dl illegal / dl turns / dl spacing = dyad-layout's own objective on the drawn geometry;
dl unmatched = problem connections no drawn wire was matched to (a * marks scores that leave them out);
reroute X / reroute illegal = dyad-layout's router re-routing the same placements."""


def worst_first(rows, n):
    out = []
    for r in sorted(rows, key=lambda r: -r["metrics"]["badness"])[:n]:
        m = r["metrics"]
        why = []
        for k, label in (("unrouted_connects", "unrouted connects"), ("overlap_runs", "shared runs"),
                         ("false_junctions", "false junctions"), ("wire_through_block", "wires through blocks"),
                         ("wire_thru_glyph", "wires through glyphs"), ("junction_on_glyph", "junctions on glyphs"),
                         ("glyph_overlap", "overlapping glyphs"), ("glyph_detached", "detached glyphs"),
                         ("glyph_overlap_unwired", "unwired glyphs piled up"),
                         ("label_covered_by_icon", "labels under their own block's glyphs (child icon)"),
                         ("glyph_overhang", "overhanging glyphs"), ("label_covered", "labels under glyphs"),
                         ("near_diagonal", "near-diagonal segments"), ("block_overlaps", "overlapping blocks/ports"),
                         ("diagonal_segments", "diagonal segments"), ("crossings", "crossings"),
                         ("label_block_overlaps", "labels on blocks"), ("label_label_overlaps", "labels on labels"),
                         ("outer_wires", "outer wires"), ("detour_wires", "detours")):
            if m.get(k):
                why.append(f"{m[k]} {label}")
        if m.get("whitespace", 0) > 0.6:
            why.append(f"{int(100 * m['whitespace'])}% empty")
        if m.get("min_pin_pitch") is not None and m["min_pin_pitch"] < 10:
            why.append(f"pins {m['min_pin_pitch']} units apart")
        out.append(f"1. **{r['diagram']}** (badness {m['badness']}): " + ", ".join(why))
    return "\n".join(out)


def analyze_component(lib, libdir, sc, args, cache):
    q = sc.qualified(lib)
    row = {"diagram": q, "library": lib, "component": sc.name, "kind": sc.kind,
           "file": os.path.relpath(sc.file, libdir), "metrics": {}, "detail": {}}
    svg_path = os.path.join(cache, q + ".svg")
    if args.reuse and os.path.exists(svg_path) and os.path.getsize(svg_path) > 0:
        svg = open(svg_path).read()
    else:
        rc, out, err = run_dyad(args.dyad, ["render", q, "--dir", "."], libdir)
        if rc != 0 or not out.strip().startswith("<") or not out.rstrip().endswith("</svg>"):
            log = err if out.strip().startswith("<") else err + ("\n--- stdout ---\n" + out if out.strip() else "")
            msg, row["error_log"] = dyad_failure(cache, q, "render", log)
            row["error"] = "render failed: " + msg
            return row
        svg = out
        open(svg_path, "w").write(svg)
    src_boxes = instance_boxes(sc.block)
    try:
        dg = parse_svg(svg, src_boxes, instance_connectors(libdir, sc.block))
    except ET.ParseError as e:
        row["error"] = f"cannot parse the rendered SVG: {e}"
        return row
    except UnsupportedSVG as e:
        row["error"] = f"unsupported SVG structure: {e}"
        return row
    m, detail = compute_metrics(dg)
    with open(os.path.join(cache, q + ".overlay.svg"), "w") as f:
        f.write(overlay_svg(dg, q))
    total, missing, arms, looped = connect_route_status(sc.block)
    m["connects"] = total
    m["loop_connects"] = looped
    m["unrouted_connects"] = missing
    row["detail"] = detail
    prob = None
    if args.extract or args.dyad_layout_wasm or args.solve:
        ppath = os.path.join(cache, q + ".problem.json")
        if not (args.reuse and os.path.exists(ppath)):
            rc, _out, err = run_dyad(args.dyad, ["layout", "extract", q, "--dir", ".", "-o", ppath], libdir)
            if rc != 0:
                row["extract_error"], row["extract_log"] = dyad_failure(cache, q, "extract", err)
        if os.path.exists(ppath):
            prob = json.load(open(ppath))
    scorer = getattr(args, "scorer", None) or {}
    if args.dyad_layout_wasm and "error" in scorer:
        row["dyad_layout"] = {"status": "unavailable", "error": scorer["error"]}
        m["dl_status"] = "unavailable"
    elif args.dyad_layout_wasm:
        if prob is None:
            row["dyad_layout"] = {"status": "unavailable", "error": "no extracted problem to score against"}
            m["dl_status"] = "unavailable"
        else:
            try:
                sc_out = score_with_wasm(args.dyad_layout_wasm, prob, dg, prob["settings"].get("options"))
            except Exception as e:  # the geometry above stands even if scoring breaks
                sc_out = {"status": "unavailable", "error": f"{type(e).__name__}: {e}"}
            sc_out["scorer"] = {k: scorer.get(k) for k in ("release", "version", "pinned", "sha256")}
            row["dyad_layout"] = sc_out
            m["dl_status"] = sc_out.get("status")
            m["dl_unmatched"] = sc_out.get("unmatchedConnections")
            if "existing" in sc_out:
                o = sc_out["existing"]["objective"]
                m["dl_crossings"] = o.get("crossings")
                m["dl_illegal"] = o.get("illegalRoutes", 0)
                m["dl_turns"] = o.get("turns")
                m["dl_spacing"] = o.get("spacingPenalty")
            if "rerouted" in sc_out:
                o = sc_out["rerouted"]["objective"]
                m["dl_rerouted_crossings"] = o.get("crossings")
                m["dl_rerouted_illegal"] = o.get("illegalRoutes", 0)
    if prob and args.solve:
        spath = os.path.join(cache, q + ".solution.json")
        rc, _out, err = run_dyad(args.dyad, ["layout", "solve", "-i", os.path.join(cache, q + ".problem.json"), "-o", spath], libdir)
        sol = json.load(open(spath)) if os.path.exists(spath) else None
        row["fresh_solve"] = summarize_solve(err, sol)
        if rc != 0:
            row["fresh_solve"]["error"], row["fresh_solve"]["log"] = dyad_failure(cache, q, "solve", err)
    m["badness"] = badness(m)
    row["metrics"] = m
    return row


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dir", action="append", default=[], help="Dyad library directory (Project.toml + dyad/); repeatable")
    ap.add_argument("--root", help="analyse every library directly below this directory")
    ap.add_argument("-c", "--component", action="append", default=[],
                    help="component name or qualified name (default: every component with a diagram)")
    ap.add_argument("--skip-tests", action="store_true", help="skip test/example components")
    ap.add_argument("--dyad", default=os.environ.get("DYAD", "dyad"), help="dyad CLI (default $DYAD or dyad)")
    ap.add_argument("-o", "--out", default="layout-report-out", help="output directory")
    ap.add_argument("--extract", action="store_true", help="also run `dyad layout extract` (cached in the output dir)")
    ap.add_argument("--dyad-layout-wasm", metavar="DIR",
                    help="dyad-layout wasm/pkg directory: score the drawn geometry with dyad-layout's own objective")
    ap.add_argument("--allow-unpinned-scorer", action="store_true",
                    help="score with a dyad-layout WASM build whose checksums match no pinned release")
    ap.add_argument("--solve", action="store_true", help="also run `dyad layout solve` on the raw extracted problem")
    ap.add_argument("--reuse", action="store_true", help="reuse cached renders/problems in the output dir")
    ap.add_argument("--svg", action="append", default=[], help="analyse a rendered SVG file directly (no dyad needed)")
    ap.add_argument("--sort", default="badness", help="metric to sort the markdown table by")
    ap.add_argument("--worst", type=int, default=10, help="length of the worst-first list")
    ap.add_argument("--allow-failures", action="store_true",
                    help="exit 0 even if some diagram could not be rendered or measured (default: exit 1)")
    ap.add_argument("-j", "--jobs", type=int, default=1,
                    help="libraries analysed in parallel (components of one library always run in sequence)")
    args = ap.parse_args(argv)

    libs = list(args.dir)
    if args.root:
        for d in sorted(os.listdir(args.root)):
            p = os.path.join(args.root, d)
            if os.path.isfile(os.path.join(p, "Project.toml")) and os.path.isdir(os.path.join(p, "dyad")):
                libs.append(p)
    if not libs and not args.svg:
        ap.error("give --dir, --root or --svg")
    if libs and not shutil.which(args.dyad) and not os.path.exists(args.dyad):
        ap.error(f"dyad CLI not found: {args.dyad}")
    args.out = os.path.abspath(args.out)
    os.makedirs(args.out, exist_ok=True)
    cache = os.path.join(args.out, "cache")
    os.makedirs(cache, exist_ok=True)

    args.scorer = None
    if args.dyad_layout_wasm:
        args.scorer = check_scorer(args.dyad_layout_wasm, args.allow_unpinned_scorer)
        if "error" in args.scorer:
            print(f"[layout-report] dyad-layout scoring disabled: {args.scorer['error']}", file=sys.stderr)

    rows = []
    for svgf in args.svg:
        try:
            with open(svgf) as f:
                dg = parse_svg(f.read())
        except (ET.ParseError, UnsupportedSVG) as e:
            rows.append({"diagram": os.path.basename(svgf), "error": f"cannot measure {svgf}: {e}"})
            continue
        m, detail = compute_metrics(dg)
        with open(os.path.join(cache, os.path.basename(svgf) + ".overlay.svg"), "w") as f:
            f.write(overlay_svg(dg, os.path.basename(svgf)))
        m["badness"] = badness(m)
        rows.append({"diagram": os.path.basename(svgf), "metrics": m, "detail": detail})
    def run_library(libdir):
        libdir = os.path.abspath(libdir)
        lib = library_name(libdir)
        out = []
        for sc in find_components(libdir):
            if args.skip_tests and sc.kind:
                continue
            if args.component and not any(c in (sc.name, sc.qualified(lib), sc.qualified("")) for c in args.component):
                continue
            print(f"[layout-report] {sc.qualified(lib)}", file=sys.stderr)
            try:
                row = analyze_component(lib, libdir, sc, args, cache)
            except Exception as e:  # keep going: one odd diagram must not lose the rest
                row = {"diagram": sc.qualified(lib), "error": f"{type(e).__name__}: {e}"}
            if "error" in row:
                print(f"  {sc.qualified(lib)}: {first_line(row['error'])}", file=sys.stderr)
            out.append(row)
        return out

    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        for got in ex.map(run_library, libs):
            rows.extend(got)

    ok = [r for r in rows if r.get("metrics")]
    failed = [r for r in rows if not r.get("metrics")]
    with open(os.path.join(args.out, "report.json"), "w") as f:
        json.dump(rows, f, indent=1)
    md = ["# Diagram layout report", "", f"{len(ok)} diagrams measured" + (f", {len(failed)} failed" if failed else "") + ".",
          "", "## Worst first", "", worst_first(ok, args.worst), "", "## All diagrams", "", markdown(ok, args.sort), "", LEGEND]
    md += scorer_section(args.scorer, ok)
    if failed:
        md += ["", "## Failed", ""]
        for r in failed:
            err = r.get("error") or ""
            md.append(f"- {r['diagram']}: " + "<br>".join(l.strip() for l in err.splitlines() if l.strip())[:600]
                      + (f" (full log: `{r['error_log']}`)" if r.get("error_log") else ""))
    est = [r for r in ok if r["metrics"].get("ink_estimated")]
    if est:
        md += ["", "## Estimated icon ink", "",
               "The glyph checks measure each icon's drawn shapes. For these icons the ink is only an estimate: text is sized "
               "from an average character width, and art that cannot be measured (e.g. `<use>`) is taken to fill its viewBox, "
               "which can hide a detached or overhanging glyph and make glyphs look bigger than drawn.", ""]
        md += [f"- {r['diagram']}: " + "; ".join(r["detail"].get("ink_estimated", []))
               + (" ..." if r["metrics"]["ink_estimated"] > len(r["detail"].get("ink_estimated", [])) else "") for r in est]
    md += ["", "## Details (worst first)", ""]
    for r in sorted(ok, key=lambda r: -r["metrics"]["badness"])[: args.worst]:
        d = r["detail"]
        md.append(f"### {r['diagram']}")
        for k in ("worst_wires", "through_block", "label_overlaps", "labels_hit_by_wires", "detours", "glyph_overlap",
                  "glyph_overlap_unwired", "glyph_detached", "glyph_overhang", "label_covered", "label_covered_by_icon", "wire_thru_glyph",
                  "junction_on_glyph", "near_diagonal", "ink_estimated"):
            if d.get(k):
                vals = d[k] if k != "worst_wires" else [f"{w['wire']} ({w['crossings']} X, {w['bends']} bends, len {w['length']})" for w in d[k]]
                md.append(f"- {k.replace('_', ' ')}: " + "; ".join(vals))
        if r.get("fresh_solve"):
            fs = r["fresh_solve"]
            md.append(f"- fresh `dyad layout solve` of the raw problem: {fs.get('crossings')} crossings, {fs.get('illegal_routes')} illegal routes")
        md.append("")
    with open(os.path.join(args.out, "report.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    print(os.path.join(args.out, "report.md"))
    if failed and not args.allow_failures:
        print(f"[layout-report] {len(failed)} of {len(rows)} diagrams failed (see report.md); --allow-failures to exit 0",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
