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
            src = open(path, encoding="utf-8").read()
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


DECL_RE = re.compile(r"^\s{2}(\w+)\s*=\s*[A-Za-z_][\w.]*\s*\(", re.M)


def instance_boxes(block):
    """name -> (x1, y1, x2, y2) of each instance's diagram placement in the source."""
    decls = list(DECL_RE.finditer(block))
    out = {}
    for i, d in enumerate(decls):
        seg = block[d.end(): decls[i + 1].start() if i + 1 < len(decls) else len(block)]
        m = re.search(r'"diagram"\s*:\s*\{([^}]*)\}', seg)
        if not m:
            continue
        kv = dict(re.findall(r'"(x1|x2|y1|y2|rot)"\s*:\s*(-?[\d.eE+-]+)', m.group(1)))
        try:
            x1, x2, y1, y2 = (float(kv[k]) for k in ("x1", "x2", "y1", "y2"))
        except KeyError:
            continue
        out[d.group(1)] = (min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2))
    return out


# ---------------------------------------------------------------------------
# SVG parsing


@dataclass
class Block:
    name: str
    box: tuple
    is_port: bool
    rot: float = 0.0
    labels: list = field(default_factory=list)  # (text, bbox) of each label drawn with the block


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
    issues: dict = field(default_factory=dict)  # geometry of each finding, for the overlay


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


def viewport_matrix(el, default_w=None, default_h=None):
    """Mapping from a nested <svg>'s user space to its parent's: x/y offset plus viewBox scaling.

    Implements the default preserveAspectRatio (xMidYMid meet) and "none".
    Width and height default to the given values; with neither, the nested
    viewport's size is unknown and the SVG is rejected.
    """
    x = _num(el, "x", 0.0)
    y = _num(el, "y", 0.0)
    w = _num(el, "width", default_w)
    h = _num(el, "height", default_h)
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


def _local(el, center):
    m = parse_transform(el.get("transform"))
    if el.get("transform-origin", "").startswith("center"):
        m = mat_mul(translate(*center), mat_mul(m, translate(-center[0], -center[1])))
    elif el.get("transform-origin"):
        raise UnsupportedSVG(f"transform-origin={el.get('transform-origin')!r}")
    return m


def parse_svg(svg_text, src_boxes=None):
    """Parse a `dyad render` SVG into blocks, wires, junctions and labels, in root user units.

    Transforms are accumulated down the tree (translate/scale/rotate/matrix on
    any element, the <svg> element included, and nested <svg> viewport
    mappings); any other transform is rejected. Groups are classified by
    content: Dyad wraps each block and boundary-port icon in a <g> with a direct
    <svg> child (a drop shadow on blocks only), and icons hold no wires. A <g>
    whose subtree holds a wire is a plain group whatever it wraps, so its
    wires, junctions and labels are measured like top-level ones, through any
    nested <svg> viewports.
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
        # the block's frame is its icon's viewport, in the group's coordinates, moved by the icon's own transform
        fm = mat_mul(m, _local(icons[0], center))
        _vm, (x, y, w, h) = viewport_matrix(icons[0], ICON_SIZE, ICON_SIZE)
        box = map_box(fm, x, y, x + w, y + h)
        rot = math.degrees(math.atan2(fm[1], fm[0])) % 360
        texts = []
        for icon in icons:
            im = mat_mul(mat_mul(m, _local(icon, center)), viewport_matrix(icon, ICON_SIZE, ICON_SIZE)[0])
            for t in icon:
                if tag_of(t) == "text":
                    txt, bb = text_box(t, mat_mul(im, _local(t, center)))
                    if txt and bb:
                        texts.append((txt, bb))
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
        if name is None:
            name = f"{'port' if not shadow else 'block'}#{counter[0]}"
        dg.blocks.append(Block(name, box, not shadow, rot, (label or []) if shadow else []))

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
                    dg.free_labels.append((txt, bb))
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

    # wires through blocks (and through boundary-port glyphs)
    through, through_len, through_list, through_port = 0, 0.0, [], 0
    for w in dg.wires:
        for b in dg.blocks:
            if b.is_port and b.name in w.ends:
                continue  # a wire runs into the glyph of the boundary port it ends at
            inner = shrink(b.box, 1.0)
            if inner[2] <= inner[0] or inner[3] <= inner[1]:
                continue
            L = sum(clip_len_in_box(p, q, inner) for p, q in zip(w.pts, w.pts[1:]))
            if L > 1.0 and b.is_port:
                through_port += 1
            elif L > 1.0:
                through += 1
                through_len += L
                through_list.append((w.name, b.name))
                dg.issues.setdefault("through", []).extend(
                    (p, q) for p, q in zip(w.pts, w.pts[1:]) if clip_len_in_box(p, q, inner) > 1.0)
    m["wire_through_block"] = through
    m["wire_through_block_len"] = round(through_len, 1)
    m["wire_through_port"] = through_port

    # block / label overlaps
    block_ov = 0
    allb = dg.blocks
    for i in range(len(allb)):
        for j in range(i + 1, len(allb)):
            if box_overlap_area(allb[i].box, allb[j].box) > 1:
                block_ov += 1
    m["block_overlaps"] = block_ov
    labels = [(b.name, bb) for b in comps for _t, bb in b.labels] + list(dg.free_labels)
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
            if labels[i][0] == labels[j][0] and labels[i][0] in {b.name for b in comps}:
                continue
            if box_overlap_area(labels[i][1], labels[j][1]) > 1:
                lb_label += 1
                lb_list.append((labels[i][0], labels[j][0]))
    for name, lb in labels:
        if any(clip_len_in_box(p, q, lb) > 1 for w in dg.wires for p, q in zip(w.pts, w.pts[1:])):
            lb_wire += 1
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
    full = union([b.box for b in dg.blocks] + list(bbs) + [lb for _, lb in labels])
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
    for _, lb in labels:
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
        "detours": [f"{n} ({d}x)" for d, n in sorted(detour_wires, reverse=True)[:10]],
    }
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
         "(red dot = crossing, magenta = false junction, red line = through a block, orange = shared run)</text>"]
    for b in dg.blocks:
        x, y, X, Y = b.box
        o.append(f"<rect x='{x:g}' y='{y:g}' width='{X - x:g}' height='{Y - y:g}' fill='{'#eef' if b.is_port else '#f4f4f4'}' "
                 f"stroke='{'#88a' if b.is_port else '#333'}' stroke-width='{1.2 * sw:g}'/>")
        for txt, (lx, ly, LX, LY) in b.labels:
            o.append(f"<rect x='{lx:g}' y='{ly:g}' width='{LX - lx:g}' height='{LY - ly:g}' fill='none' stroke='#9a9' "
                     f"stroke-dasharray='{3 * sw:g}' stroke-width='{0.8 * sw:g}'/>")
            o.append(f"<text x='{(lx + LX) / 2:g}' y='{(ly + LY) / 2:g}' font-size='{(LY - ly) * 0.8:g}' text-anchor='middle' "
                     f"dominant-baseline='central' font-family='sans-serif' fill='#353'>{esc(txt)}</text>")
        if b.is_port:
            o.append(f"<text x='{(x + X) / 2:g}' y='{(y + Y) / 2:g}' font-size='{max(8 * sw, (Y - y) * 0.3):g}' text-anchor='middle' "
                     f"dominant-baseline='central' font-family='sans-serif' fill='#558'>{esc(b.name)}</text>")
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
    o.append("</svg>")
    return "\n".join(o)


def badness(m):
    hard = (m.get("overlap_runs", 0) + m.get("diagonal_segments", 0) + m.get("wire_through_block", 0)
            + m.get("false_junctions", 0) + m.get("block_overlaps", 0))
    s = (20 * hard + 5 * m.get("unrouted_connects", 0) + 3 * m.get("crossings", 0)
         + 2 * (m.get("label_block_overlaps", 0) + m.get("label_label_overlaps", 0))
         + 0.5 * m.get("labels_hit_by_wires", 0) + 2 * m.get("wire_through_port", 0) + 2 * m.get("outer_wires", 0)
         + 2 * m.get("detour_wires", 0) + 0.25 * m.get("bends_total", 0) + 0.5 * m.get("micro_jogs", 0))
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
    ("overlap_runs", "ovl"), ("wire_through_block", "thru"), ("wire_through_port", "thru port"), ("diagonal_segments", "diag"),
    ("unrouted_connects", "unrt"), ("block_overlaps", "blk ovl"), ("label_block_overlaps", "lbl/blk"), ("label_label_overlaps", "lbl/lbl"),
    ("labels_hit_by_wires", "lbl/wire"), ("bends_mean", "bends/w"), ("bends_max", "bends max"),
    ("micro_jogs", "jogs"), ("wire_len_total", "len"), ("wire_len_max", "len max"), ("detour_wires", "detours"),
    ("outer_wires", "outer"), ("whitespace", "white"), ("largest_gap", "gap"), ("aspect", "aspect"),
    ("min_pin_pitch", "pitch"),
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
two different nets; thru = (wire, block) pairs where the wire passes through a block; thru port = the same for
another boundary port's glyph;
diag = non-orthogonal segments; unrt = connect() statements with no route metadata; lbl/blk,
lbl/lbl, lbl/wire = label overlaps; bends/w, bends max = bends per wire; jogs = interior segments
shorter than 10 units; len = Dyad units; detours = wires >= 2.5x their Manhattan distance;
outer = wires leaving the blocks' bounding box by > 30 units; white = fraction of 50x50 cells with
no block, label or wire; gap = side of the largest empty square; pitch = closest pins on different
nets. dl X / dl illegal / dl turns / dl spacing = dyad-layout's own objective on the drawn geometry;
dl unmatched = problem connections no drawn wire was matched to (a * marks scores that leave them out);
reroute X / reroute illegal = dyad-layout's router re-routing the same placements."""


def worst_first(rows, n):
    out = []
    for r in sorted(rows, key=lambda r: -r["metrics"]["badness"])[:n]:
        m = r["metrics"]
        why = []
        for k, label in (("unrouted_connects", "unrouted connects"), ("overlap_runs", "shared runs"),
                         ("false_junctions", "false junctions"), ("wire_through_block", "wires through blocks"), ("wire_through_port", "wires through port glyphs"), ("block_overlaps", "overlapping blocks/ports"),
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
        dg = parse_svg(svg, src_boxes)
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
    md += ["", "## Details (worst first)", ""]
    for r in sorted(ok, key=lambda r: -r["metrics"]["badness"])[: args.worst]:
        d = r["detail"]
        md.append(f"### {r['diagram']}")
        for k in ("worst_wires", "through_block", "label_overlaps", "detours"):
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
