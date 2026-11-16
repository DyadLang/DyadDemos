# layout-report

Measures how readable Dyad component diagrams are, and ranks them worst first.

It measures the diagram **as Dyad draws it**: `dyad render` gives every wire
with its real port endpoints, every block and boundary-port glyph, and the
labels. The `.dyad` source says which `connect()` statements have route
metadata. Optionally, the tool also runs `dyad layout extract` and
dyad-layout's own WASM scorer, so the solver's crossing and illegal-route
counts appear next to the tool's own.

```sh
# every diagram in one library
python3 tools/layout-report/layout_report.py --dir HL20Demo -o /tmp/hl20-report

# a few components, with dyad-layout's own objective on the same geometry
python3 tools/layout-report/layout_report.py --dir HL20Demo -c HL20Vehicle -c QuatToBody \
    --extract --dyad-layout-wasm ../dyad-layout/wasm/pkg -o /tmp/r

# every library under the repository root, four at a time
python3 tools/layout-report/layout_report.py --root . -j 4 -o /tmp/all

# a rendered SVG you already have (no dyad needed)
python3 tools/layout-report/layout_report.py --svg Foo.svg -o /tmp/r
```

Output in `-o DIR`:

- `report.md`: a worst-first list with the reasons, a sortable table of
  every diagram (`--sort METRIC`), and details for the worst
  (`--worst N`): the wires with the most crossings, wires through blocks,
  label clashes and detours.
- `report.json`: every metric and detail per diagram, plus dyad-layout's
  full objective when it was run.
- `cache/<diagram>.svg`, the `dyad render` output. `--reuse` skips
  re-rendering.
- `cache/<diagram>.problem.json`: the `dyad layout extract` output, with
  `--extract`.
- `cache/<diagram>.overlay.svg`: a plain schematic of the measured geometry
  with every finding marked. Red dots are crossings, magenta rings are false
  junctions, red lines go through a block, and orange marks a run shared by
  two nets. Open it in a browser.

Requirements:

- Python 3.9 or newer, standard library only.
- The Dyad CLI (`--dyad`, default `$DYAD` or `dyad`) with a working
  `JULIA_EXECUTABLE`, as for any `dyad` command. It is needed for anything
  except `--svg`.
- For `--dyad-layout-wasm`: Node 18 or newer and the `wasm/pkg` directory of
  [JuliaComputing/dyad-layout](https://github.com/JuliaComputing/dyad-layout).
  The repository is private. The Dyad 3.5.0 CLI ships dyad-layout 0.1.1:
  `gh repo clone JuliaComputing/dyad-layout -- --branch v0.1.1 --depth 1`.

Run the tests with `python3 -m unittest tools/layout-report/test_layout_report.py`.

## Metrics

Lengths are in Dyad diagram units. A dyad-layout half-square is 50 units.

| column | meaning |
|---|---|
| `X` | crossings between wires of different nets. Wires that share an endpoint or a junction dot are one net. |
| `T` | false junctions: a wire end or bend lying on another net's wire. It reads as a connection. |
| `ovl` | collinear runs shared by two different nets. dyad-layout counts these as illegal routes. |
| `thru` | (wire, block) pairs where the wire passes through a block body. |
| `thru port` | the same, through another boundary port's glyph. This usually means port glyphs overlap. |
| `diag` | non-orthogonal segments. Stale routes and pins off the routing lattice cause them. |
| `unrt` | `connect()` statements with no route metadata (the 3.5.0 `apply` bug, or never laid out). Connects inside `for` loops are counted separately, as `loop_connects`. |
| `blk ovl` | overlapping block or port glyph boxes. |
| `lbl/blk`, `lbl/lbl`, `lbl/wire` | labels (instance names, parameter values, free diagram text) overlapping a block, another label, or a wire. Label boxes are estimated at 0.6 × font size per character. |
| `bends/w`, `bends max` | bends per wire. |
| `jogs` | interior segments shorter than 10 units (staircase noise). |
| `len`, `len max` | total and longest wire length. |
| `detours` | wires at least 2.5× their endpoints' Manhattan distance, and at least 200 units long. |
| `outer` | wires that leave the bounding box of the blocks and ports by more than 30 units, i.e. routed round the outside. |
| `white`, `gap` | fraction of 50×50 cells with no block, label or wire, and the side of the largest empty square. |
| `aspect` | width / height of everything drawn. |
| `pitch` | the closest two pins on different nets. Under about 10 units the pins are unreadable and the block is too small for its pin count. |
| `dl X`, `dl illegal`, `dl turns`, `dl spacing` | dyad-layout's own `score_existing_solution` on the drawn routes. `illegal` = overlapping runs + fallback routes. |
| `reroute X`, `reroute illegal` | dyad-layout's `score_layout`: the same placements, routed by its own router. If this is far below `dl X`, the routes are the problem. If it is about the same, the placement is. |

`bad` (badness) is the ranking key. It is a plain weighted sum:

```
20 × (ovl + T + thru + diag + blk ovl) + 5 × unrt + 3 × X
+ 2 × (lbl/blk + lbl/lbl + thru port + outer + detours)
+ 0.5 × (lbl/wire + jogs) + 0.25 × total bends
+ 100 × max(0, white − 0.6) + 10 if pitch < 10
```

Defects that make a diagram wrong to read (a wire through a block, a false
junction) outweigh ones that only make it busy. Sort by any other column with
`--sort`.

The tool's crossing count and dyad-layout's agree to within a few on every
HL20Demo diagram (310 against 312 on HL20Vehicle, 805 against 807 on
HL20Aero). The small differences are in how touches at shared pins are
counted.

## How the dyad-layout scoring works

`--dyad-layout-wasm` converts the drawn diagram into a dyad-layout
`LayoutSolution`:

- block centres come from the render, D4 states from the extracted problem;
- coordinates are divided by 50 and shifted by the origin that `extract` used;
- each drawn wire becomes the route of the problem connection whose two
  connector positions are nearest its two ends.

The result is passed to `score_existing_solution_json` and
`score_layout_json` (`dyad_layout_score.mjs`). `dl_unmatched` in
`report.json` counts problem connections no drawn wire matched.

## Limitations

- Label sizes are estimated, not measured; the font is not known.
- Diagrams whose connections only exist inside `for` loops draw no wires.
  Their metrics are empty apart from `loop_connects`.
- A component whose render fails (for example, a `connect` to a nested
  connector) is listed under *Failed* with the compiler's error.
