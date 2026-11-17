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

COMPSTART = re.compile(r'\n((?:(?:abstract|test)\s+)?(?:component|model|connector|record|block)\s+)(\w+)')
DEFAULT_REF = '2e80df8'

# Reviewed endpoint renames: RENAMES[component][ref_path] = cur_path, where
# each path is a canonical flattened endpoint or an instance-path prefix of
# one (a match on PATH itself or on PATH.<anything> is rewritten). Use it
# ONLY for a deliberate rename or extraction the reviewer has signed off
# on; every entry must be justified in review. An empty table means no
# rename is accepted anywhere.
RENAMES = {}

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
                secs[name] = text[pos:end]
    return secs

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

def canon_nets(nets, comp, lib, newpaths):
    imapcache = {}
    def imaps(c):
        if c not in imapcache: imapcache[c] = instances(lib[c], lib)
        return imapcache[c]
    out = set()
    for net in nets:
        cn = frozenset(c for c in
                       (canon_ep(ep, comp, lib, newpaths, imaps) for ep in net)
                       if c is not None)
        out.add(cn)
    return frozenset(out)

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

def full_partition(comp, lib, other_lib):
    nr = flat_nets(comp, frozenset(lib.items()))
    newpaths = inst_paths(comp, lib) - inst_paths(comp, other_lib)
    return canon_nets(nr, comp, lib, newpaths), nr

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
    def ren(ep):
        for old, new in table.items():
            if ep == old: return new
            if ep.startswith(old + '.'): return new + ep[len(old):]
        return ep
    return frozenset(frozenset(ren(ep) for ep in net) for net in nets)

def compare(reflib, curlib, comp):
    """return (level, boundary_ok, diff_info) where level is
    'match' | 'shape' | 'mismatch' | None(component missing).
    'match' is exact after canonicalisation and RENAMES. 'shape' (same
    net signatures, different internal endpoints) is reported for
    diagnosis but is a gate failure like 'mismatch'."""
    if comp not in reflib: return None, None, f"{comp} missing in REF"
    if comp not in curlib: return None, None, f"{comp} missing in CUR"
    cr, nr = full_partition(comp, reflib, curlib)
    cc, nc = full_partition(comp, curlib, reflib)
    cr = apply_renames(cr, comp)
    ok = cr == cc
    shape = shape_partition(cr) == shape_partition(cc)
    br = boundary_partition(flat_nets(comp, frozenset(reflib.items())))
    bc = boundary_partition(flat_nets(comp, frozenset(curlib.items())))
    info = []
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
    return ('match' if ok else 'shape' if shape else 'mismatch'), br == bc, \
        '\n'.join(info)

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
    # though the result changes. It must now FAIL.
    ref_inline = """component QuatToBody
  a = RealInput()
  b = RealInput()
  y1 = RealOutput()
  y2 = RealOutput()
  s1 = Src()
  s2 = Src()
  p11 = Prod()
  p12 = Prod()
relations
  connect(a, s1.u)
  connect(b, s2.u)
  connect(s1.y, p11.u)
  connect(s2.y, p12.u)
  connect(p11.y, y1)
  connect(p12.y, y2)
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
  connect(s1.y, mv.a12)
  connect(s2.y, mv.a11)
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
    lvl, _, info = compare(lib_r, lib_c, 'QuatToBody')
    shape_ok = shape_partition(full_partition('QuatToBody', lib_r, lib_c)[0]) == \
        shape_partition(full_partition('QuatToBody', lib_c, lib_r)[0])
    print(f"selftest: extracted-swap level={lvl} (shapes {'equal' if shape_ok else 'differ'})")
    if lvl == 'shape' and shape_ok:
        print("selftest PASS: same-shape rewire reported as 'shape', which fails the gate")
        return 0
    if lvl == 'mismatch':
        print("selftest PASS: same-shape rewire reported as mismatch (fails the gate)")
        return 0
    print("selftest FAIL: same-shape rewire was not flagged")
    print(info)
    return 1

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
