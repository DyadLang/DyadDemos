#!/usr/bin/env python3
"""Small helpers to edit the JSON metadata of one component definition in a .dyad file.

Only metadata is touched: `{^tag}` link tags on declarations and the
`metadata { ... }` block of the component.  Equations/connections are never edited.
"""
import json
import re


def _block(src, comp):
    m = re.search(r'^\s*(?:test |example |partial )*component ' + re.escape(comp) + r'\b', src, re.M)
    if not m:
        raise SystemExit(f'component {comp} not found')
    e = re.search(r'^end\b', src[m.end():], re.M)
    return m.start(), m.end() + e.start()


def _match_brace(s, i):
    """s[i] == '{'; return index of matching '}' (JSON-aware)."""
    depth = 0
    instr = False
    esc = False
    for j in range(i, len(s)):
        c = s[j]
        if instr:
            if esc:
                esc = False
            elif c == '\\':
                esc = True
            elif c == '"':
                instr = False
            continue
        if c == '"':
            instr = True
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return j
    raise SystemExit('unbalanced braces')


def load(path, comp):
    src = open(path).read()
    a, b = _block(src, comp)
    blk = src[a:b]
    m = re.search(r'^metadata\s*\{', blk, re.M)
    if m:
        i = a + m.end() - 1
        j = _match_brace(src, i)
        meta = json.loads(src[i:j + 1])
        span = (a + m.start(), j + 1)
    else:
        meta = {}
        span = None
    return src, meta, span, (a, b)


def ensure_tags(src, comp, names):
    """Add `{^name}` to `name = X(...)` declarations in comp that have no metadata."""
    a, b = _block(src, comp)
    blk = src[a:b]
    for n in names:
        pat = re.compile(r'^(\s*' + re.escape(n) + r'\s*=\s*[A-Za-z_][\w.]*\((?:[^()\n]|\([^()\n]*\))*\))[ \t]*$', re.M)
        blk, k = pat.subn(lambda mm: mm.group(1) + ' {^' + n + '}', blk, count=1)
    return src[:a] + blk + src[b:]


def save(path, comp, meta):
    src = open(path).read()
    _, _, span, (a, b) = load(path, comp)
    text = 'metadata ' + json.dumps(meta, indent=2, ensure_ascii=False) + '\n'
    if span:
        src = src[:span[0]] + text.rstrip('\n') + src[span[1]:]
    else:
        src = src[:b] + text + src[b:]
    open(path, 'w').write(src)


def link(meta, name):
    return meta.setdefault('_links', {}).setdefault(name, {}).setdefault('Dyad', {})
