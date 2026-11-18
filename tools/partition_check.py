#!/usr/bin/env python3
"""partition_check.py — compare the FLATTENED connection graph of a component
against a reference version, internal endpoints included.

Connectivity is flattened through sub-components (any instance whose type is
defined in the same library dir: an endpoint `inst.p` is merged with that
component's internal nets as `inst.<inner>`). The comparison is done on the
partition of *all* flattened endpoints, not just boundary pins, so an internal
input swap (a-b becoming b-a) fails.

Because layout work legitimately restructures a component into new
sub-components, endpoint names are canonicalised before comparing: an
instance path that exists on only one side (a newly introduced or inlined
sub-component) is made transparent — its boundary-pin endpoints are dropped
and its inner block paths are stripped of the prefix, so `airdata.p_sin.u2`
compares against a reference that had `p_sin.u2` inline. Instance paths that
exist on both sides keep their prefix. The residual blind spot: a swap of
two sub-component boundary pins whose insides are pure pass-throughs is not
visible; everything else (block-pin swaps, mis-attached multi-way arms,
wiring to the wrong net) is.

usage:
  partition_check.py [--ref REF] DYADDIR_CUR COMPONENT...
  partition_check.py --selftest

  DYADDIR_CUR  the .../dyad directory of the checkout to test
  REF          the reference: either a dyad dir, a demo dir containing dyad/,
               or a git ref (default 2e80df8) resolved inside the repo
               containing DYADDIR_CUR

Backwards compatible with the old call
  partition_check.py DYADDIR_REF DYADDIR_CUR FILE COMPONENT
(the FILE argument was already ignored).

The gate is EXACT: only an identical canonical endpoint partition passes.
A result that matches only in "shape" (the same net signatures with
internal instance names discarded) FAILS — shape matching cannot tell a
rewire between two identically-shaped nets from no change at all, e.g.
swapping `mv.a11` and `mv.a12` in QuatToBody. A renamed or extracted
block passes only through an explicit entry in RENAMES below, which a
reviewer can audit line by line.
"""
import os, re, sys, functools, subprocess, tempfile
from collections import Counter

COMPSTART = re.compile(r'\n((?:(?:abstract|test)\s+)?(?:component|model|connector|record|block)\s+)(\w+)')
DEFAULT_REF = '2e80df8'
HERE = os.path.dirname(os.path.abspath(__file__))

# Reviewed endpoint renames: RENAMES[component][ref_path] = cur_path, where
# each path is a canonical flattened endpoint or an instance-path prefix of
# one (a match on PATH itself or on PATH.<anything> is rewritten). Use it
# ONLY for a deliberate rename or extraction the reviewer has signed off
# on; every entry must be justified in review. An empty table means no
# rename is accepted anywhere.
#
# Audited for the DCMMatVec / QuatToDCM extraction (PR #51): the nine
# Product + three Add3 blocks that built R*v / R^T*b inline moved into
# shared sub-components. In the flattened graph of a parent the new
# instance path is transparent, so a ref endpoint `X.m12.u1` compares
# against cur `X.p12.u1` and the sum blocks `X.b1s`/`X.v1s` compare
# against `X.s1`:
#
#   kind 'qtb'  QuatToBody instance: product blocks m_ij -> p_ij,
#               column sums b1s/b2s/b3s -> s1/s2/s3. The shared
#               QuatToDCM keeps QuatToBody's r_ij convention, so the
#               r_ij endpoints compare unchanged.
#   kind 'qti'  QuatToInertial instance: same m_ij -> p_ij products and
#               v1s/v2s/v3s -> s1/s2/s3 sums. Its ref r_ij blocks carry
#               the TRANSPOSED DCM (ref QuatToInertial.r12 ==
#               QuatToDCM.r21), so the r_ij endpoints map as r_ij -> r_ji
#               for i != j. Net effect: ref `m12.u1 r12.y` pairs with
#               cur `p12.u1 r21.y`, preserving the v = R^T b semantics.
#   kind 'aero' HL20Aero instance: the |DRUD| Abs block was renamed
#               abs_drud -> abs_d.
#
# Each entry below is (instance path prefix inside the component, kind);
# '' means the component itself. Verified: with this table the default
# run is all-exact-match; the QuatToBody mv.a11<->mv.a12 swap still
# fails because a_ij pins drive different product blocks, not
# pass-throughs.
def _extraction(prefix, kind):
    def P(s):
        return f"{prefix}.{s}" if prefix else s
    e = {}
    if kind in ('qtb', 'qti'):
        for i in (1, 2, 3):
            for j in (1, 2, 3):
                e[P(f'm{i}{j}')] = P(f'p{i}{j}')
        sums = 'b' if kind == 'qtb' else 'v'
        for i in (1, 2, 3):
            e[P(f'{sums}{i}s')] = P(f's{i}')
        if kind == 'qti':
            for a, b in ((1, 2), (1, 3), (2, 3)):
                e[P(f'r{a}{b}')] = P(f'r{b}{a}')
                e[P(f'r{b}{a}')] = P(f'r{a}{b}')
    elif kind == 'aero':
        e[P('abs_drud')] = P('abs_d')
    elif kind == 'qk':
        # The QuatDerRow extraction is handled by the CUR-side rewrite in
        # _cur_qk_map, not by ref-side RENAMES: each row's blocks map back
        # to that row's ORIGINAL names (qkin.r{i}.p{k} -> q_j w_l,
        # qkin.r{i}.s -> dq{i}) so a cross-row swap cannot collapse into an
        # identical canonical name.
        pass
    else:
        raise ValueError(kind)
    return e


# Original inline block names of QuatKinematics' four derivative rows, one
# (p1, p2, p3) product triple and one Add3 sum dq_i per QuatDerRow r_i:
#   row 0: dq0 = q1w1 + q2w2 + q3w3   (k = -0.5, -0.5, -0.5)
#   row 1: dq1 = q0w1 + q2w3 + q3w2   (k = +0.5, +0.5, -0.5)
#   row 2: dq2 = q0w2 + q1w3 + q3w1   (k = +0.5, -0.5, +0.5)
#   row 3: dq3 = q0w3 + q1w2 + q2w1   (k = +0.5, +0.5, -0.5)
_QK_ROWS = (('q1w1', 'q2w2', 'q3w3'),
            ('q0w1', 'q2w3', 'q3w2'),
            ('q0w2', 'q1w3', 'q3w1'),
            ('q0w3', 'q1w2', 'q2w1'))

_EXTRACTIONS = {
    'QuatToBody': [('', 'qtb')],
    'QuatToInertial': [('', 'qti')],
    'HL20Aero': [('', 'aero')],
    'AeroForceBuilder': [('rot', 'qti')],
    'FlightState': [('rot', 'qtb')],
    'RigidBody6DOF': [('', 'qk')],
    'HL20Vehicle': [('aero', 'aero'), ('flight.rot', 'qtb'),
                    ('forces.rot', 'qti'), ('body', 'qk')],
    'HL20FullSystem': [('vehicle.aero', 'aero'),
                       ('vehicle.flight.rot', 'qtb'),
                       ('vehicle.forces.rot', 'qti'),
                       ('vehicle.body', 'qk')],
    'TestAeroPoint': [('aero', 'aero')],
    'TestAeroSweep': [('aero', 'aero')],
    'TestGravityOnly': [('body', 'qk')],
    'TestHL20FullSystem': [('sys.vehicle.aero', 'aero'),
                           ('sys.vehicle.flight.rot', 'qtb'),
                           ('sys.vehicle.forces.rot', 'qti'),
                           ('sys.vehicle.body', 'qk')],
    'TestHL20Subsonic': [('vehicle.aero', 'aero'),
                         ('vehicle.flight.rot', 'qtb'),
                         ('vehicle.forces.rot', 'qti'),
                         ('vehicle.body', 'qk')],
    'TestQuatDirection': [('rot_a', 'qti'), ('rot_b', 'qti')],
    'TestQuatRoundTrip': [('rot_f', 'qti'), ('rot_b', 'qtb')],
}

RENAMES = {comp: {k: v for prefix, kind in specs
                  for k, v in _extraction(prefix, kind).items()}
           for comp, specs in _EXTRACTIONS.items()}

# Controller instance renames made in this PR (ref `*_ctrl` -> cur
# short names); the inverse _PATH_EQUIV entries keep children attached.
for _pfx, _comps in (('', ['HL20FullSystem']),
                     ('sys.', ['TestHL20FullSystem'])):
    for _c in _comps:
        RENAMES.setdefault(_c, {}).update(
            {_pfx + n + '_ctrl': _pfx + n
             for n in ('pitch', 'roll', 'yaw', 'speed')})

ANALYSIS = re.compile(r'(?ms)^analysis\s+(\w+)\b(.*?)^end\s*$')

def lib_sections(dyaddir):
    secs = {}
    for root, _, files in os.walk(dyaddir):
        for f in files:
            if not f.endswith('.dyad'): continue
            text = open(os.path.join(root, f)).read()
            marks = [(m.start() + 1, m.group(2)) for m in COMPSTART.finditer('\n' + text)]
            m0 = re.match(r'\s*(?:(?:abstract|test)\s+)?(?:component|model|connector|record|block)\s+(\w+)', text)
            if m0: marks.append((0, m0.group(1)))
            marks = sorted(set(marks))
            for i, (pos, name) in enumerate(marks):
                end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
                # `analysis` blocks sit between components; strip them so
                # `model = X()` inside is not mistaken for a sub-instance.
                secs[name] = ANALYSIS.sub('\n', text[pos:end])
    return secs


def lib_analyses(dyaddir):
    """{analysis_name: normalised text} for every analysis block."""
    out = {}
    for root, _, files in os.walk(dyaddir):
        for f in files:
            if not f.endswith('.dyad'): continue
            text = open(os.path.join(root, f)).read()
            for m in ANALYSIS.finditer(text):
                body = re.sub(r'#.*$', '', m.group(2), flags=re.M)
                out[m.group(1)] = re.sub(r'\s+', '', body)
    return out

CON = re.compile(r'connect\s*\(')
def connects(text):
    out = []
    for m in CON.finditer(text):
        i = m.end(); depth = 1; buf = ''
        while depth and i < len(text):
            ch = text[i]; i += 1
            if ch == '(': depth += 1
            elif ch == ')': depth -= 1
            else: buf += ch
        out.append([a.strip() for a in buf.split(',') if a.strip()])
    return [c for c in out if len(c) >= 2]

def instances(text, lib):
    """instance name -> component type, for `name = Comp(...)` style decls.
    Only same-library types are returned (only those are flattened)."""
    inst = {}
    for m in re.finditer(r'(\w+)\s*=\s*([\w.]+)\s*\(', text):
        t = m.group(2).split('.')[-1]
        if t in lib and t != m.group(1):
            inst[m.group(1)] = t
    return inst

class UF:
    def __init__(self): self.p = {}
    def find(self, x):
        self.p.setdefault(x, x)
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]; x = self.p[x]
        return x
    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb: self.p[rb] = ra
    def groups(self):
        g = {}
        for x in self.p: g.setdefault(self.find(x), set()).add(x)
        return [frozenset(v) for v in g.values()]

@functools.lru_cache(maxsize=None)
def flat_nets(libname, lib_frozen):
    lib = dict(lib_frozen)
    sec = lib[libname]
    inst = instances(sec, lib)
    uf = UF()
    for c in connects(sec):
        for e in c[1:]: uf.union(c[0], e)
    # merge each instance's internal nets, names prefixed inst.
    for iname, itype in inst.items():
        if itype == libname: continue
        for net in flat_nets(itype, lib_frozen):
            mem = [f"{iname}.{n}" for n in net]
            for e in mem[1:]: uf.union(mem[0], e)
    return frozenset(uf.groups())

def inst_paths(libname, lib):
    """all nested instance paths (dot-joined) of same-library instances."""
    out = set()
    def rec(c, prefix, seen):
        for n, t in instances(lib[c], lib).items():
            if t == c or t in seen: continue
            p = prefix + n
            out.add(p)
            rec(t, p + '.', seen | {t})
    rec(libname, '', {libname})
    return out

def canon_ep(ep, comp, lib, newpaths, imaps, prefix=''):
    """Canonicalise one flattened endpoint.

    `newpaths` is the set of instance paths (from `comp`) that exist only in
    this version. A leading instance segment that is new is transparent:
    stripped away. What remains after stripping is kept unless it is a bare
    pin name (a transparent sub-component's boundary pin), which is dropped —
    the pin's inner wiring is already reified by the stripped block paths.

    Returns the canonical endpoint, or None to drop it.
    """
    segs = ep.split('.')
    if len(segs) == 1:
        return segs[0]
    t = imaps(comp).get(segs[0])
    if t is None or t not in lib:
        return ep                       # non-library block pin: keep as-is
    ipath = prefix + segs[0]
    inner = canon_ep('.'.join(segs[1:]), t, lib, newpaths, imaps, ipath + '.')
    if ipath in newpaths:
        return inner if (inner is not None and '.' in inner) else None
    return segs[0] + '.' + inner if inner is not None else None

class CanonError(Exception):
    """Two distinct flattened endpoints canonicalised to the same name —
    a transparent-prefix collision that would hide a rewire."""
    pass


def canon_nets(nets, comp, lib, newpaths, cur_rw=None):
    imapcache = {}
    def imaps(c):
        if c not in imapcache: imapcache[c] = instances(lib[c], lib)
        return imapcache[c]
    out = Counter()
    for net in nets:
        cns = []
        for ep in net:
            if cur_rw:
                ep = _apply_prefix_map(ep, cur_rw)
            c = canon_ep(ep, comp, lib, newpaths, imaps)
            if c is not None:
                cns.append(c)
        dup = sorted(x for x, n in Counter(cns).items() if n > 1)
        if dup:
            raise CanonError(
                f"{comp}: distinct endpoints canonicalise to the same "
                f"name {dup} in net {sorted(net)}")
        out[frozenset(cns)] += 1
    return out

def boundary_partition(nets):
    """frozenset of boundary-pin sets per net (legacy, weaker check)."""
    out = set()
    for net in nets:
        b = frozenset(n for n in net if '.' not in n)
        if b: out.add(b)
    return out

def shape_partition(nets):
    """Net shapes: (boundary pins, sorted pin-name suffixes) per net, as a
    multiset. Renaming an internal block (`m11` -> `p11`) leaves the shape
    unchanged; rewiring a pin to a different pin name or net does not."""
    from collections import Counter
    sigs = Counter()
    for net in nets:
        b = frozenset(n for n in net if '.' not in n)
        suf = tuple(sorted(n.rsplit('.', 1)[-1] for n in net if '.' in n))
        sigs[(b, suf)] += 1
    return sigs

# Sub-instance extraction path equivalences: _PATH_EQUIV[comp] maps a
# CUR instance-path prefix to its REF equivalent, so paths that differ
# only by an extraction wrapper compare equal. E.g. HL20Vehicle's
# RigidBody6DOF/FlightState/AirData/AeroForceBuilder instances moved
# inside a new `vd = VehicleDynamics` sub-component: `vd.body` == `body`.
# `vd` itself stays a new path (transparent), but `vd.body` no longer
# counts as new, so `body.` prefixes are kept on both sides and the
# RENAMES extraction entries above continue to apply verbatim.
#
# The aero entries map the six coefficient blocks out of the lon/lat/pair
# group wrappers: without them `lon.pair.cl` normalises to a path that
# does not exist on the REF side (REF had `cl` inline), so `cl` counted
# as new on both sides and every endpoint inside the six coefficient
# blocks was silently dropped. With the mapping, `lon.pair.cl` keeps the
# literal `cl` prefix on the CUR side and `cl` is not new on the REF
# side, so a swap like cl.DBFUR <-> cl.DWFL is a real diff. The lon/lat/
# pair/air wrappers themselves stay transparent: REF's inline contents
# (the trig chain, the air-data conditioning, the CX/CZ products) match
# the stripped CUR names one to one.
def _aero_equiv(a):
    P = lambda s: f'{a}.{s}' if a else s
    return {P('lon.pair.cl'): (P('cl'), True),
            P('lon.pair.cd'): (P('cd'), True),
            P('lon.cm'): (P('cm'), True),
            P('lat.pair.cy'): (P('cy'), True),
            P('lat.pair.cn'): (P('cn'), True),
            P('lat.cr'): (P('cr'), True)}


def _ctrl_equiv(pfx):
    """Controller instance renames inside HL20FullSystem-family
    components: CUR `pitch` is REF `pitch_ctrl`, etc. The self-map makes
    the renamed instance keep its (new) literal name; children normalise
    to the REF `*_ctrl` path."""
    return {pfx + 'pitch': (pfx + 'pitch_ctrl', True),
            pfx + 'roll': (pfx + 'roll_ctrl', True),
            pfx + 'yaw': (pfx + 'yaw_ctrl', True),
            pfx + 'speed': (pfx + 'speed_ctrl', True)}


_PATH_EQUIV = {
    'HL20Aero': _aero_equiv(''),
    'TestAeroPoint': _aero_equiv('aero'),
    'TestAeroSweep': _aero_equiv('aero'),
    'HL20Vehicle': {'vd': ('', False), 'vd.airdata': ('', False),
                    **_aero_equiv('aero')},
    'HL20FullSystem': {'vehicle.vd': ('vehicle', False),
                       'vehicle.vd.airdata': ('vehicle', False),
                       **_aero_equiv('vehicle.aero'),
                       **_ctrl_equiv('')},
    'TestHL20Subsonic': {'vehicle.vd': ('vehicle', False),
                         'vehicle.vd.airdata': ('vehicle', False),
                         **_aero_equiv('vehicle.aero')},
    'TestHL20FullSystem': {'sys.vehicle.vd': ('sys.vehicle', False),
                           'sys.vehicle.vd.airdata': ('sys.vehicle', False),
                           **_aero_equiv('sys.vehicle.aero'),
                           **_ctrl_equiv('sys.')},
}


def _norm_paths(p, comp):
    """The SET of REF-equivalent candidate paths for a CUR instance path.
    Each _PATH_EQUIV entry is (new, selfmap): a `selfmap` entry also maps
    `p == old` to `new` (a renamed instance); any entry maps children
    `old.*` to `new.*` (or `*` when new is ''). A cur path counts as new
    only when NO candidate — not its literal name, not any normalisation —
    exists on the REF side, so the same CUR file compares exactly against
    both the pre-layout ref (2e80df8: no `vd`, `airdata`, `lon`/`lat`
    wrappers, `*_ctrl` names) and the PR-base ref (227734c: `airdata`,
    `lon`/`lat` present, still no `vd`)."""
    out = {p}
    for old, (new, selfmap) in _PATH_EQUIV.get(comp, {}).items():
        if p == old and selfmap:
            out.add(new if new else p[len(old) + 1:])
        elif p.startswith(old + '.'):
            out.add(new + p[len(old):] if new else p[len(old) + 1:])
    return out


# Type equivalences an auditor has signed off on: a decl of the key type
# is semantically the same as the mapped type instantiated with the
# mapped default args (stdlib `Feedback` computes u1 - u2).
_TYPE_ALIAS = {
    'BlockComponents.Math.Feedback':
        ('BlockComponents.Math.Add', {'k2': -1.0}),
}

# Connector/port type suffixes: a leaf instance of one of these types
# whose parent instance is transparent is a boundary pin of the wrapper,
# so it drops (the same rule canon_ep applies via the '.' check).
_PORT_SUFFIXES = ('Input', 'Output', 'Port', 'Port_a', 'Port_b', 'Pin',
                  'Flange', 'Flange_a', 'Flange_b', 'Frame', 'Frame_a',
                  'Frame_b', 'Support', 'Node')


def _newpaths(comp, lib, other_lib, cur):
    """Instance paths present on this side but with no counterpart on the
    other. A CUR path is new when no candidate normalisation exists in
    REF; a REF path is new when it is neither a literal CUR path nor any
    candidate normalisation of one."""
    if cur:
        ref_paths = inst_paths(comp, other_lib)
        return {p for p in inst_paths(comp, lib)
                if not (_norm_paths(p, comp) & ref_paths)}
    cur_paths = inst_paths(comp, other_lib)
    cur_norm = set()
    for p in cur_paths:
        cur_norm |= _norm_paths(p, comp)
    return {p for p in inst_paths(comp, lib)
            if p not in cur_paths and p not in cur_norm}


def _cur_qk_map(comp, lib):
    """CUR-side endpoint rewrites for the audited QuatDerRow extraction:
    map each row's blocks back to that row's ORIGINAL inline names
    (`<c>.r{i}.p{k}` -> `<c>.q_j w_l`, `<c>.r{i}.s` -> `<c>.dq{i}`) for
    every flattened container `c` holding the four r0..r3 rows (the
    container is `''` for QuatKinematics itself, `qkin`-suffixed paths
    elsewhere). Applied before canonicalisation, so `qkin` still strips
    when it is a new path but the row identity survives — a cross-row
    swap (r0.dq<->r1.dq, r0.qa<->r1.qa, wa<->wc, ...) can no longer
    collapse into an identical canonical endpoint."""
    paths = inst_paths(comp, lib)
    containers = {p[:-3] for p in paths if p == 'r0' or p.endswith('.r0')}
    e = {}
    for c in containers:
        P = lambda s: f'{c}.{s}' if c else s
        if c != '' and not c.endswith('qkin'):
            continue
        if not all(P(f'r{i}') in paths for i in range(4)):
            continue
        for i, prods in enumerate(_QK_ROWS):
            for k, prod in enumerate(prods):
                e[P(f'r{i}.p{k + 1}')] = P(prod)
            e[P(f'r{i}.s')] = P(f'dq{i}')
    return e


def _apply_prefix_map(ep, table):
    """Rewrite endpoint `ep` by the longest matching prefix in `table`
    (a match on PATH itself or on PATH.<anything>)."""
    best = None
    for old, new in table.items():
        if ep == old or ep.startswith(old + '.'):
            if best is None or len(old) > len(best[0]):
                best = (old, new)
    if best is not None:
        old, new = best
        return new + ep[len(old):]
    return ep


def full_partition(comp, lib, other_lib, cur=False):
    nr = flat_nets(comp, frozenset(lib.items()))
    newpaths = _newpaths(comp, lib, other_lib, cur)
    rw = _cur_qk_map(comp, lib) if cur else None
    return canon_nets(nr, comp, lib, newpaths, rw), nr

def resolve_ref(ref, curdir):
    """REF may be a dyad dir, a demo dir containing dyad/, or a git ref."""
    if os.path.isdir(ref):
        return ref if os.path.basename(os.path.normpath(ref)) == 'dyad' \
            else os.path.join(ref, 'dyad')
    root = subprocess.run(['git', '-C', curdir, 'rev-parse', '--show-toplevel'],
                          capture_output=True, text=True, check=True).stdout.strip()
    rel = os.path.relpath(os.path.abspath(curdir), root)
    tmp = tempfile.mkdtemp(prefix='pcheck-')
    archive = subprocess.run(['git', '-C', root, 'archive', ref, rel],
                             check=True, capture_output=True).stdout
    open(os.path.join(tmp, 'ref.tar'), 'wb').write(archive)
    subprocess.run(['tar', '-x', '-f', os.path.join(tmp, 'ref.tar'), '-C', tmp],
                   check=True)
    return os.path.join(tmp, rel)

def apply_renames(nets, comp):
    """Rewrite canonical endpoints per RENAMES[comp] (ref -> cur names)."""
    table = RENAMES.get(comp)
    if not table: return nets
    out = Counter()
    for net, k in nets.items():
        out[frozenset(_apply_prefix_map(ep, table) for ep in net)] += k
    return out

# ---------------------------------------------------------------- semantics
#
# Wiring alone is not the model: the signature below also compares, per
# component, the declared parameter defaults, every flattened block
# instance's component type and parameter arguments (with parent parameter
# values substituted down the hierarchy), the non-connect equations
# (including `initial` values) and the analyses. Instance paths are
# canonicalised with the same transparent-prefix rules as endpoints, so a
# block's semantic slot follows its wiring slot.

_PARAM = re.compile(r'(?m)^\s*parameter\s+(\w+)\s*(?:::[\w.]+)?\s*=\s*(.+?)\s*$')
_DECL = re.compile(r'(\w+)\s*=\s*([\w.]+)\s*\(')
_IDENT = re.compile(r'[A-Za-z_]\w*')


def _strip_meta(s):
    """Remove JSON `{...}` metadata blocks, comments and whitespace."""
    out, i, depth = [], 0, 0
    while i < len(s):
        c = s[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        elif depth == 0:
            out.append(c)
        i += 1
    s = ''.join(out)
    s = re.sub(r'#.*$', '', s, flags=re.M)
    return s


def _norm_val(v):
    v = v.strip()
    try:
        return float(v)
    except ValueError:
        return re.sub(r'\s+', '', v)


def _subst(expr, env):
    return _IDENT.sub(lambda m: env.get(m.group(0), m.group(0)), expr)


def _sec_params(sec):
    return {m.group(1): _norm_val(m.group(2).split('{', 1)[0])
            for m in _PARAM.finditer(sec)}


def _call_args(text, open_idx):
    """(args dict) for the (...) call starting at text[open_idx] == '('."""
    i, depth, buf = open_idx + 1, 1, ''
    while depth and i < len(text):
        ch = text[i]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                break
        if depth:
            buf += ch
        i += 1
    args, d2, last, n = {}, 0, 0, 0
    for j in range(len(buf) + 1):
        ch = buf[j] if j < len(buf) else ','
        if ch == '(':
            d2 += 1
        elif ch == ')':
            d2 -= 1
        if ch == ',' and d2 == 0:
            piece = buf[last:j].strip()
            last = j + 1
            if not piece:
                continue
            k, eq, v = piece.partition('=')
            if eq:
                args[k.strip()] = v.strip()
            else:
                n += 1
                args[f'#{n}'] = piece
    return args


def _decls(sec):
    """(name, type, args) for every `name = Type(args)` decl, stdlib
    included; `parameter` lines are skipped and only the declarations
    region (before `relations`/`metadata`/`end`) is scanned so equations
    like `y = max(u1, u2)` are not mistaken for instances."""
    m = re.search(r'(?m)^(relations|metadata|end)\b', sec)
    head = sec[:m.start()] if m else sec
    flat = '\n'.join(l for l in head.split('\n') if 'parameter' not in l)
    for m in _DECL.finditer(flat):
        yield m.group(1), m.group(2), _call_args(flat, m.end() - 1)


def _flat_insts(comp, lib):
    """{flat_instance_path: (type, resolved_args)} over the whole
    sub-component tree. Parent parameter values are substituted down:
    each instance's args are resolved against the enclosing component's
    parameter bindings before descending."""
    out = {}

    def rec(cname, prefix, inherited, seen):
        env = {}
        for n, d in _sec_params(lib[cname]).items():
            env[n] = _subst(str(inherited.get(n, d)),
                            {**inherited, **env})
        for name, typ, args in _decls(lib[cname]):
            if name == cname:
                continue
            raw = {a: _subst(str(v), env) for a, v in args.items()}
            resolved = {a: _norm_val(v) for a, v in raw.items()}
            alias = _TYPE_ALIAS.get(typ)
            if alias:
                typ, extra = alias
                resolved = {**extra, **resolved}
            out[prefix + name] = (typ, resolved)
            t = typ.split('.')[-1]
            if t in lib and t != cname and t not in seen:
                rec(t, prefix + name + '.', raw, seen | {t})

    rec(comp, '', {}, {comp})
    return out


def _canon_inst(path, typ, comp, lib, newpaths, imaps, prefix=''):
    """Canonical instance path: strip leading segments whose instance path
    is new, keep the literal name of every surviving segment. Returns None
    for a path whose innermost instance is itself new (an extraction
    wrapper — its children carry the semantics) and for a port leaf that
    sits inside a transparent wrapper (a wrapper boundary pin)."""
    segs = path.split('.')
    t = imaps(comp).get(segs[0])
    ipath = prefix + segs[0]
    if len(segs) == 1:
        if t is not None and t in lib and ipath in newpaths:
            return None
        return segs[0]
    if t is None or t not in lib:
        return path
    inner = _canon_inst('.'.join(segs[1:]), typ, t, lib, newpaths, imaps,
                        ipath + '.')
    if ipath in newpaths:
        if inner is None:
            return None
        if '.' not in inner and typ.split('.')[-1].endswith(_PORT_SUFFIXES):
            return None
        return inner
    return segs[0] + '.' + inner if inner is not None else None


def _eq_chunks(sec):
    """Non-connect statements in the relations region, normalised."""
    rel = re.search(r'(?ms)^relations\s*$(.*?)(?:^metadata\b|^end\s*$)', sec)
    if not rel:
        return []
    text = rel.group(1)
    # remove connect(...) calls with their trailing metadata
    out, i = [], 0
    for m in CON.finditer(text):
        out.append(text[i:m.start()])
        j, depth = m.end(), 1
        while depth and j < len(text):
            ch = text[j]
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
            j += 1
        i = j
    out.append(text[i:])
    text = re.sub(r'(?m)^\s*metadata\b', '', ''.join(out))
    text = _strip_meta(text)
    return [re.sub(r'\s+', '', ln) for ln in text.split('\n')
            if re.sub(r'\s+', '', ln)]


def _flat_eqs(comp, lib, newpaths, imaps, cur_rw):
    """{canonical container path: [normalised statements]} — statements of
    an extraction wrapper (canonical path None) attach to the nearest
    surviving ancestor, matching the pre-extraction level."""
    out = {}

    def rec(cname, rawpath, canonpath, seen):
        for ch in _eq_chunks(lib[cname]):
            out.setdefault(canonpath, []).append(ch)
        for name, t in instances(lib[cname], lib).items():
            if t == cname or t in seen:
                continue
            rp = rawpath + name
            p2 = _apply_prefix_map(rp, cur_rw) if cur_rw else rp
            c2 = _canon_inst(p2, '', comp, lib, newpaths, imaps)
            rec(t, rp + '.', c2 if c2 is not None else canonpath,
                seen | {t})

    rec(comp, '', '', {comp})
    return out


def _sem_signature(comp, lib, newpaths, renames=None, cur_rw=None):
    """(params, insts, eqs) semantic signature of `comp`."""
    imapcache = {}

    def imaps(c):
        if c not in imapcache:
            imapcache[c] = instances(lib[c], lib)
        return imapcache[c]

    insts = {}
    for p, ta in _flat_insts(comp, lib).items():
        if cur_rw:
            p = _apply_prefix_map(p, cur_rw)
        cp = _canon_inst(p, ta[0], comp, lib, newpaths, imaps)
        if cp is None:
            continue
        if renames:
            cp = _apply_prefix_map(cp, renames)
        if cp in insts:
            raise CanonError(f"{comp}: instances collide at canonical "
                             f"path {cp} ({p} vs {insts[cp]})")
        insts[cp] = ta
    eqs = _flat_eqs(comp, lib, newpaths, imaps, cur_rw)
    if renames:
        eqs = {_apply_prefix_map(k, renames) if k else k: v
               for k, v in eqs.items()}
    return _sec_params(lib[comp]), insts, eqs


def _sem_diff(comp, reflib, curlib, ref_np, cur_np, cur_rw):
    pr, ir, er = _sem_signature(comp, reflib, ref_np,
                                renames=RENAMES.get(comp))
    pc, ic, ec = _sem_signature(comp, curlib, cur_np, cur_rw=cur_rw)
    diffs = []
    if pr != pc:
        diffs.append("  params: " +
                     '; '.join(sorted(f"{k}: {pr.get(k)}!={pc.get(k)}"
                                      for k in set(pr) | set(pc)
                                      if pr.get(k) != pc.get(k))))
    for k in sorted(set(ir) | set(ic)):
        if k not in ir:
            diffs.append(f"  inst only CUR: {k} = {ic[k][0]}{ic[k][1]}")
        elif k not in ic:
            diffs.append(f"  inst only REF: {k} = {ir[k][0]}{ir[k][1]}")
        elif ir[k][0] != ic[k][0]:
            diffs.append(f"  inst {k}: type {ir[k][0]} != {ic[k][0]}")
        elif ir[k][1] != ic[k][1]:
            diffs.append(f"  inst {k} args: {ir[k][1]} != {ic[k][1]}")
        if len(diffs) > 12:
            break
    if er != ec:
        diffs.append("  equations differ: " +
                     '; '.join(sorted(f"{k or '<top>'}: REF{er.get(k)} "
                                      f"CUR{ec.get(k)}"
                                      for k in set(er) | set(ec)
                                      if er.get(k) != ec.get(k))[:6]))
    return diffs


def compare(reflib, curlib, comp):
    """return (level, boundary_ok, diff_info) where level is
    'match' | 'shape' | 'mismatch' | None(component missing).
    'match' is exact after canonicalisation and RENAMES, on both the
    flattened wiring partition and the semantic signature. 'shape' (same
    net signatures, different internal endpoints) is reported for
    diagnosis but is a gate failure like 'mismatch'."""
    if comp not in reflib: return None, None, f"{comp} missing in REF"
    if comp not in curlib: return None, None, f"{comp} missing in CUR"
    info = []
    try:
        cr, nr = full_partition(comp, reflib, curlib)
        cc, nc = full_partition(comp, curlib, reflib, cur=True)
    except CanonError as e:
        return 'mismatch', False, str(e)
    cr = apply_renames(cr, comp)
    ok = cr == cc
    shape = shape_partition(cr.elements()) == \
        shape_partition(cc.elements())
    br = boundary_partition(flat_nets(comp, frozenset(reflib.items())))
    bc = boundary_partition(flat_nets(comp, frozenset(curlib.items())))
    if not ok:
        only_ref = sorted(cr - cc, key=str)
        only_cur = sorted(cc - cr, key=str)
        for b in only_ref[:10]: info.append("  only REF: " + ' '.join(sorted(b)))
        for b in only_cur[:10]: info.append("  only CUR: " + ' '.join(sorted(b)))
        if shape:
            info.append("  net SHAPES match — only internal endpoint names "
                        "differ. If this is a reviewed rename or extraction, "
                        "add it to RENAMES in this tool; otherwise the wiring "
                        "changed.")
    try:
        info += _sem_diff(comp, reflib, curlib,
                          _newpaths(comp, reflib, curlib, cur=False),
                          _newpaths(comp, curlib, reflib, cur=True),
                          _cur_qk_map(comp, curlib))
    except CanonError as e:
        info.append(str(e))
    if info:
        ok = False
    return ('match' if ok else 'shape' if shape else 'mismatch'), \
        br == bc, '\n'.join(info)

def selftest():
    """A swapped internal connection must fail the full check while the
    old boundary-only check still passes; and a same-shape rewire through
    an extracted sub-component must fail the gate (not pass as 'shape')."""
    base = """component Swap
  a = RealInput()
  b = RealInput()
  y = RealOutput()
  blk = Block1()
relations
  connect(a, blk.u1)
  connect(b, blk.u2)
  connect(blk.y, y)
end
"""
    swapped = base.replace('blk.u1', 'TMP').replace('blk.u2', 'blk.u1').replace('TMP', 'blk.u2')
    lib_r = {'Swap': base}
    lib_c = {'Swap': swapped}
    ok_full, ok_bound, _ = compare(lib_r, lib_c, 'Swap')
    print(f"selftest: full={ok_full} boundary={'MATCH' if ok_bound else 'MISMATCH'}")
    if not (ok_full != 'match' and ok_bound is True):
        print("selftest FAIL: internal swap not caught by full check")
        return 1
    print("selftest: internal swap detected by full check, invisible to boundary check")

    # Regression: the QuatToBody mv.a11/mv.a12 swap. The reference wires its
    # product blocks inline; the current version extracted them into a
    # sub-component and swapped two of its pins. Every net keeps the same
    # shape signature, so the old shape tier called this a match even
    # though the result changes. It must now FAIL. The same extraction
    # WITHOUT the swap must PASS, through an audited RENAMES entry.
    ref_inline = """component QuatToBody
  a = RealInput()
  b = RealInput()
  y1 = RealOutput()
  y2 = RealOutput()
  s1 = Src()
  s2 = Src()
  m11 = Prod()
  m12 = Prod()
relations
  connect(a, s1.u)
  connect(b, s2.u)
  connect(s1.y, m11.u)
  connect(s2.y, m12.u)
  connect(m11.y, y1)
  connect(m12.y, y2)
end
"""
    cur_extracted = """component QuatToBody
  a = RealInput()
  b = RealInput()
  y1 = RealOutput()
  y2 = RealOutput()
  s1 = Src()
  s2 = Src()
  mv = Sink()
relations
  connect(a, s1.u)
  connect(b, s2.u)
  connect(s1.y, mv.a11)
  connect(s2.y, mv.a12)
  connect(mv.y1, y1)
  connect(mv.y2, y2)
end
"""
    sink = """component Sink
  a11 = RealInput()
  a12 = RealInput()
  y1 = RealOutput()
  y2 = RealOutput()
  p11 = Prod()
  p12 = Prod()
relations
  connect(a11, p11.u)
  connect(a12, p12.u)
  connect(p11.y, y1)
  connect(p12.y, y2)
end
"""
    lib_r = {'QuatToBody': ref_inline}
    lib_c = {'QuatToBody': cur_extracted, 'Sink': sink}
    saved = RENAMES.get('QuatToBody')
    RENAMES['QuatToBody'] = {'m11': 'p11', 'm12': 'p12'}
    lvl, _, info = compare(lib_r, lib_c, 'QuatToBody')
    if lvl != 'match':
        print("selftest FAIL: reviewed extraction+rename did not match")
        print(info)
        return 1
    print("selftest: reviewed extraction passes through its RENAMES entry")
    cur_swapped = cur_extracted.replace('mv.a11', 'TMP') \
        .replace('mv.a12', 'mv.a11').replace('TMP', 'mv.a12')
    lib_c = {'QuatToBody': cur_swapped, 'Sink': sink}
    lvl, _, info = compare(lib_r, lib_c, 'QuatToBody')
    if saved is None:
        del RENAMES['QuatToBody']
    else:
        RENAMES['QuatToBody'] = saved
    shape_ok = shape_partition(full_partition('QuatToBody', lib_r, lib_c)[0].elements()) == \
        shape_partition(full_partition('QuatToBody', lib_c, lib_r)[0].elements())
    print(f"selftest: extracted-swap level={lvl} (shapes {'equal' if shape_ok else 'differ'})")
    if lvl not in ('shape', 'mismatch'):
        print("selftest FAIL: same-shape rewire was not flagged")
        print(info)
        return 1
    print("selftest: same-shape rewire flagged (fails the gate)")
    return _selftest_real()


def _swap2(text, a, b):
    """Swap literals a and b in `text` (a<->b), applied to all copies."""
    return text.replace(a, '\x00').replace(b, a).replace('\x00', b)


def _mutate(lib, comp, old, new):
    lib = dict(lib)
    assert old in lib[comp], (comp, old)
    lib[comp] = lib[comp].replace(old, new, 1)
    return lib


def _selftest_real():
    """Every mutation a reviewer flagged must fail the gate on the real
    model. Returns 0 if all are caught, 1 otherwise."""
    dyaddir = os.path.join(HERE, '..', 'HL20Demo', 'dyad')
    refdir = resolve_ref(DEFAULT_REF, dyaddir)
    lib_r = lib_sections(refdir)
    lib_c = lib_sections(dyaddir)
    fails = []

    def mut(comp, owner, *subs):
        """apply (old,new) replacements inside section `owner`, compare `comp`"""
        lib_m = dict(lib_c)
        sec = lib_m[owner]
        for old, new in subs:
            if old not in sec:
                fails.append((comp, f'mutation target missing: {old!r}'))
                return
            sec = sec.replace(old, new, 1)
        lib_m[owner] = sec
        lvl, _, info = compare(lib_r, lib_m, comp)
        if lvl == 'match':
            fails.append((comp, f'not caught: {subs!r}\n{info}'))

    # cross-row QuatDerRow wiring swaps (item 1)
    mut('RigidBody6DOF', 'QuatKinematics',
        ('connect(r0.dq, int_q0.u)', 'connect(r1.dq, int_q0.u)'),
        ('connect(r1.dq, int_q1.u)', 'connect(r0.dq, int_q1.u)'))
    # r0.qa <-> r1.qa (cross-row quaternion-factor swap)
    lib_m = dict(lib_c)
    lib_m['QuatKinematics'] = _swap2(lib_m['QuatKinematics'], 'r0.qa', 'r1.qa')
    lvl, _, info = compare(lib_r, lib_m, 'RigidBody6DOF')
    if lvl == 'match':
        fails.append(('RigidBody6DOF', 'r0.qa<->r1.qa swap not caught'))
    # QuatDerRow's own wa<->wc
    mut('RigidBody6DOF', 'QuatDerRow',
        ('connect(wa, p1.u2)', 'connect(wc, p1.u2)'),
        ('connect(wc, p3.u2)', 'connect(wa, p3.u2)'))
    # changed row coefficient k3 -0.5 -> 0.5 (semantic)
    mut('RigidBody6DOF', 'QuatKinematics',
        ('r1 = QuatDerRow(k1 = 0.5, k2 = 0.5, k3 = -0.5)',
         'r1 = QuatDerRow(k1 = 0.5, k2 = 0.5, k3 = 0.5)'))
    # Product -> Division (semantic type)
    mut('RigidBody6DOF', 'QuatDerRow',
        ('p1 = BlockComponents.Math.Product()',
         'p1 = BlockComponents.Math.Division()'))
    # swapped integrator x0 q0_0 -> q1_0 (semantic args)
    mut('RigidBody6DOF', 'QuatKinematics',
        ('x0 = q0_0', 'x0 = q1_0'))
    # swapped mass/g on RigidBody6DOF instantiation (semantic args)
    mut('HL20Vehicle', 'VehicleDynamics',
        ('mass=mass, g=g', 'mass=g, g=mass'))
    # changed top-level parameter default -3048 -> -3000 (semantic params)
    mut('HL20Vehicle', 'HL20Vehicle',
        ('parameter p3_0::Real = -3048.0', 'parameter p3_0::Real = -3000.0'))
    # aero coefficient-block input swap cl.DBFUR <-> cl.DWFL (item 2)
    lib_m = dict(lib_c)
    lib_m['AeroCLCD'] = _swap2(lib_m['AeroCLCD'], 'cl.DBFUR', 'cl.DWFL')
    lvl, _, _ = compare(lib_r, lib_m, 'HL20Aero')
    if lvl == 'match':
        fails.append(('HL20Aero', 'cl.DBFUR<->cl.DWFL swap not caught'))

    for comp, why in fails:
        print(f"selftest FAIL {comp}: {why}")
    if fails:
        return 1
    print("selftest: all 9 real-model mutations rejected")
    return 0

def main(argv):
    args = argv[1:]
    if '--selftest' in args:
        return selftest()
    ref = DEFAULT_REF
    if '--ref' in args:
        i = args.index('--ref'); ref = args[i + 1]
        del args[i:i + 2]
    if len(args) == 4 and os.path.isdir(args[0]):
        refdir, curdir, _, comps = args[0], args[1], args[2], [args[3]]
    elif len(args) >= 2:
        curdir, comps = args[0], args[1:]
        refdir = resolve_ref(ref, curdir)
    else:
        print(__doc__); return 2
    lib_r = lib_sections(refdir)
    lib_c = lib_sections(curdir)
    worst = 0
    ar, ac = lib_analyses(refdir), lib_analyses(curdir)
    if ar != ac:
        worst = 2
        for k in sorted(set(ar) | set(ac)):
            if ar.get(k) != ac.get(k):
                print(f"analysis {k}: MISMATCH")
    for comp in comps:
        level, bok, info = compare(lib_r, lib_c, comp)
        if level is None:
            if 'missing in CUR' in info:
                print(info); worst = max(worst, 2)
            else:
                print(f"{comp}: NEW (not in {ref}; covered by the flattened "
                      f"comparison of components that instantiate it)")
            continue
        if level == 'match':
            status = 'MATCH'
        elif level == 'shape':
            status = 'MISMATCH (shape match only — internal endpoints differ)'
        else:
            status = 'MISMATCH'
        extra = '' if (level == 'match') == bok else \
            f" (boundary {'MATCH' if bok else 'MISMATCH'})"
        print(f"{comp}: flattened-graph {status}{extra}")
        if info and level != 'match': print(info)
        worst = max(worst, 0 if level == 'match' else 1)
    return worst

if __name__ == '__main__':
    sys.exit(main(sys.argv))
