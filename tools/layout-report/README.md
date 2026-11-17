# layout-report

Measures how readable Dyad component diagrams are, and ranks them worst first.

It measures the diagram **as Dyad Studio draws it**: `dyad render` gives every
wire with its real port endpoints, every block, every connector glyph (boundary
ports and the ports of each block), and the labels; the tool then places them
the way Studio's diagram view does (see [Studio geometry](#studio-geometry)),
not the way `dyad render` stretches them. The `.dyad` source says which
`connect()` statements have route metadata, and names instances, boundary
ports and block ports. Optionally, the tool also runs `dyad layout extract`
and dyad-layout's own WASM scorer, so the solver's crossing and illegal-route
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
- `cache/<diagram>.render.log`, `.extract.log`, `.solve.log`: the full dyad
  output of a step that failed. The report keeps the first error and its
  message; the log keeps everything.
- `cache/<diagram>.overlay.svg`: a plain schematic of the measured geometry
  with every finding marked: placement boxes dashed, icons and glyphs as Studio
  draws them. Red dots are crossings, magenta rings are false junctions, red
  lines go through a block or a glyph, orange lines mark a run shared by two
  nets, orange boxes a glyph finding, purple boxes a covered label, orange
  rings a junction on a glyph and green lines a near-diagonal segment. Open it
  in a browser.

Requirements:

- Python 3.9 or newer, standard library only. The tests run on 3.9, 3.11 and
  3.12.
- The Dyad CLI (`--dyad`, default `$DYAD` or `dyad`) with a working
  `JULIA_EXECUTABLE`, as for any `dyad` command. It is needed for anything
  except `--svg`.
- For `--dyad-layout-wasm`: Node 18 or newer and the `wasm/pkg` directory of
  [JuliaComputing/dyad-layout](https://github.com/JuliaComputing/dyad-layout).
  The repository is private. The Dyad 3.5.0 CLI ships dyad-layout 0.1.1:
  `gh repo clone JuliaComputing/dyad-layout -- --branch v0.1.1 --depth 1`.
  The tool checks the sha256 of `dyad_layout_wasm_bg.wasm` and
  `dyad_layout_wasm.js` against the builds it pins (`PINNED_SCORERS`; v0.1.1,
  whose `version()` reports `0.0.1`) and refuses other builds unless you pass
  `--allow-unpinned-scorer`. If the scorer is missing, unpinned or Node is not
  installed, the geometry metrics are still measured, and `report.md` says
  why the scorer did not run.

Run the tests with `python3 -m unittest tools/layout-report/test_layout_report.py`.
Set `LAYOUT_REPORT_WASM` to dyad-layout's `wasm/pkg` to also run the test
against the real scorer. `fixtures/` holds gzipped `dyad render` output of 19
HL20Demo diagrams (at 99ffbc0, draft PR #51) with the counts the glyph checks
must give (`expected.json`) and the geometry Studio drew for them
(`studio.json`, see [Calibration](#calibration)).

## Metrics

Lengths are in Dyad diagram units. A dyad-layout half-square is 50 units.

| column | meaning |
|---|---|
| `X` | crossings between wires of different nets. Wires that share an endpoint or a junction dot are one net. |
| `T` | false junctions: a wire end or bend lying on another net's wire. It reads as a connection. |
| `ovl` | collinear runs shared by two different nets. dyad-layout counts these as illegal routes. |
| `thru` | (wire, block) pairs where the wire passes through a block's placement box. |
| `thru glyph` | `wire_thru_glyph`: (wire, glyph) pairs where the wire crosses a connector glyph it is not wired to. See [Glyph checks](#glyph-checks). `report.json` also keeps `wire_through_port`, the boundary-port part of it. |
| `diag` | non-orthogonal segments. Stale routes and pins off the routing lattice cause them. |
| `near diag` | `near_diagonal`: segments 0.001 to 0.5 units off the horizontal or vertical, too little for `diag`. A waypoint rounded to the grid against a pin that is not (`y 561.42` against `561.4`). Studio draws them as a hairline slope. |
| `g ovl` | `glyph_overlap`: glyph pairs that overlap or touch, and glyphs lying on another block's icon. |
| `g detach` | `glyph_detached`: a block's glyphs that are off the icon Studio draws. |
| `g hang` | `glyph_overhang`: a block's glyphs past the end of their side of the icon, or standing far out of it. |
| `lbl/glyph` | `label_covered`: labels a glyph lies on. |
| `jct/glyph` | `junction_on_glyph`: junction dots on a glyph. |
| `unrt` | `connect()` statements with no route metadata (the 3.5.0 `apply` bug, or never laid out). Connects inside `for` loops are counted separately, as `loop_connects`. |
| `blk ovl` | overlapping block placement boxes or boundary-port glyphs. |
| `lbl/blk`, `lbl/lbl`, `lbl/wire` | block labels (instance names, parameter values) and free diagram text overlapping a block, another label, or a wire. Label boxes are placed and sized as Studio draws them (see [Studio geometry](#studio-geometry)). |
| `bends/w`, `bends max` | bends per wire. |
| `jogs` | interior segments shorter than 10 units (staircase noise). |
| `len`, `len max` | total and longest wire length. |
| `detours` | wires at least 2.5× their endpoints' Manhattan distance, and at least 200 units long. |
| `outer` | wires that leave the bounding box of the blocks and ports by more than 30 units, i.e. routed round the outside. |
| `white`, `gap` | fraction of 50×50 cells with no block, label or wire, and the side of the largest empty square. |
| `aspect` | width / height of everything drawn. |
| `pitch` | the closest two pins on different nets. Under about 10 units the pins are unreadable and the block is too small for its pin count. |
| `dl X`, `dl illegal`, `dl turns`, `dl spacing` | dyad-layout's own `score_existing_solution` on the drawn routes. `illegal` = overlapping runs + fallback routes. A `*` marks a partial score (see `dl unmatched`). |
| `dl unmatched` | problem connections no drawn wire was matched to. They are left out of the drawn-route score, never replaced by an invented route. |
| `reroute X`, `reroute illegal` | dyad-layout's `score_layout`: the same placements, routed by its own router. If this is far below `dl X`, the routes are the problem. If it is about the same, the placement is. |

`bad` (badness) is the ranking key. It is a plain weighted sum:

```
20 × (ovl + T + thru + diag + blk ovl) + 5 × unrt + 3 × X
+ 10 × (g ovl + g detach + thru glyph + jct/glyph)
+ 5 × (g hang + lbl/glyph + near diag)
+ 2 × (lbl/blk + lbl/lbl + outer + detours)
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

## Studio geometry

`dyad render` and Dyad Studio draw the same placement boxes differently, and
the defects people see are in Studio's drawing. Studio 3.5.1's diagram view
(checked against its DOM, see [Calibration](#calibration)):

- **Icons keep their aspect ratio.** A block's icon is fitted into its
  placement box, centred (SVG `xMidYMid meet`). `dyad render` stretches it to
  the box. A 200 × 800 block is drawn as a 200 × 200 square in the middle of
  its box.
- **Connector glyphs are placed on the box, not on the icon.** A block port's
  frame is its icon placement (`x1..x2`, `y1..y2` on the 0..1000 icon),
  mapped through the block's box, so it stretches with the box. The glyph is
  fitted into that frame, aspect ratio kept. In a stretched box the pins on
  the long sides float away from the square icon. Wires attach at the centre of
  the frame.
- **Every frame is 1000 units.** A connector icon's `<svg width="210"
  height="210">` does not change where it is drawn: a boundary port's glyph
  fills its placement box. (Before this, the tool read boundary ports at a
  fifth of their size, in the top-left corner of their box.)
- **Labels are a fixed size.** 20-unit text, 24-unit line, centred on the
  label's anchor: (500, 1100) of a block's icon by default, mapped through the
  box and turned with it, but drawn upright. A boundary port's name is drawn at
  (500, 1100) of its box grown by 20 units on every side, i.e. 24 units lower
  than a block's. Label widths use per-character advances fitted to 1150
  labels Studio drew (within 3 units for 90% of them).

The glyph's outline is the convex hull of its icon's shapes (`polygon`,
`rect`, `circle` and so on; the triangle of `RealInput`), or the fitted square
when the icon uses paths or text. Port names come from the component
definitions: the library's own `.dyad` files, then the newest version of each
package in the Julia depot. Unresolved ones are numbered (`b.#2`); only the
report text depends on the names.

## Glyph checks

All in diagram units. A glyph's size is the shorter side of its box.

| class | a finding is | tolerance |
|---|---|---|
| `glyph_overlap` | two glyphs whose outlines overlap or are closer than a tenth of the smaller one's size (touching triangles in a column); or a glyph reaching more than 1 unit into another block's icon. Two **unwired** glyphs of the same block are left out: their placement is the child component's icon design, not this diagram's layout. They are counted in `glyph_overlap_unwired`, which is reported but not in the badness. | `GLYPH_GAP` 0.1, `BODY_DEPTH` 1 |
| `glyph_detached` | a block's glyph further from the icon Studio draws than a quarter of its size, and at least 2 units. | `DETACH_GAP` 0.25 |
| `glyph_overhang` | a block's glyph (that is not detached) with more than half its length past the end of the side it sits on, or more than 75% of its area outside the icon while sticking out more than 30 units. BlockComponents' own pins stand just outside their block (`x1 = -100, x2 = 0`, 10 units out on a 100-unit block), so standing outside is only a finding for a big glyph. | `OVERHANG` 0.5, `OVERHANG_OUT` (0.75, 30) |
| `label_covered` | a label (block, boundary port, or free text) with more than 60 square units (a quarter of a character) under a glyph's outline. A block's own glyphs over its own labels are left out: Studio's default label position (500, 1100) is where a bottom pin is, by the child's design. | `LABEL_COVER` 60 |
| `wire_thru_glyph` | a wire running inside a glyph's outline for more than a quarter of the glyph's size (and 1 unit), when neither end of the wire is in the glyph's frame and the glyph is not wired to the wire's net. | `THRU_GLYPH` 0.25 |
| `junction_on_glyph` | a junction dot (radius 2.5) touching a glyph's outline. | `JUNCTION_R` 2.5 |
| `near_diagonal` | a segment off the horizontal or vertical by more than 0.001 and at most 0.5 units. | `NEAR_DIAG` (0.001, 0.5) |

`wire_thru_glyph` and `junction_on_glyph` skip glyphs smaller than 20 units
(`MIN_GLYPH`): the 10-unit pins of a standard 100-unit block, which every
wire to the pin runs over, and which a junction dot at the pin covers.

At 99ffbc0 (draft PR #51), the checks flag every glyph defect listed for the
HL20Demo diagrams in Studio screenshots, and nothing in the diagrams that look
clean there. On the relaid demos of PR #49 (f47214b) they flag only
FrictionBrakeDemo.BrakeThermalTest_Step: Studio draws its two step sources'
outputs and its heat inputs' ports away from their icons, so the findings are
real.

## Calibration

`studio_geometry.py` compares this model with what Studio drew. It reads
DOM dumps of Studio's diagram view and the renders of the same diagrams. To
make a dump, evaluate `studio_dom_dump.js` in the page of `tools/dyad-ui-shot`
(branch `tools/dyad-ui-shot`) once `captureDiagram` has settled the diagram,
and save the result as `<diagram>.dom.json`. dyad-ui-shot has no option for
this yet; the calibration used a two-line local patch after its capture step.

```sh
python3 tools/layout-report/studio_geometry.py --dom DUMPS --svg OUT/cache --lib HL20Demo
```

It lists every icon, glyph and label that is more than `--tol` (1) unit off.
All 43 HL20Demo diagrams at 99ffbc0 match within 1 unit. Icons whose artwork
does not fill their viewBox are drawn smaller than the fitted square the tool
uses (FrictionBrakeDemo's heat sources). The tool keeps the square, so
`glyph_detached` errs on the side of not flagging. `--fixture` writes the
compact geometry the unit tests compare with.

## How the dyad-layout scoring works

`--dyad-layout-wasm` converts the drawn diagram into a dyad-layout
`LayoutSolution`:

- block centres come from the render, D4 states from the extracted problem
  (dyad-layout's names: `identity`, `r90`, `r180`, `r270`, `flipH`, `flipV`,
  `flipH_r90`, `flipV_r90`; any other state is an error);
- coordinates are divided by 50 and shifted by the origin that `extract` used;
- each drawn wire becomes the route of the problem connection whose two
  connector positions are nearest its two ends.

The result is passed to `score_existing_solution_json` and
`score_layout_json` (`dyad_layout_score.mjs`). Connections that no drawn
wire matched get no route. `dl_status` in `report.json` is `complete`,
`partial` (some connections unmatched: `dl_unmatched` counts them and
`dyad_layout.unmatchedIds` names them) or `unavailable` (nothing scored, with
`dyad_layout.error` saying why). `report.md` lists the partial and unscored
diagrams under *dyad-layout scorer*. The re-routed score (`reroute X`) uses
only the placements, so it covers every connection. If re-routing fails,
`dyad_layout.reroutedError` in `report.json` and the *dyad-layout scorer*
section of `report.md` say why.

## How the SVG is read

Transforms are composed down the tree: `translate`, `scale`, `rotate` and
`matrix` on any element (the `<svg>` elements, block icons and labels
included), `transform-origin="center"`, and nested `<svg>` viewports (`x`,
`y`, `width`, `height`, `viewBox`, with the default `preserveAspectRatio`; a
missing width or height is the parent viewport's). Groups are classified by
what they hold, not by how they are wrapped. A `<g>` with a direct `<svg>`
child and no wire anywhere inside it is a block (with a drop shadow) or a
boundary port (without one), as `dyad render` draws them. Inside a block's
frame, the first `<g>` holding an `<svg>` and covering the whole frame is its
icon, and every other one is a connector glyph. A label's own `rotate()` is
about its centre (the icon's CSS sets `transform-origin: center` on text), so
it keeps the label upright and does not move its anchor. Any other `<g>`,
including one that wraps wires in a nested `<svg>`, is a plain group, and
the wires, junction dots and labels in it are measured like top-level ones.
Before contacts are classified, every
wire polyline is normalised: repeated vertices and vertices in the middle of
a straight run are dropped, and the shared runs of two wires are merged
before they are counted, so a waypoint that does not bend the wire does not
change the result. Structures the parser does not model (`<use>`,
`<image>`, `skewX`/`skewY` or malformed transforms, a nested `<svg>` viewBox
whose size cannot be known, other `preserveAspectRatio` values) are rejected
with an error instead of being measured wrongly.

## Limitations

- Label widths are estimated from per-character advances fitted to Studio's
  font, not measured.
- The icon body is the icon fitted into its box, not its ink: icon artwork
  drawn with paths is taken to fill its viewBox.
- Diagrams whose connections only exist inside `for` loops draw no wires.
  Their metrics are empty apart from `loop_connects`.
- A component whose render fails (for example, a `connect` to a nested
  connector) is listed under *Failed* with the compiler's error.
