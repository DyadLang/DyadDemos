# TurkeyDemo diagram layout notes

| Diagram | Before | What was done | After |
|---|---|---|---|
| TurkeySphereTest | good hand layout, except `convection` was placed with `x1 > x2` (a horizontal mirror), so its label and icon rendered back to front | `convection` turned 180 degrees instead (`rot: 180`). The solid and fluid ports stay on the same sides, and the renderer keeps the label upright. Its Gc input is now on the bottom, so convection goes in the lower branch with `Gc_signal` under it. Re-laid out by pinning through the solver | oven -> (radiation over convection) -> turkey, 0 crossings, no mirrored text |
| TurkeyDiscretizedSphere | no subcomponents (equations only) | nothing to lay out | - |

The order of the turkey and oven can't be swapped to avoid the turn.
`turkey.surface` is on the turkey icon's left edge and `oven.port` on the
oven's right edge, so the oven has to be on the left. The convection block's
`fluid` (oven side) must then face left, which needs either a mirror or a
180-degree turn. Of the two, only the turn keeps the text readable.

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
cd TurkeyDemo
OR180='add:{"id":"orientation:convection","kind":{"kind":"orientation","componentId":"convection","d4":"r180"},"strength":{"tier":"required","weight":1}}'
relayout.sh TurkeySphereTest OUT grid:9x8 lock-orientation "$OR180" unpin-ports port-edges \
  "$(PIN oven 3 7)" "$(PIN radiation 9 4)" "$(PIN convection 9 10)" \
  "$(PIN Gc_signal 5 14)" "$(PIN turkey 15 7)"
```

(The unpinned solve with `ALN vertical radiation convection` +
`ORD radiation convection above` put the oven on the right and gave 2
crossings.)

Verification: `dyad compile .` leaves `generated/` byte-identical, and
`Pkg.test()` passes (6/6).
