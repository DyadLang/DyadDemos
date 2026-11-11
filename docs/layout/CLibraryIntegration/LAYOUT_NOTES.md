# CLibraryIntegration diagram layout notes

| Diagram | Before | What was done | After |
|---|---|---|---|
| SampledSlidingAxle | 3 blocks stacked on the default position | fixed the child icon first (below), then one row: sampler -> tire -> hold | 0 crossings, straight wires |
| SlidingAxle | 1 subcomponent | nothing to lay out | - |

**Child icon fix (`dyad/tires.dyad`, RelaxationTire).** The `_links` placements
for RelaxationTire's clocked connectors `alpha = RealInput@[clk]()` /
`Fy = RealOutput@[clk]()` were not picked up. The compiler warned
`connector-placement: Connector alpha in RelaxationTire doesn't include placement
metadata`, and both ports were drawn at the icon centre, as were the wires into
the tire. The connectors now carry inline icon placements on 50-unit multiples
(alpha `x -50..50, y 450..550`, Fy `x 950..1050, y 450..550`), and the dead
`_links` entries are removed. `MagicFormulaTire` (unclocked) was not affected
and is unchanged.

**Environment.** `DiscreteComponents = "0.6.0"` does not resolve against the
registries available here (0.5.1 is the newest). Rendering and layout were done in
an untracked scratch copy of the demo with the compat relaxed to `0.5`. That
copy is enough for `dyad render`/`dyad layout`/`dyad compile`, but its
package does not load: DiscreteComponents 0.5 was generated with an older Dyad
constructor API. The compat change was **not** committed. The committed
`.dyad` files are byte-identical to the scratch copy's, and `dyad compile`
there leaves `generated/` byte-identical to the committed one. Tests could not
be run (they could not run before this change either, for the same reason).

## Tooling

Dyad CLI 3.5.0 (`dyad layout`), `JULIA_EXECUTABLE="julia +dyad-3.5.0"`, and the
layout scripts (`relayout.sh`, `edit_problem.py`, `fix_junction_order.py`,
`verify_edges.py`, `svg2png.sh`). Every diagram below was produced with

    relayout.sh COMPONENT OUTDIR OPS...

run from the demo root. The constraint ops are built with these shell helpers
(they expand to `edit_problem.py` `add:` ops):

```sh
PE()   { echo "add:{\"id\":\"portEdge:$1\",\"kind\":{\"kind\":\"portEdge\",\"connectorId\":\"$1\",\"edge\":\"$2\"}}"; }
ORD()  { echo "add:{\"id\":\"order:$1:$2\",\"kind\":{\"kind\":\"order\",\"a\":\"$1\",\"b\":\"$2\",\"dir\":\"$3\"}}"; }
ALN()  { local ax=$1; shift; local ids=$(printf '"%s",' "$@"); echo "add:{\"id\":\"align:${ax}:$1\",\"kind\":{\"kind\":\"align\",\"componentIds\":[${ids%,}],\"axis\":\"$ax\"}}"; }
PIN()  { echo "add:{\"id\":\"pin:$1\",\"kind\":{\"kind\":\"pin\",\"componentId\":\"$1\",\"at\":{\"x\":$2,\"y\":$3}},\"strength\":{\"tier\":\"required\",\"weight\":1}}"; }
```

Notes on what the solver actually does (3.5.0):

- `PIN` coordinates are in half-squares (one half-square = 50 diagram units, a
  block is 2x2). Pins are honoured *relative to each other*; the solver then
  translates the whole layout to add its margin. Canvas-connector pins must sit
  on the canvas edge (bottom edge = `2 * gridRows`).
- `extract` seeds `gridColumns/gridRows` from the current layout, so repeated
  runs grow the canvas (and push edge ports outwards). Pass `grid:CxR`
  explicitly to keep it stable.
- `ORD a b left` = `a` is left of `b`. `above/below` is ignored unless the two
  blocks are in the same layer (force that with `ALN vertical`).

## Exact command

```sh
cd CLibraryIntegration   # (scratch copy with DiscreteComponents compat "0.5")
relayout.sh SampledSlidingAxle OUT grid:7x3 lock-orientation unpin-ports port-edges \
  "$(ALN horizontal sampler tire hold)" "$(ORD sampler tire left)" "$(ORD tire hold left)"
```
