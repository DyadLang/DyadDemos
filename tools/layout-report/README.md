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

The exit status is 1 if any diagram could not be rendered or measured (they
are listed under *Failed* in `report.md`), so a CI gate notices; pass
`--allow-failures` to exit 0 anyway.

Output in `-o DIR`:

- `report.md`: a worst-first list with the reasons, a sortable table of
  every diagram (`--sort METRIC`), and details for the worst
  (`--worst N`): the wires with the most crossings, wires through blocks,
  label clashes and detours. *Estimated icon ink* lists the icons whose drawn
  shapes could only be estimated (see [Studio geometry](#studio-geometry)).
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
  nets, orange boxes a glyph finding (dashed: unwired glyphs piled up by the
  child's icon), purple boxes a covered label, orange
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
against the real scorer. `fixtures/` holds gzipped `dyad render` output of 23
HL20Demo diagrams (at 99ffbc0, draft PR #51) and DynamicSteadyState.ZoneRoom
(PR #49, f47214b) with the counts the glyph checks
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
| `thru glyph` | `wire_thru_glyph`: (wire, glyph) pairs where a wire of another net runs through a connector glyph. See [Glyph checks](#glyph-checks). `report.json` also keeps `wire_through_port`, the boundary-port part of it. |
| `diag` | non-orthogonal segments. Stale routes and pins off the routing lattice cause them. |
| `near diag` | `near_diagonal`: segments 0.001 to 0.5 units off the horizontal or vertical, too little for `diag`. A waypoint rounded to the grid against a pin that is not (`y 561.42` against `561.4`). Studio draws them as a hairline slope. |
| `g ovl` | `glyph_overlap`: glyph pairs that overlap or touch, and glyphs lying on another block's icon. |
| `g ovl unw` | `glyph_overlap_unwired`: unwired glyphs of one block piled up by its icon (the child component's doing). |
| `g detach` | `glyph_detached`: a block's glyphs that are off the icon Studio draws. |
| `g hang` | `glyph_overhang`: a block's glyphs past the end of their side of the icon, or standing far out of it. |
| `lbl/glyph` | `label_covered`: labels a glyph lies on. |
| `lbl/icon` | `label_covered_by_icon`: labels under their own block's glyph as much as at the block's default size (the child component's icon puts the glyph there). |
| `jct/glyph` | `junction_on_glyph`: junction dots on a glyph. |
| `unrt` | `connect()` statements with no route metadata (the 3.5.0 `apply` bug, or never laid out). Connects inside `for` loops are counted separately, as `loop_connects`. |
| `blk ovl` | overlapping block placement boxes or boundary-port glyphs. |
| `lbl/blk`, `lbl/lbl`, `lbl/wire` | labels overlapping a block, another label, or a wire: block labels (instance names, parameter values), boundary-port names and free diagram text. One block's own labels are not tested against each other. Labels collide by their text's ink, not their line box (see [Studio geometry](#studio-geometry)). A wire hits a label when it runs more than a unit through the ink grown by half the width of Studio's 1.5-unit wire (`WIRE_HALF`): a wire through the line box's padding around the text is not a hit. `report.json` names the labels a wire runs through (`labels_hit_by_wires`). |
| `bends/w`, `bends max` | bends per wire. |
| `jogs` | interior segments shorter than 10 units (staircase noise). |
| `len`, `len max` | total and longest wire length. |
| `detours` | wires at least 2.5× their endpoints' Manhattan distance, and at least 200 units long. |
| `outer` | wires that leave the bounding box of the blocks and ports by more than 30 units, i.e. routed round the outside. |
| `white`, `gap` | fraction of 50×50 cells with no block, label or wire, and the side of the largest empty square. |
| `aspect` | width / height of everything drawn. |
| `pitch` | the closest two pins on different nets. Under about 10 units the pins are unreadable and the block is too small for its pin count. |
| `ink est` | `ink_estimated`: icons and glyphs whose drawn shapes could only be estimated (text, or art the tool cannot measure). Not a defect; the glyph checks on them are less certain. |
| `dl X`, `dl illegal`, `dl turns`, `dl spacing` | dyad-layout's own `score_existing_solution` on the drawn routes. `illegal` = overlapping runs + fallback routes. A `*` marks a partial score (see `dl unmatched`). |
| `dl unmatched` | problem connections no drawn wire was matched to. They are left out of the drawn-route score, never replaced by an invented route. |
| `reroute X`, `reroute illegal` | dyad-layout's `score_layout`: the same placements, routed by its own router. If this is far below `dl X`, the routes are the problem. If it is about the same, the placement is. |

`bad` (badness) is the ranking key. It is a plain weighted sum of the counts
(`WEIGHTS` in `layout_report.py`), weighted by how hard the defect is to read
past:

| weight | counts | why |
|---:|---|---|
| 20 | `ovl`, `T`, `thru`, `diag`, `blk ovl` | the drawing is wrong: wires that read as connected, a wire through a block, a slanted wire, blocks on blocks |
| 10 | `g ovl`, `g detach`, `thru glyph`, `jct/glyph` | a connector is misdrawn: on another glyph or icon, off its block, crossed by another net, a junction dot on it |
| 5 | `unrt`, `g hang`, `lbl/glyph` | a connect() with no route (Dyad invents one), a glyph past the end of its side, a label under a glyph |
| 3 | `X` | a crossing: readable, but each one costs the reader |
| 2 | `lbl/blk`, `lbl/lbl`, `outer`, `detours` | clutter |
| 1 | `near diag`, `g ovl unw`, `lbl/icon` | a hair off the axis, which shows only as a jag when zoomed in; unwired pins piled up, or a label under its own block's glyph, by the child's icon: visible, but only fixable in the child component |
| 0.5 | `lbl/wire`, `jogs` | |
| 0.25 | each bend | |

plus `100 × max(0, white − 0.6)` and 10 if `pitch` < 10. A near-diagonal
costs less than a crossing: it is a cosmetic rounding slip that a reader does
not notice at normal zoom, while every crossing makes a wire harder to
follow. Sort by any other column with `--sort`.

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
- **Labels are a fixed size.** Studio sets them in Inter at 16.035 units
  (em) on a 24.45-unit line, whatever the size of the box, centred on the
  label's anchor: (500, 1100) of a block's icon by default, mapped through the
  box and turned with it. They are drawn upright on a block turned 0 or 180
  degrees and on their side on a block turned a quarter turn. A boundary
  port's name is drawn at (500, 1100) of its box grown by 20 units on every
  side, i.e. 24 units lower than a block's. Widths are Inter's advance widths
  and pair kerning (`inter_metrics.json`, measured in Chrome by
  `inter_metrics.mjs` from the font Studio ships). They agree with Studio's
  DOM within 0.1 units for 1151 of the 1152 HL20Demo labels; the exception is
  `k=GRSAS * 0.01745`, drawn 2.2 units wider (1.1 at each edge), likely an
  Inter contextual alternate on the `*`.
- **The text is smaller than its label.** Studio's label element is a 2-unit
  top margin (`LABEL_MARGIN`, its `margin-block-start`) over a line box 1.4 em
  high, with the text's baseline in the middle of the line box: 19.06 units
  below the element's top. The letters reach only as far above and below the
  baseline as Inter's glyphs do (`ink` in `inter_metrics.json`): the name
  `cap` centred at y = 360 has its line box from 347.8 to 372.2 but its
  letters from 357.8 to 370.4. A label's *ink* is that box, from the first
  letter's ink to the last's, turned with the label (on a half turn the
  margin goes to the bottom and the text turns back upright). Coverage by
  glyphs, label and wire collisions use the ink; the full line boxes are only
  compared with Studio's DOM ([Calibration](#calibration)) and size the
  drawing (extents, whitespace).
- **Only quarter turns.** Dyad places blocks in the eight D4 states. A
  rotation by any other angle is rejected (`UnsupportedSVG`, "only quarter
  turns are modelled") instead of being fitted into the turned frame's
  bounding box.

An icon's outline is the convex hull of what it paints, measured through
nested `<g>` and `<svg>` elements and their transforms: `polygon`,
`polyline`, `rect`, `circle`, `ellipse`, `line`, `path` (every command; curves
and arcs are sampled), and the boxes of `image` and `foreignObject`. A shape
paints its fill (unless `fill` is `none`) and its stroke: half its
`stroke-width` to each side, miter tips within `stroke-miterlimit` (or round
joins), and square or round caps, styled by presentation attributes, the
icon's `<style>` rules (tag, class and id selectors) and `style` attributes,
inherited down the tree. A 20 × 20 square with a 20-unit stroke paints
(30, 30)-(70, 70). Each nested `<svg>` clips what it holds to its viewport
(unless `overflow` is `visible`), and the icon's viewBox clips the rest: a
20 × 20 rectangle in the middle of a 100 × 100 icon, or an oversized one in a
nested viewport there, is drawn, and measured, as 20 × 20. The calibration
compares the shapes' geometry instead (`parse_svg(..., strokes=False)`):
the DOM's client rectangles leave strokes out. Two things are only estimated, and each
estimate is listed in `report.md` (*Estimated icon ink*, `ink est`): text,
sized from an average character width, and art the tool cannot measure (a
`<use>`, a malformed shape), which is taken to fill its viewBox. Port names come from the component
definitions: the library's own `.dyad` files, then the newest version of each
package in the Julia depot. Unresolved ones are numbered (`b.#2`); only the
report text depends on the names.

## Glyph checks

All in diagram units. A glyph's size is the shorter side of its box. A wire
is wired to a glyph if it ends on the glyph's pin (within `PIN_TOL`, 0.5
units: `dyad render` ends wires exactly on the pin), and the glyph's nets are
the nets of those wires. Nothing else counts as wired: a wire that starts
elsewhere in a tall port's frame is not the port's.

Some of what a glyph does is the child component's icon design, the same at
any size: BlockComponents' pins stand just outside their block (`x1 = -100,
x2 = 0`), a bottom pin sits where Studio writes the block's name, an icon
drawn 5% in from its frame leaves its pins 5% off it. For a block's own glyphs
the checks marked *baseline* compare with the same block at Dyad's default
size, a 100 × 100 square (`STD_BLOCK`) about the same centre, and count only
what this diagram's placement adds.

| class | a finding is | tolerance |
|---|---|---|
| `glyph_overlap` | two glyphs whose outlines overlap or are closer than a tenth of the smaller one's size (touching triangles in a column); or a glyph reaching more than 1 unit into another block's icon. Two **unwired** glyphs of the same block are counted apart, in `glyph_overlap_unwired` (weight 1, `g ovl unw` in the table, dashed in the overlay): their placement is the child's icon design. | `GLYPH_GAP` 0.1, `BODY_DEPTH` 1 |
| `glyph_detached` | *baseline*: a block's glyph further from the icon Studio draws than a quarter of its size more than at the default size (gaps as fractions of the glyph's size, which scales with the block), and at least 2 units. | `DETACH_GAP` 0.25 |
| `glyph_overhang` | *baseline*: a block's glyph (that is not detached) with more than half its length past the end of its side of the icon beyond what it has at the default size (1% slack, so a glyph centred on the corner is not counted however its stroke is drawn); or with 75% more of its area outside the icon than at the default size, or most of it outside and sticking out 30 units further than at the default size (scaled). A standard pin on a big block is a big pin standing as far off a big icon, which is no layout defect. | `OVERHANG` 0.5, `OVERHANG_OUT` (0.75, 30) |
| `label_covered` | a label (block, boundary port, or free text) with more than 25 square units of its text's ink (a quarter of a character's) under a glyph's outline, a block's own glyphs over its own labels included. A connector centred on a short name covers 45 square units of its text at 100 × 100; on a 200 × 200 block it is twice the size and covers 159, which counts. A plain bottom pin reaches only the padding over the text (20 to 22 square units of ink, at either size). | `LABEL_COVER` 25 |
| `label_covered_by_icon` | *baseline*: a label over 25 square units of ink under its own block's glyph, when the block at the default size covers it within 25 square units as much (the label keeps its size, its anchor scales with the block). The child's icon puts its glyph where Studio writes the name, so it is reported apart, at weight 1, as the child component's finding; a placement that makes it more than 25 square units worse counts in `label_covered`. | `LABEL_COVER` 25, `STD_BLOCK` 100 |
| `wire_thru_glyph` | a wire of a net not wired to the glyph, along its route as drawn, with one continuous passage through the painted outline that gets further from its edge than `min(THRU_DEPTH` × the depth of the outline's centre, `GRAZE)`, or that runs at least `RUN_FRAC` of the glyph's size and `RUN_MIN` units at least `RUN_DEPTH` inside. Every glyph is tested, whatever its size, and a zigzag through a glyph is one passage however short its legs. Wires of the glyph's own nets may run over it: the wire to a 10-unit pin crosses it from whichever side it comes, and the spur `dyad render` leaves past a pin, to the block's edge and back, is on the pin's net. Shallower and shorter, a wire runs along the glyph's edge (the backs of a column of input pins, at most 1.4 units in and 9.2 units long in the clean HL20Demo diagrams). | `THRU_DEPTH` 0.6, `GRAZE` 2, `RUN_FRAC` 0.5, `RUN_MIN` 20, `RUN_DEPTH` 1 |
| `junction_on_glyph` | a junction dot (radius 2.5) touching a glyph's outline, unless it is on one of the glyph's nets and either on its pin or no deeper than the same depth limit (at the rim, where the wire leaves the glyph). | `JUNCTION_R` 2.5 |
| `near_diagonal` | a segment off the horizontal or vertical by more than 0.001 and at most 0.5 units. | `NEAR_DIAG` (0.001, 0.5) |

At 99ffbc0 (draft PR #51), the checks flag every glyph defect listed for the
HL20Demo diagrams in Studio screenshots, and nothing in the diagrams that look
clean there. On the relaid demos of PR #49 (f47214b) they flag only
FrictionBrakeDemo.BrakeThermalTest_Step (Studio draws its two step sources'
outputs and its heat inputs' ports away from their icons, so the findings are
real) and, in `glyph_overlap_unwired`, MakieWebinar's grid tests, whose
resistor icons pile their two unwired pins up. No label there is covered: on
the 100 × 100 thermal blocks (heat capacitors, sources, `brake_thermal`), the
block's own bottom heat port covers 72 square units of its name's line box but
at most 4.5 of its letters (the top of the `k` of `disk_mass`). In HL20Demo
the glyphs over labels cover 42 square units of text or more and the others
reach no letter: `LABEL_COVER` sits in that gap.

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

It lists every icon and glyph that is more than `--tol` (1) unit off, and
every label whose box is more than `--label-tol` (`LABEL_TOL`, 1.25) off at
any edge: the full box, not just its centre. Icons and glyphs are compared
by their shapes' geometry, as the DOM measures them (without strokes). All 43 HL20Demo diagrams at
99ffbc0 match within these tolerances (every label but `k=GRSAS * 0.01745`
within 0.1 units); so do DynamicSteadyState.ZoneRoom and
FrictionBrakeDemo.BrakeThermalTest_Step from PR #49, whose path-drawn icons
are measured as drawn. `--fixture` writes the compact geometry the unit
tests compare with.

`inter_metrics.json` comes from Studio's own font:

```sh
node tools/layout-report/inter_metrics.mjs CHROME inter-latin-wght-normal.woff2 > tools/layout-report/inter_metrics.json
```

where `CHROME` is a Chrome or chrome-headless-shell binary (dyad-ui-shot
downloads one) and the font is in Studio's VSIX under
`extension/out/fonts/`. It needs `puppeteer-core`.

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
`<image>` at diagram level, `skewX`/`skewY` or malformed transforms, an icon
turned by other than a quarter turn, a nested `<svg>` viewBox whose size
cannot be known, other `preserveAspectRatio` values) are rejected with an
error instead of being measured wrongly. Instance placements are read from
the source inline or through a `{^link}` into the metadata's `_links`, after
the constructor's closing parenthesis however many lines its arguments take.

## Limitations

- A label's ink is the box round its letters, not their shapes: a glyph or
  wire in the gap above a run of short letters (the `a` after the `C` of
  `Cap`) is counted as on the text.
- Label widths are Inter's canvas metrics; a contextual alternate (as on the
  `*` of `k=GRSAS * 0.01745`) can make Studio's text up to about a unit wider
  at each edge.
- Icon text is sized from an average character width, and art the tool cannot
  measure fills its viewBox; both are listed under *Estimated icon ink*.
- The default size the *baseline* checks compare with is a 100 × 100 square;
  a child component meant to be placed at another size is judged against it
  all the same.
- Diagrams whose connections only exist inside `for` loops draw no wires.
  Their metrics are empty apart from `loop_connects`.
- A component whose render fails (for example, a `connect` to a nested
  connector) is listed under *Failed* with the compiler's error, and the run
  exits 1 unless `--allow-failures` is given.
