# FrictionBrakeDemo diagram re-layout (Dyad 3.5 autolayout)

Toolchain: Dyad CLI 3.5.0 (`483d92b`), `JULIA_EXECUTABLE="julia +dyad-3.5.0"`, and
the layout scripts `relayout.sh`, `edit_problem.py`, `fix_junction_order.py`,
`verify_edges.py` and `svg2png.sh` (headless Chrome). Every diagram was rendered
before and after with `dyad render FrictionBrakeDemo.<Comp> --dir .`, and the PNGs
were checked by eye.

`dyad layout apply` re-prints the whole file. Only the blocks of the components that
changed were spliced back into the original files, so the diffs cover just those
components. The other diagrams keep their original text and render byte-identical.

## Summary

| Diagram | Before | What was done | After |
|---|---|---|---|
| SimpleVehicle | F: no placements, 7 blocks stacked on one spot, labels on top of each other | solver + 2 hints, then hand-tuned pendants and output ports | left→right chain, grounds hang under their flanges, 0 crossings |
| Driver | C: input ports overlap, wires end away from ports, a diagonal wire to `u_ff` | solver with pinned boundary ports | inputs left, outputs right, 0 crossings, no diagonals |
| TestDriver_Constant | B: needless jog in the only wire | hand: moved `speed_ref_source` up 15 units and 90 units right | straight wire |
| BrakeThermal | D: 17 blocks cramped, diagonal wires, heat ports stranded at the bottom, several crossings | solver for the signal chains, then a hand-designed thermal section | two stacked strips, 1 crossing (see below), no diagonals, no rotated text |
| SimpleVehicleTest_Constant | A | solver tried, looser; kept original | unchanged |
| SimpleVehicleTest_CoastDown | A | solver tried, looser; kept original | unchanged |
| TestPowertrain | A | solver tried, ground wire loops over the top; kept original | unchanged |
| FrictionBrakeTest | A- | solver tried, boundary wires loop around; kept original | unchanged |
| TestDriverWithBraking | A | solver tried, much more spread out; kept original | unchanged |
| BrakeThermalTest_Constant | B+ | solver tried, heat wires loop under everything; kept original | unchanged |
| BrakeThermalTest_Step | B+ | solver tried, 2 long detours; kept original | unchanged |
| VehicleCycleTest | B+ | solver tried, 4–5 crossings with or without order hints; kept original | unchanged |

`*.before.png` / `*.after.png` show the changed diagrams. `*.unchanged.png` shows the diagrams that were kept.

## Recipes (run from `FrictionBrakeDemo/`)

Coordinates in the hand specs are in half-squares: a block `[cx, cy]` is the
100×100 box `x1 = 50·cx − 50 … x2 = 50·cx + 50` (same for y). A third value is
`"rot"`. A route `[[x, y], …]` is the connect's interior waypoints `M`, times 50.

### SimpleVehicle

```sh
relayout.sh SimpleVehicle OUT lock-orientation unpin-ports port-edges edge:shaft=left \
  opt:collapsePendants=true \
  'add:{"id":"pin:housing","kind":{"kind":"pin","componentId":"housing","at":{"x":10,"y":8}},"strength":{"tier":"required","weight":1}}' \
  'add:{"id":"pin:ground","kind":{"kind":"pin","componentId":"ground","at":{"x":14,"y":8}},"strength":{"tier":"required","weight":1}}'
```

`collapsePendants` puts `load_anchor` under the damper. Without it, the anchor sits to
the right and its wire loops over the top. The pins split `housing` (rotational
support, left wheel port) and `ground` (translational support, right wheel port) into
two columns. Without the pins they stack in one column and the housing wire wraps
around the ground. Hand edits after apply (diagram units):

- `housing` 450–550 × 300–400, `ground` 650–750 × 300–400, `load_anchor` 1050–1150 × 300–400
  (the pinned rows came out 175 units lower than the main row).
- Routes: `wheel.support_r → housing` M `(565,250),(500,250)`; `wheel.support_t → ground`
  M `(635,250),(700,250)`; `load_damper.flange_b → load_anchor` M `(1200,150),(1200,250),(1100,250)`.
- Output ports `vehicle_speed` 1300–1400 × 100–200 and `wheel_speed` 1300–1400 × 300–400.
  They are driven by equations, not connects, so the solver dropped them at
  overlapping spots. They now follow the icon order: vehicle_speed upper, wheel_speed lower.

### Driver

```sh
relayout.sh Driver OUT lock-orientation unpin-ports port-edges \
  'add:{"id":"pin:speed_ref","kind":{"kind":"pin","componentId":"speed_ref","at":{"x":0,"y":7}},"strength":{"tier":"required","weight":1}}' \
  'add:{"id":"pin:speed_act","kind":{"kind":"pin","componentId":"speed_act","at":{"x":0,"y":11}},"strength":{"tier":"required","weight":1}}' \
  'add:{"id":"pin:brake","kind":{"kind":"pin","componentId":"brake","at":{"x":20,"y":7}},"strength":{"tier":"required","weight":1}}' \
  'add:{"id":"pin:throttle","kind":{"kind":"pin","componentId":"throttle","at":{"x":20,"y":11}},"strength":{"tier":"required","weight":1}}'
```

The solver treats boundary ports as points and put `speed_act` one half-square above
`speed_ref`. The boxes overlapped and the `speed_act` wire looped around the PID.
Pinning the ports in icon order (`speed_ref`/`brake` upper, `speed_act`/`throttle`
lower) fixes both. Route coordinates `426.99999999999994`/`473.00000000000006` were rounded to `427`/`473`.

### TestDriver_Constant (hand)

`speed_ref_source` moved to 400–500 × 435–535, which lines its output up with
`driver.speed_ref` (y = 485). The route is now `M: []`.

### BrakeThermal

1. `relayout.sh BrakeThermal OUT lock-orientation unpin-ports port-edges`. The signal
   chains came out clean. The thermal half had 5 crossings and loops: the masses sat
   right of the convections and the ambient port faced away. Hints did not fix it:
   order constraints for mass/convection/radiation/ambient, `routingRefinement=2`,
   `blockAlignment`, `collapsePendants`, and an r180 orientation for ambient/masses all
   stayed at 4–6 crossings.
2. Every placement and route was then set by hand to the spec below. Layout: disk
   strip on top, pad strip below. Each strip runs inputs → gain/constant → `*_h_calc`
   → `*_conductance` → the convection's top `Gc` port. Each mass's bottom port is a
   small bus that joins its heat input, its convection's `solid` port and the
   radiation links. A vertical ambient bus on the right collects both `fluid` ports and
   `disk_radiation.port_b`.
   - `ambient` and `pad_disk_radiation` use `"rot": 180`. With r180 the instance label
     stays upright; ambient's port now faces the bus, and the radiation's disk-side
     port faces the disk bus. `"rot": 90/270` was rejected because it rotates the label
     text, and flips (x1 > x2) were rejected because they mirror it.
   - One crossing remains (`pad_mass.port → pad_disk_radiation.port_a` crosses
     `pad_convection.fluid → ambient`). Some crossing is forced here: disk node →
     disk convection → ambient → pad convection → pad node → pad-disk radiation → disk
     node is a cycle, and the pad signal chain has to reach `pad_convection.Gc` across it.
   - The mass labels sit on their port wire. That comes from the HeatCapacitor icon,
     which has its port and its label both at the bottom.

```json
{"place": {"wheel_speed": [0, 6], "heat_disk": [0, 11], "vehicle_speed": [0, 18], "heat_pad": [0, 23],
  "disk_h_base_const": [5, 2], "wheel_speed_gain": [5, 6], "disk_h_calc": [10, 4], "disk_area_const": [10, 8],
  "disk_conductance": [15, 6], "disk_mass": [18, 9], "disk_convection": [21, 11], "disk_radiation": [25, 13],
  "pad_h_base_const": [5, 14], "vehicle_speed_gain": [5, 18], "pad_h_calc": [10, 16], "pad_area_const": [10, 20],
  "pad_conductance": [15, 18], "pad_mass": [18, 21], "pad_convection": [21, 23],
  "pad_disk_radiation": [24, 19, 180], "ambient": [29, 16, 180]},
 "route": {
  "heat_disk, disk_mass.port": [[18, 11]],
  "heat_pad, pad_mass.port": [[18, 23]],
  "wheel_speed, wheel_speed_gain.u": [],
  "vehicle_speed, vehicle_speed_gain.u": [],
  "disk_h_base_const.y, disk_h_calc.u1": [[8, 2], [8, 3.4]],
  "wheel_speed_gain.y, disk_h_calc.u2": [[8, 6], [8, 4.6]],
  "pad_h_base_const.y, pad_h_calc.u1": [[8, 14], [8, 15.4]],
  "vehicle_speed_gain.y, pad_h_calc.u2": [[8, 18], [8, 16.6]],
  "disk_h_calc.y, disk_conductance.u1": [[13, 4], [13, 5.4]],
  "disk_area_const.y, disk_conductance.u2": [[13, 8], [13, 6.6]],
  "pad_h_calc.y, pad_conductance.u1": [[13, 16], [13, 17.4]],
  "pad_area_const.y, pad_conductance.u2": [[13, 20], [13, 18.6]],
  "disk_conductance.y, disk_convection.Gc": [[21, 6]],
  "pad_conductance.y, pad_convection.Gc": [[21, 18]],
  "disk_mass.port, disk_convection.solid": [[18, 11]],
  "pad_mass.port, pad_convection.solid": [[18, 23]],
  "disk_mass.port, disk_radiation.port_a": [[18, 13]],
  "disk_mass.port, pad_disk_radiation.port_b": [[18, 13], [22, 13], [22, 19]],
  "pad_mass.port, pad_disk_radiation.port_a": [[18, 25], [26, 25], [26, 19]],
  "disk_convection.fluid, ambient.port": [[27, 11], [27, 16]],
  "pad_convection.fluid, ambient.port": [[27, 23], [27, 16]],
  "disk_radiation.port_b, ambient.port": [[27, 13], [27, 16]]}}
```

### Kept diagrams

Each one was run through `relayout.sh <Comp> OUT lock-orientation unpin-ports port-edges`,
compared, and then reverted:

- **SimpleVehicleTest_Constant / _CoastDown:** same topology as before, but spread
  over about twice the area.
- **TestPowertrain:** `fixed` moved right of the damper, and its wire loops up and over.
- **FrictionBrakeTest:** the boundaries moved right, and the heat wires loop over the brake.
- **TestDriverWithBraking:** `step2` was pushed far below; the original is compact.
- **BrakeThermalTest_Constant / _Step:** the heat-flow wires run under the whole diagram,
  and the Step harness gained two long detours.
- **VehicleCycleTest:** the default ops gave 4 crossings. Order hints (`ref < driver <
  brake/powertrain < vehicle`, `brake_thermal` above `brake`) with
  `routingRefinement=2` gave 5, and one hint was dropped. The original has a single
  crossing, and that crossing is forced: `vehicle.vehicle_speed` and
  `vehicle.wheel_speed` feed back to `brake_thermal`, whose ports are in the opposite
  vertical order once the wires wrap over the top. No "wire over a block" defect is
  visible in the current render. Known cosmetic issue: the heat wires pass through the
  `brake_thermal` label, because that icon puts its ports and its label both at the bottom.

## Renderer note

Boundary `RealInput`/`RealOutput` triangles render about 50 units up and to the left of
where their wires start. This shows in every diagram, before and after. The cause is the
connector icon, a nested `<svg width="210" height="210">` scaled by 0.1, not the layout.
Port placements and wire endpoints agree in the model.
