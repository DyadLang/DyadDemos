# Diagram layout conventions

Conventions and helper tools used for the graphical (`connect` / placement
metadata) layout of the Dyad demos, e.g. HL20Demo. Paths below are relative to
the repository root.

## Tools

- `dyad compile <demo-dir>` — regenerates `<demo>/generated/*.jl` from
  `dyad/` sources. Required after any source change; the Julia package loads
  the generated code.
- `dyad render <Lib.Component> --dir <demo-dir>` — renders a diagram to SVG
  on stdout. `tools/svg2png.sh` converts SVG to PNG.
- `tools/dyad_summary.py <file.dyad>` — dumps instances, `connect`s and port
  boxes of a `.dyad` file.
- `tools/partition_check.py <ref-dir> <dyad-dir> <file> <Component>` — compares
  the flattened connection graph (internal endpoints included, sub-components
  flattened through) against a reference checkout, e.g. a `git worktree` of an
  earlier commit. Run it on every component whose file you touched.
- `tools/relayout.sh` — extract → edit → solve → apply pipeline around
  `dyad layout`; see also `edit_problem.py`, `fix_junction_order.py`,
  `verify_edges.py` in this directory.
- `tools/verify_edges.py <file.dyad>` — checks every `connect` still carries
  route (`edges`) metadata.
- `tools/aero_parity.jl <demo-dir> <inputs.csv> <report.txt>` — numeric parity
  of the aero stack against a reference.

## Conventions

- Boundary port glyphs are 50 units tall. Space port centers at least 100
  units apart, or the label under one glyph is covered by the next glyph in
  Studio. (Shrinking a port box toward its pin does not move the pin; moving a
  port along the boundary edge does, and every wire touching it must then be
  re-routed or its `edges` waypoints updated.)
- Grow many-pin block icons to roughly 50 units per pin.
- Place blocks and ports on 50-unit multiples where possible.
- All routes orthogonal; every `connect` must keep its `"edges"` route
  metadata. Multi-way connections use junction dots; the *flattened* wiring
  must not change.
- Components visible to the user need icon metadata plus connector
  placements; test and top-level components are exempt (see AGENTS.md).
- Keep component names and connector names/types/directions stable — test
  harnesses and generated code reference them.

## `dyad layout apply` caveats (Dyad 3.5.x)

- It rewrites the whole file and can drop comments and docstrings — always
  `git diff` afterwards and restore anything lost.
- It can attach multi-way arms to the wrong endpoints — run
  `tools/partition_check.py` after applying.
- It can write placements without `edges` — run `tools/verify_edges.py`.

## Gate per diagram

- No overlapping blocks or port glyphs, no wires through blocks or port
  glyphs, no diagonal segments, no false junctions (a wire end or bend
  touching another net), no label collisions.
- Port labels readable in a real Studio render, not just the tool metrics.
- `partition_check` MATCH for every component you touched.
