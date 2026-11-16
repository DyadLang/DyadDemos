#!/usr/bin/env python3
"""partition_check.py — compare FLATTENED connectivity of a component against
a reference version. Connectivity is flattened through sub-components (any
component defined in the same library dir whose instance pin `inst.p` is
rewired to that component's internal nets as `inst.<inner>`), then the induced
partition on top-level boundary pins (dot-less endpoints) is compared. The
flattened partition must map bijectively: every net's boundary-pin set must
match a reference net exactly.

usage: partition_check.py DYADDIR_REF DYADDIR_CUR COMPONENTFILE COMPONENT
Both dirs are the .../dyad directory of a checkout; COMPONENTFILE is the file
basename containing COMPONENT (searched recursively).
"""
import os, re, sys, functools

COMPSTART = re.compile(r'\n((?:(?:abstract|test)\s+)?(?:component|model|connector|record|block)\s+)(\w+)')

def lib_sections(dyaddir):
    secs = {}
    for root, _, files in os.walk(dyaddir):
        for f in files:
            if not f.endswith('.dyad'): continue
            text = open(os.path.join(root, f)).read()
            marks = [(m.start() + 1, m.group(2)) for m in COMPSTART.finditer('\n' + text)]
            # also catch a component at file start
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
    """instance name -> component type, for lines like `name = Comp(...)` or
    `name: Comp` / `name = sub.Comp` declarations."""
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

def boundary_partition(nets):
    """map: frozenset(boundary pins) per net (only nets touching a boundary pin)."""
    out = {}
    for net in nets:
        b = frozenset(n for n in net if '.' not in n)
        if b: out[net] = b
    return frozenset(out.values())

def main():
    refdir, curdir, _, comp = sys.argv[1:5]
    lib_r = lib_sections(refdir); lib_c = lib_sections(curdir)
    if comp not in lib_r: print(f"{comp} missing in REF"); sys.exit(2)
    if comp not in lib_c: print(f"{comp} missing in CUR"); sys.exit(2)
    nr = flat_nets(comp, frozenset(lib_r.items()))
    nc = flat_nets(comp, frozenset(lib_c.items()))
    br, bc = boundary_partition(nr), boundary_partition(nc)
    ok = br == bc
    print(f"{comp}: {len(nr)} ref nets, {len(nc)} cur nets -> boundary {'MATCH' if ok else 'MISMATCH'}")
    if not ok:
        for b in br - bc: print("  only REF:", sorted(b))
        for b in bc - br: print("  only CUR:", sorted(b))
    sys.exit(0 if ok else 1)

main()
