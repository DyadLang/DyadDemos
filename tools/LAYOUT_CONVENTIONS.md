# HL20Demo layout-pass conventions (read fully before editing)

Repo root: `/home/asinghvi17/.factory/runners/work/clones/543c6f9d-c49f-4e76-a948-379433e34403` (call it `$ROOT`).
All work happens in the shared checkout — edit `HL20Demo/dyad/**` in place. Do NOT commit; the coordinator commits.

## Toolchain (exact paths)

- Dyad CLI 3.5.0: `$ROOT/.cache/dyad-cli/dyad` (the PATH `dyad` is 3.6.0 — NEVER use it).
- Julia: `/home/asinghvi17/.julia/juliaup/julia-1.13.2+dyad-3x5x0.x64.linux.musl/bin/julia` — run with `--startup-file=no`.
- layout-report: `python3 $ROOT/.cache/layout-report/tools/layout-report/layout_report.py` (read its README for flags). Baseline report dir: `$ROOT/.cache/report-baseline/` (a `report.json` list).
- dyad-ui-shot: `node $ROOT/.cache/dyad-ui-shot/tools/dyad-ui-shot/dyad-ui-shot.mjs` (read its README; env `UISHOT_HOME=$ROOT/.cache/uishot`). Saves Studio PNGs. Example existing output: `$ROOT/.cache/shots/`.
- dyad render (SVG): `DYAD=$ROOT/.cache/dyad-cli/dyad; cd HL20Demo && $DYAD render <Lib.Component>` → stdout SVG. Convert with `$ROOT/tools/svg2png.sh`.
- relayout helper: `HL20Demo/tools/relayout.sh` (extract → edit_problem → solve → fix_junction_order → apply → verify_edges → render). Read it and `HL20Demo/tools/edit_problem.py`, `fix_junction_order.py`, `verify_edges.py` before using.

## Verification tools (already built — use them)

- `python3 $ROOT/tools/partition_check.py $ROOT/.cache/ref-dyad $ROOT/HL20Demo/dyad <file> <Component>`
  Compares FLATTENED connectivity (through same-library sub-components) vs the
  pristine baseline snapshot at `.cache/ref-dyad`. The induced partition on the
  component's boundary pins must MATCH. Run it for every component you touch.
  It catches Dyad-3.5 `layout apply` multi-way-arm miswiring too.
- Numeric parity: `julia --startup-file=no $ROOT/tools/aero_parity.jl HL20Demo <inputs.csv> <report.txt>`
  (only needed if you touch anything under `shared/` reachable from HL20Aero).
- `python3 $ROOT/tools/dyad_summary.py <file.dyad>` — dumps instances/connects/port boxes.
- Generated tests: `cd $ROOT/HL20Demo && julia --project=. test/runtests.jl` is the full suite; targeted generated test files live under `HL20Demo/generated/` and `HL20Demo/test/`.

## File anatomy

- `HL20Demo/dyad/*.dyad`: each file is a Dyad library file containing one or more `component Name ... end` blocks. Graphical metadata lives in Dyad analysis/annotation strings (JSON-ish `[Layout]`/`connect(...)` metadata embedded in the source). `layout apply` can REWRITE whole files — always `git diff` after apply and restore lost comments/equation formatting if any.
- Port glyphs: `name = RealInput() { ... metadata with box/edge placement ... }`.

## Conventions (decided by measurement, follow exactly)

- Boundary port glyphs: 50 units tall is legal and renders correctly in Studio.
  HOWEVER port centers must be spaced ≥100 units apart or labels/glyphs crowd.
  Shrinking a port box toward its pin edge does NOT move the pin — no re-route needed.
- Moving a port along the boundary edge moves its pin → all wires touching it must be re-routed (store correct ends or re-run apply).
- Grow many-pin block icons to ≈50 units per pin before solving.
- All placements on 50-unit multiples.
- New sub-components: same `HL20Demo` library (a file in `HL20Demo/dyad/` or `dyad/shared/`), must have icon metadata + connector placements (components the user can see need graphical metadata; test/toplevel components are exempt), laid out bottom-up with the same conventions, and their own clean internal diagram.
- Keep every existing component's NAME and external connector names/types/directions unchanged — harnesses and generated tests reference them.
- Keep the MATH identical: same equations, same parameters, same connectivity semantics. You may move equations into a sub-component only when the parent instantiates it and wires the same signals.

## Known Dyad 3.5.0 bugs (work around)

- `layout apply` can attach multi-way connect arms to the wrong ends → always run partition_check after apply.
- `apply` sometimes writes placements but no edges → run `HL20Demo/tools/verify_edges.py`; re-run apply if needed.
- `apply` rewrites whole files → diff and restore lost comments.
- `routingRefinement>0` can move locked blocks; `above/order` constraints can be silently overridden — verify visually.

## Compile/eval isolation (IMPORTANT — shared checkout)

`HL20Demo/generated/*.jl` is produced by `dyad compile .` and the Julia package
loads generated code — so `using HL20Demo` only sees dyad-source changes after a
recompile. Several agents edit concurrently: do NOT run `dyad compile .` in the
shared tree and do NOT touch `HL20Demo/generated/`. Instead:

```
cp -r $ROOT/HL20Demo $ROOT/.cache/work-<yourname>/
cd $ROOT/.cache/work-<yourname> && $ROOT/.cache/dyad-cli/dyad compile .
julia --startup-file=no --project=$ROOT/.cache/work-<yourname> -e 'using HL20Demo'   # reuses depot
```
Copy your edited `.dyad` files from the shared tree into the scratch copy before
compiling (or edit in scratch then copy back — but only YOUR files). For
partition_check/eval parity, the scratch copy's `dyad/` dir and its compiled
package both work. To run Julia against the scratch package:
`Pkg.activate("$ROOT/.cache/work-<yourname>")` then `using HL20Demo`.

Serialized access: wrap `dyad-ui-shot` invocations in
`flock $ROOT/.cache/uishot.lock -c '<cmd>'` — Studio instances can collide.

## Gate (per diagram, before you report done)

- `layout-report` on the component: 0 overlapping ports/blocks, 0 wires through blocks or port glyphs, 0 diagonals, 0 false junctions, shared runs only when the wires genuinely share a segment.
- `dyad-ui-shot` PNG: LOOK at it (read the PNG). Every port label readable and horizontal, no rotated labels, icons not touching labels.
- Crossing target: top-level ≈≤80; sub-components well under. If genuinely impossible, record the number and a one-line reason for LAYOUT_NOTES.md.
- `partition_check` MATCH for every touched component.
- `verify_edges.py` clean on every file `apply` touched.
