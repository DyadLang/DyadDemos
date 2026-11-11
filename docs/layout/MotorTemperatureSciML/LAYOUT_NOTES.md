# MotorTemperatureSciML diagram re-layout

Toolchain: Dyad CLI 3.5.0 (`dyad-linux-x64`, release v3.5.0, SHA256 checked),
`JULIA_EXECUTABLE="julia +dyad-3.5.0"`, and the scout's `layout-tools`
(`relayout.sh`, `edit_problem.py`, `fix_junction_order.py`, `verify_edges.py`,
`svg2png.sh`). `relayout.sh` is run from the demo root. `PIN(id,x,y)` below is shorthand for

    add:{"id":"pin:ID","kind":{"kind":"pin","componentId":"ID","at":{"x":X,"y":Y}},"strength":{"tier":"required","weight":1}}

Solver coordinates are in half-squares (1 = 50 diagram units).

`before.png` is `main` at f8723d5 and `after.png` is this branch. Both are rendered with
`dyad render` and then `svg2png.sh` at 1000 px.

## Child icon fixes (done first, bottom-up)

The tall routing icons `FeatureMux.svg`, `NormalizerTall.svg`,
`BoundaryTemperatures.svg`, `OperatingConditionsDemux.svg` and
`TemperatureDemux.svg` have non-square viewBoxes (e.g. `0 0 400 1000`). The
renderer letterboxes them inside the stretched 1000×1000 icon frame. Their
connectors sit on the frame edge, so every wire stopped 40–60 units short of the
visible bar. Adding `preserveAspectRatio="none"` to the root `<svg>` makes each icon
fill its instance box. Each instance box already has the SVG's aspect ratio, so
nothing gets visibly distorted.

## Per-diagram notes

| Diagram | Before | Method | Result |
|---|---|---|---|
| `Networks.ConductanceNet` | B-: x/T wires stop short of the mux bar; labels misplaced | solver | A: 0 crossings, 0 turns |
| `Networks.PowerLossNet` | B-: same as ConductanceNet | solver | A |
| `Models.TNNModel` (and `Story.HighTempTNNModel`, which `extends` it) | A- hand layout: features caption under the normalizer name; `boundaries` block 50×100 and unreadable; wire gaps at the normalizer | hand fixes, solver rejected | A- |
| `Networks.Tests.TestConductanceNet` | C: 14 wires drawn as two diagonals | hand | A |
| `Networks.Tests.TestPowerLossNet` | C: same | hand | A |
| `Models.Tests.TestTNNModel` | C: 10 diagonal wires fanning into the model | hand (solver rejected) | A: 0 crossings |
| `Models.Tests.TestTNNProfile` (and `Story.TestTNNProfile60/62/74`, which `extend` it) | B: model ports 40 apart; wire labels sit between wires; caption collisions | hand grid alignment | A- |

### ConductanceNet / PowerLossNet

    relayout.sh Networks.ConductanceNet OUT lock-orientation unpin-ports port-edges PIN(x,0,4) PIN(T,0,8)
    relayout.sh Networks.PowerLossNet   OUT lock-orientation unpin-ports port-edges PIN(x,0,4) PIN(T,0,8)

`order` constraints have no effect on canvas connectors ("no such component"),
so the two input ports are pinned level with the mux inputs (mux centre y=6,
ports at 4 and 8). Diagram-layer labels were then moved by hand:
`Operating conditions · x[10]` → (115,170), `Estimated temperatures · T[4]` →
(115,370), `[x; T] · 14` → (478,270).

### TNNModel

I tried the solver and rejected it:

- `lock-orientation unpin-ports port-edges opt:routingRefinement=2` left 3 illegal routes.
- `lock-orientation opt:routingRefinement=2` gave 26 crossings, with wires looping around the blocks.

So the hand layout stays, with targeted edits:

- `boundaries` box 50×100 → 70×140 (`x1 715, y1 -25, x2 785, y2 115`). Edge
  waypoints were moved to the new port heights: `features` arm to `boundaries.u`
  at y=45, `coolant` at y=10, `ambient` at y=80.
- Title `THERMAL NEURAL NETWORK` y −65 → −115, to clear the bigger block's name.
- `Normalized features · x[10]` y 805 → 880, moving it off the `normalizer` instance name.

The vertical coolant/ambient wires still pass through the `thermal` instance
name. They enter `thermal`'s top ports, and the name is part of the icon layer,
so that can't be fixed per instance.

### TestConductanceNet / TestPowerLossNet

With only two blocks, the solver's centring always added a jog. Hand layout:
`net` box 400..900 × 250..750 (500×500, which puts both ports on the grid). `sources`
box 100..200 × 400..500 sits level with `net.x`. The 10 `x[i]` edges are straight
(`M: []`). The 4 `T[i]` edges run `M: [(300,450),(300,850),(650,850)]` under the
block into the bottom port.

### TestTNNModel

The model box grew from 300 to 500 so its 10 input ports are 50 apart (they were 30).
Solver attempts, all rejected:

- `lock-orientation unpin-ports port-edges` left 6 illegal routes.
- Adding `opt:routingRefinement=2`, an order chain `above` over the ten sources,
  and `bump` of the model by 1 or 2 still left 11 crossings, with wires looping
  behind the source column.
- `opt:collapsePendants=true` left 8 illegal routes.

Hand layout: sources are 100×100 in one column, centres at y=100+150k, x 50..150.
The model is at 500..1000 × 525..1025, so port k is at y=550+50k. Each edge is a
nested staircase `M: [(x_k, s_k), (x_k, p_k)]`, with x_k = 200+50·(4−k) for k≤4 and
200+50·(k−5) for k≥5. That gives 0 crossings.

### TestTNNProfile

Hand grid alignment:

- `inputs` demux at 400..500 × 100..600, `model` at 650..1150 × 100..600. Both are 500
  tall, so the 10 wires are straight and 50 apart.
- `interp_inputs` at 100..300 × 250..450.
- `interp_meas` at 100..300 × 900..1100, `measurements` at 400..500 × 800..1200.

Labels:

- Wire labels sit at x=575, y=113+50k.
- `pm`/`stator yoke`/`stator tooth`/`stator winding` at (590, 850+100k).
- `Operating conditions · 10 channels` (200,190), `TNN temperature estimator` (900,40),
  `Measured temperatures · 4 channels` (200,840), `Targets for calibration / validation` (665,790).

## Known renderer limitations (not fixable in layout)

- Instance names are drawn in the icon layer and scale with the box, unevenly when
  the box isn't square. Tall boxes therefore get squeezed names (`mux`, `inputs`,
  `measurements`, `boundaries`), and large boxes get very large names (`normalizer`, `model`).
