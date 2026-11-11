# CoffeeMugDemo diagram layout notes

All six diagrams live in `CoffeeMugDemo/dyad/CoffeeMugSubsystems.dyad`.
Children were laid out before parents (bottom-up); no icon-port placements
changed, so the parent diagrams did not need to move.

| Diagram | Before | What was done | After |
|---|---|---|---|
| HandSubsystem | no placements: both blocks stacked on the icon | solver + order hint; cupContact on the right edge | `HandSubsystem.after.png`: handMass -> handContact -> cupContact, 0 crossings |
| SteamSubsystem | no placements | pinned layout through the solver; liquidInterface left, ambient right | convection (with its Gc source above) and radiation as two parallel branches, 0 crossings |
| SpoonSubsystem | no placements | pinned layout, `routingRefinement=1` | liquidContact on the main row, spoonMass and radiation above, convection on the main row, 0 crossings |
| CoffeeMugSubsystem | 12 blocks with no placements, stacked | pinned layout, `routingRefinement=1`, edge choice for the heat ports (below) | sensor chain on top row, heat path left -> right below it, 0 crossings |
| EspressoCupSystemModular | hand layout, no rotated blocks | kept (file re-printed by `layout apply`, render byte-identical) | `EspressoCupSystemModular.unchanged.png` |
| EspressoCupSystemWithSpoon | hand layout, no rotated blocks | kept (as above) | `EspressoCupSystemWithSpoon.unchanged.png` |

Heat-port edge choices (acausal, so `port-edges` does not place them):

- CoffeeMugSubsystem: `topSurface` **top** (it is the liquid surface, and the
  icon has it on top), `ambient` **right** (end of the heat path),
  `outerSurface` **bottom** (it is a mid-chain node: condCup -> outer surface
  -> convection/radiation), `espressoTemp_degC` right (output).
- Steam/Spoon: `liquidInterface` left, `ambient` right (heat flows liquid -> air).
- Hand: `cupContact` right (heat flows hand -> cup).

The HeatCapacitor icon has its port at the bottom centre, directly over its
label, so the wire out of hotEspresso/cupMass/spoonMass/handMass always runs
through the label. That is the library icon, not the layout.

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

## Exact commands

```sh
cd CoffeeMugDemo

relayout.sh HandSubsystem OUT lock-orientation unpin-ports port-edges \
  "$(PE cupContact right)" "$(ORD handMass handContact left)"

relayout.sh SteamSubsystem OUT lock-orientation unpin-ports port-edges \
  "$(PE liquidInterface left)" "$(PE ambient right)" \
  "$(PIN gcTop 9 3)" "$(PIN convTop 13 7)" "$(PIN radTop 13 11)"

relayout.sh SpoonSubsystem OUT grid:12x8 lock-orientation unpin-ports port-edges opt:routingRefinement=1 \
  "$(PE liquidInterface left)" "$(PE ambient right)" \
  "$(PIN liquidContact 5 12)" "$(PIN spoonMass 9 2)" "$(PIN gcExposed 13 8)" \
  "$(PIN convExposed 17 12)" "$(PIN radExposed 17 6)"

relayout.sh CoffeeMugSubsystem OUT grid:15x11 lock-orientation unpin-ports port-edges opt:routingRefinement=1 \
  "$(PE topSurface top)" "$(PE outerSurface bottom)" "$(PE ambient right)" \
  "$(PIN tempSensor 6 3)" "$(PIN to_degC 10 3)" "$(PIN add_offset 14 3)" "$(PIN offset_degC 10 7)" \
  "$(PIN hotEspresso 4 10)" "$(PIN gcEsp2Cup 8 10)" "$(PIN convEspresso2Cup 12 14)" \
  "$(PIN cupMass 16 10)" "$(PIN condCup 19 14)" "$(PIN gcCup2Env 22 10)" \
  "$(PIN convCup2Env 26 14)" "$(PIN radCup2Env 26 18)" \
  "$(PIN outerSurface 22 22)" "$(PIN topSurface 2.5 0)"
```

Hints that did not work, for the record: the unhinted solve of
CoffeeMugSubsystem gave 4 crossings and 43 turns; for SteamSubsystem
`ORD convTop radTop above` alone was ignored (different layers) and put
radiation in series. Adding `ALN vertical` fixed that, but the Gc source still
crossed the heat wire until it was pinned.

Verification: `dyad compile .` leaves `generated/` byte-identical, and
`Pkg.test()` passes (10/10).
