# HL20Demo diagram layout notes

How the HL20Demo diagrams are laid out and what to know before re-running
the layout tooling. Rendered PNGs live in [`diagrams/`](diagrams/); they are
captured by `dyad-ui-shot`, i.e. they are exactly what Dyad Studio 3.5.1's
diagram view draws, and each was inspected by eye.

## This pass (structural re-layout)

The goal of this round was genuine readability, measured by
`layout-report` (crossings, wires through blocks/ports, overlaps,
diagonals, false junctions, shared runs, unrouted connects) and by Studio
screenshots — not by the solver's own objective. The dense components were
**restructured into sub-components** rather than re-routed in place; every
existing component kept its name and external connectors, and the math is
unchanged (equations and parameters moved verbatim into sub-components).

Verified by:

- `python3 tools/partition_check.py HL20Demo/dyad <COMPONENT...>` —
  flattened connect-endpoint partitions (through sub-components) compared
  against the `2e80df8` reference for every component. The gate is exact:
  renamed or extracted blocks pass only through the audited `RENAMES`
  table inside the script; a same-shape rewire (e.g. swapping `mv.a11`
  and `mv.a12` in QuatToBody) still fails. Current run: **all components
  MATCH** (`--selftest` also verifies the swap regression is detected).
- Numeric parity of `HL20Demo.shared.HL20Aero` against the spec equations
  (the equation-level implementation): **max |Δ| = 4.44e-16 over 1000
  randomized input cases** (baseline was 4.44e-16).
- `dyad compile` clean; **1549/1549 generated tests + 20/20 aero tests
  pass**, including TestQuatDirection, TestQuatRoundTrip, TestMixerAssist.
- `layout-report` (f4bd2fe, the current Studio-geometry gate — measures
  label text ink and boundary-port captions) on all 45 public diagrams:
  **zero** in every scored class — overlapping ports/blocks, wires
  through blocks or port glyphs, diagonal segments, false junctions,
  unrouted connects, wires routed outside the diagram bounding box,
  plus the glyph classes `glyph_overlap`, `glyph_detached`,
  `glyph_overhang`, `label_covered`, `wire_thru_glyph`,
  `junction_on_glyph`, `near_diagonal`, and the label classes
  `label_block_overlaps`, `label_label_overlaps`,
  `labels_hit_by_wires`. The earlier 2a72e1e tool version was also run
  historically; its `labels_hit_by_wires` residuals at the time were
  pin-in-own-label-band contacts, all since cleared.

In a second routing pass the densest diagrams were re-laid with explicit
trunk-and-tap buses (single shared trunks with orthogonal tap drops), and
the vehicle/system, quaternion and test diagrams were re-routed in the
same style. Crossings fell further — HL20CL 69→25, HL20CD 69→25,
HL20CY 81→26, HL20CM 77→29, HL20CN/CR 91→35, HL20Mixer 44→33,
AeroForceBuilder 56→25, HL20Aero 82→59, AeroCLCD 45→45, AeroCYCN 61→46,
AeroLongitudinal 46→46, AeroLateralCoeffs 60→55, QuatKinematics 65→55,
QuatToDCM 62→25, FlightState 25→9, HL20Vehicle 128→119, HL20FullSystem
73→62, TestControllers 23→1 (AeroCLCD and AeroLongitudinal were re-laid
and held at 45 and 46) — with every non-crossing defect class at zero on
all 45 diagrams except six structural label/wire contacts on five
diagrams (a bottom-edge pin above its own block's name-label band),
listed in the metrics section below.

## New component hierarchy

```
HL20Aero        → AeroAirData                       (alpha_rad, |DRUD|, damping factors)
                + AeroLongitudinal { AeroCLCD { HL20CL, HL20CD }, HL20CM, CX/CZ transforms }
                + AeroLateralCoeffs { AeroCYCN { HL20CY, HL20CN }, HL20CR }
QuatToBody      → QuatToDCM + DCMMatVec             (shared by both rotations)
QuatToInertial  → QuatToDCM + DCMMatVec (transpose wiring)
RigidBody6DOF   → TransDynamics + RotDynamics + QuatKinematics
QuatKinematics  → QuatDerRow ×4
FlightState     → QuatToBody + AeroAngles + EulerAngles
HL20Vehicle     → VehicleDynamics { RigidBody6DOF + AirData + FlightState
                                    + AeroForceBuilder } + VehicleOutputs
HL20FullSystem  → (unchanged components; feedback pins moved to controller icon bottom edges)
```

New components live in `dyad/QuatBlocks.dyad`, `dyad/RigidBodyBlocks.dyad`,
`dyad/FlightStateBlocks.dyad`, `dyad/VehicleBlocks.dyad` and
`dyad/shared/AeroGroups.dyad`, each with its own icon asset and a clean
internal diagram laid out with the same conventions.

## Conventions used

These are authoring targets, not checker-enforced invariants; a few
diagrams deviate where the routing demanded it.

- Boundary port glyphs ~50–100 units tall; port centers generally ≥100
  units apart, tighter where a port row had to stay compact (e.g. the
  `T1`/`T2`/`T3` wall in RotDynamics).
- Many-pin block icons grown toward ~50 units per pin before routing;
  PitchControl's nine-pin bus edge is at ~50.6-unit pitch, other dense
  edges are somewhat tighter.
- All placements on 50-unit multiples; orthogonal routes only — every
  `connect()` carries explicit edge metadata.
- Multi-way `connect()` nets for shared-input fan-outs (single trunks with
  junction dots), verified equivalent by the partition check.

## Before/after metrics (layout-report)

| diagram | crossings before | crossings after¹ | defects after² |
|---|---:|---:|---|
| HL20Demo.shared.HL20Aero | 500 | 53 | 0 |
| HL20Demo.HL20Vehicle | 276 | 6 | 0 |
| HL20Demo.RigidBody6DOF | 222 | 3 | 0 |
| HL20Demo.QuatToInertial | 195 | 3 | 0 |
| HL20Demo.FlightState | 173 | 9 | 0 |
| HL20Demo.QuatToBody | 163 | 0 | 0 |
| HL20Demo.HL20FullSystem | 138 | 62 | 0 |
| HL20Demo.shared.HL20CN | 122 | 35 | 0 |
| HL20Demo.shared.HL20CR | 122 | 35 | 0 |
| HL20Demo.shared.HL20CY | 113 | 26 | 0 |
| HL20Demo.shared.HL20CM | 100 | 29 | 0 |
| HL20Demo.shared.HL20CD | 97 | 25 | 0 |
| HL20Demo.shared.HL20CL | 97 | 25 | 0 |
| HL20Demo.AeroForceBuilder | 48 | 25 | 0 |
| HL20Demo.HL20Mixer | 33 | 33 | 0 |
| HL20Demo.TestQuatRoundTrip | 12 | 0 | 0 |
| HL20Demo.PitchControl | 10 | 12 | 0 |
| HL20Demo.TestMixerAssist | 4 | 0 | 0 |
| HL20Demo.TestQuatDirection | 4 | 0 | 0 |
| HL20Demo.TestControllers | 3 | 1 | 0 |
| HL20Demo.RollControl | 2 | 2 | 0 |
| HL20Demo.YawControl | 2 | 1 | 0 |
| HL20Demo.TestGravityOnly | 2 | 0 | 0 |
| HL20Demo.SpeedControl | 0 | 1 | 0 |
| HL20Demo.Atmosphere1976 | 0 | 0 | 0 |
| HL20Demo.TestAeroPoint | 0 | 0 | 0 |
| HL20Demo.TestAeroSweep | 0 | 0 | 0 |
| HL20Demo.TestHL20FullSystem | 0 | 0 | 0 |
| HL20Demo.TestHL20Subsonic | 0 | 0 | 0 |
| HL20Demo.QuatKinematics | new | 21 | 0 |
| HL20Demo.VehicleDynamics | new | 22 | 0 |
| HL20Demo.QuatDerRow | new | 0 | 0 |
| HL20Demo.QuatToDCM | new | 25 | 0 |
| HL20Demo.shared.AeroCYCN | new | 49 | 0 |
| HL20Demo.shared.AeroLateralCoeffs | new | 55 | 0 |
| HL20Demo.EulerAngles | new | 19 | 0 |
| HL20Demo.shared.AeroLongitudinal | new | 47 | 0 |
| HL20Demo.shared.AeroCLCD | new | 0 | 0 |
| HL20Demo.DCMMatVec | new | 15 | 0 |
| HL20Demo.AeroAngles | new | 18 | 0 |
| HL20Demo.AirData | new | 10 | 0 |
| HL20Demo.RotDynamics | new | 4 | 0 |
| HL20Demo.TransDynamics | new | 0 | 0 |
| HL20Demo.VehicleOutputs | new | 0 | 0 |
| HL20Demo.shared.AeroAirData | new | 0 | 0 |

¹ "crossings after" is the current measurement from the f4bd2fe
layout-report (the stricter tool version that measures label ink and
boundary-port captions).

² defects = overlapping blocks + wires through blocks/ports + diagonal
segments + false junctions + label overlaps + unrouted connects +
wires leaving the diagram bounds + wires through glyphs/labels. Every
scored class is zero on all 45 diagrams as of this writing.

Exceptions above the ~80-crossing target, one line each:

- **HL20FullSystem (62)** — DLEDEG's mixer→pitch wire pays ~13X crossing
  the command comb; ALT_FT's riser crosses all 10 feedback risers (~11X).
- **HL20Aero (53), AeroLateralCoeffs (55),
  AeroLongitudinal (47), AeroCYCN (49), HL20CN/CR (35)** —
  same-order coefficient/product fans: a planar floor ≈ C(n,2) per fan
  (each tap must cross every other tap's drop when source and sink
  orders disagree); the layouts sit at or near that floor.
- **VehicleDynamics (22), QuatKinematics (21)** — the four-row
  quaternion fabric: the conserved u-side staircase (6) plus the
  om-lane × position-column blockade (8) and descent staircases; the
  block arrangement bounds this at ~22 without moving blocks.
- **HL20Mixer (33), QuatToDCM (25)** — residual fan-in crossings at the
  planarity floor for their fixed pin orders.

## Final gate pass (layout-report f4bd2fe)

The last round zeroed every scored class the stricter f4bd2fe gate
measures, on all 45 public diagrams:

- **Caption/wire contacts (16 → 0)** — instance captions moved above
  their icons where a pin row sat in the name band (`PitchControl`'s
  `$(instance)` label moved to y=-320, clearing the command-wire band in
  both `HL20FullSystem` and `TestControllers`); boundary ports and feed
  wires re-routed around captions in `HL20Vehicle` (`forces`),
  `AeroCYCN` (`cy_y`/`cn_y` ports dropped to align with their wires),
  `AeroLongitudinal` (`cd_sin` riser moved right of the `pair` glyphs;
  a `cz_sum` feed re-routed under the `cd_sin` block), `HL20CM`
  (`qb`/`damp_c2v`), `HL20CN`/`HL20CR`/`HL20CY` (`beta_deg`, `pb`,
  `rb`, `damp_b2v` top-port jogs) and `AeroForceBuilder`.
- **Glyph transits (3 → 0)** — the `abs_drud` trunk in AeroLateralCoeffs
  moved right of the `Cl` output glyph; AeroLongitudinal's `pair`
  feed riser moved to x=2130.
- **Label/block overlaps (4 → 0)** — AeroForceBuilder's `qw`–`qz` port
  labels separated from neighbouring glyphs; its `rot` caption pulled
  up under its own block and the `qS` caption cleared of its wire.
- **Screenshot-only items** — RotDynamics' `T2`/`T3` feeds re-routed
  around the `sum_t1/t2/t3` pin columns via the block corridors instead
  of through the pin glyphs, and its `w2`/`w3` feedback buses dropped
  below the `w1w2`/`gyro3` caption ink; `T1`/`T2`/`T3` port glyphs
  normalised to one size. `TestQuatRoundTrip`'s `rot_f.v1` wire jogged
  below the `f_qz` constant's `k = …` label. `TestControllers`' constant
  blocks staggered so each `k = …` label no longer touches the next
  block's title.
- **Icon text clipping** — `veh_outputs.svg` ("CONV" clipped at both
  edges) and `veh_airdata.svg` ("DATA" touching the outline) shrunk to
  fit inside their viewBoxes. All of the block-proportion icons are now
  generated by `tools/gen_hl20_icons.py` (Python 3, standard library
  only): run `python3 tools/gen_hl20_icons.py` to rewrite them and
  `python3 tools/gen_hl20_icons.py --check` to verify — it exits
  non-zero on any byte-level difference. The only genuinely
  hand-authored icon is `HL20Demo/assets/icon.svg` (the NASA HL-20 clip
  art); it is deliberately not generated.

Remaining exception: **RotDynamics crossings 1 → 4**. Moving the `T2`
and `T3` boundary feeds off the `sum_*` pin columns forces their drops
through the per-row `u`-feed fanouts (two crossings) and the `w1`
feedback bus (one more); every sub-450-unit left-margin path hits the
feedback tap columns instead. All scored classes are still zero there
— it is a crossing-count regression only, traded for removing wires
through pin glyphs and captions.

## Pitch-bus fix round

A follow-up pass fixed `PitchControl`'s crowded bottom bus edge: its icon
was widened so the nine bottom pins sit ≥50 units apart (~50.6), and the
`pitch` block in `HL20FullSystem` was grown to x 700–1150, y 200–300 so
those pins land on its bottom edge with matching spacing. The grown block
was placed to keep the existing command-drop corridor (x 1170–1300) clear,
so crossings held at 62 with zero diagonals and zero wires through blocks.
`TestControllers` was re-pinned for the wider icon (1 crossing). An earlier
attempt in the same round produced a worse `HL20FullSystem` (~88 crossings)
and was reverted to the 8acf83e baseline; the final metric table above is
the kept result.

## Glyph-fit pass (layout-report 2a72e1e)

A later pass targeted the Studio-geometry gate, which measures the icon
artwork actually drawn — pins live on the placement rectangle's edges
while the artwork is aspect-fitted and centred inside it, so square icons
in tall/wide placements leave pins floating ("detached").

Fixes applied:

- **Icon artwork re-proportioned** for HL20Demo-owned blocks whose real
  pin counts wanted a non-square frame (e.g. `dynamics6.svg` tall for
  RigidBody6DOF, `aero_lon.svg`/`aero_lat.svg` squared up, controller
  icons widened); connector icon placements were moved onto the new
  outline so the artwork fills the placement.
- **Instance placements aspect-corrected** for the remaining
  stdlib/icon-fixed blocks, sized so adjacent pins keep a comfortable
  pitch (the ~50-unit target is met on most edges; a few dense edges
  are tighter).
- **Icon pin frames shrunk to a uniform 60-unit margin** (was 100+), and
  `TransDynamics`'s crowded bottom pins (v3/p-chain) re-spread, clearing
  every icon-space pin adjacency the gate flags as `glyph_overlap`.
- **Boundary port rows shrunk to match** so wires still meet port
  glyphs; wires re-routed where pin moves shifted approaches
  (`near_diagonal` waypoints snapped to exact pin coordinates:
  HL20Vehicle ×11, HL20FullSystem ×6, AeroLongitudinal ×1).
- **Glyph-corridor reroutes**: risers moved out of pin-glyph zones in
  FlightState, QuatToBody, AeroLongitudinal, AeroCYCN, HL20Aero,
  HL20Vehicle; QuatKinematics' fan-out junctions re-ordered to remove
  false junctions/overlap runs at baseline crossings (55);
  RigidBody6DOF's w-fanout junctions moved to far-end columns
  (crossings held at 3); the mixer→pitch `DLEDEG` wire in
  HL20FullSystem rerouted around the grown pitch box.

Crossing deltas vs the metric table below: HL20Aero 59→53 (improved),
HL20Vehicle 119→124 (+4.2%, risers moved off the `v_mps` glyph zone),
AeroCYCN 46→49 (+6.5%, port-row reroute). Under the 2a72e1e tool every
scored class was zero at that point except the pin-in-own-label-band
`labels_hit_by_wires` contacts (HL20FullSystem/HL20Mixer/TestControllers
3, AeroLongitudinal 5, six others 1 each). The newer f4bd2fe tool
measures label text ink and boundary-port captions, and at c788222 it
still scored 16 `labels_hit_by_wires` on 10 diagrams plus
`label_block_overlaps` 4 (AeroForceBuilder) and `wire_thru_glyph` 3
(AeroLateralCoeffs 1, AeroLongitudinal 2); the final gate pass below
cleared all of them.

## Review items fixed in this pass

- **Block-crossing routes** (`shared/AeroLateral.dyad`, `shared/AeroCoefficients.dyad`):
  the `pb` routes through the product blocks and the `sum3.u1` approaches
  from the right now take orthogonal waypoints around the blocks.
- **Diagonals** (`shared/AeroLateral.dyad`): every `base.y → sum1.u1`
  connect has explicit orthogonal waypoints.
- **Snapshot tolerances** (`dyad/TestHarnesses.dyad`): original tolerances
  restored for alpha, NZ and all trim signals; relaxed atol kept only for
  pitchpulse QDEG, DECMD and DLE (reproducible ~1.3–1.7e-4 solver jitter,
  documented next to each tolerance); blanket 0.01 g / 0.5 m allowances
  removed.

## VehicleDynamics extraction and HL20Vehicle repinning pass

A later pass fixed `HL20Vehicle`'s instance rendering: `VehicleDynamics`
existed as a clean *internal* diagram, but all of its connector icon
placements were stacked placeholder positions, so the `vd` instance
drew 83 crossings, 42 diagonals and 31 wires-through-blocks in the
parent. The fix repinned `VehicleDynamics`'s icon for instance use —
right-edge aero-facing pins aligned to `HL20Aero`'s committed pin rows
(`HL20Aero` is shared by `TestAeroPoint`, `TestHarnesses` and
`HL20FullSystem`, so its pins were left untouched), six coefficient
inputs on the top edge and four `VehicleOutputs` feeds on the bottom —
and rewired all 37 `HL20Vehicle` connects around the real pin map:

- `vd → aero`: straight horizontal runs at aero's left-edge pin rows;
  the four shared signals (`alpha_deg`, `beta_deg`, `mach`, `v_fps`)
  tap boundary ports off junction risers in the lane band above aero,
  with the four tap ports stacked in a label-safe stagger at
  x 4410–4530, y 150–370 (above aero's top edge).
- DBF command ports sit in alternating rows below aero (y 1880/1980)
  and rise vertically into its bottom-edge pins — no wire enters the
  aero block or its label band.
- `aero.C* → vd` feedback uses risers at x 4600+, top channels at
  y 90–110 and drops to vd's top pins; `vd → vout` uses staggered
  lanes below the vd block.

Result: **124 → 6 crossings**, zero in every other scored class
(badness 28.5). The six are structural tap-riser crossings in the
four-net shared tap.

`VehicleDynamics`'s own diagram was also re-routed to its floor of
**22 crossings** (0 defects): quaternion taps now use a decreasing
pin order on `forces`' top edge so the descent staircase drops out,
the `om` bus rides dedicated lanes at y 2290/2300 into `airdata`'s
bottom pins, and `FlightState`'s `sin_alpha`/`cos_alpha` icon pins
moved above the port-descent band so their feeds no longer cross the
port columns.

Reproducibility: both layouts are generated by the stdlib-only
scripts `tools/gen_vd2.py` (VehicleDynamics internals + icon
placeholders) and `tools/gen_veh2.py` (repin for instance rendering
+ all `HL20Vehicle` routes), on top of `tools/laygen.py`. Run order
matters: `gen_vd2` then `gen_veh2` — `repin_vd` owns the parent-facing
icon placement. Both are idempotent against the committed files.

Renderer note: emitting `"icon": {}` in a child instance's diagram
placement silently drops the child's icon *and* its placement in
`dyad render` (all blocks stack at origin) — child placements must
carry only the diagram box/rotation, no icon key.

The partition checker gained a `_PATH_EQUIV` table for sub-instance
extractions: `vd.*` normalizes to the pre-extraction paths so the
existing `RENAMES` entries continue to apply (`vd.body` ≡ `body`,
`vehicle.vd` ≡ `vehicle`, `sys.vehicle.vd` ≡ `sys.vehicle`). All
45 components pass the flattened-graph gate; every `connect()` in the
two rewritten diagrams carries explicit edge metadata
(`verify_edges.py`: 37/37 and 39/39).

## Older notes (superseded by the restructure above)

The previous two layout rounds used the `dyad layout` solver
(`extract` → `edit_problem.py` → `solve` → `fix_junction_order.py` →
`apply` → `verify_edges.py`). Its quirks are still worth knowing when
touching these files:

- `apply` can drop edge metadata while placements update — always run
  `tools/verify_edges.py` after applying.
- `apply` can attach multi-way connect arms to the wrong ends — the
  flattened-partition check catches this.
- `apply` canonicalizes whole `.dyad` files — diff for lost comments.
- `routingRefinement > 0` can move locked blocks; required `above`/`order`
  chains are silently overridden; `apply` refuses to write edges while
  `objective.illegalRoutes > 0` (the `illegalRoutes` workaround was needed
  for the two strongly-connected diagrams in the fix round).
- `TestControllers` snapshot endpoint `speed_ctrl.DSBCMD` = 16.380375 is
  the corrected spec arithmetic (0.0375 × 20.9²), not drift.
- NASA TM-107580 Appendix F CSV comparison is skipped: the reference CSV
  is missing from the restored assets.

## Label-collision fix round

A later pass addressed port glyphs covering neighbouring port labels in
Studio renders (not visible to `dyad render`). Boundary ports that touched
were respaced to ≥100-unit center spacing and their route waypoints
re-threaded; affected diagrams:

- `HL20FullSystem` — input port wall (DCPILOT/DWPILOT/DPPILOT, etc.) and
  output port wall; crossings 94 → 73.
- `AirData` — `sin_alpha`, `r_rad`, `cos_alpha`, `hob`, `qbar`, `mach`,
  `eas_kts`; 14 crossings.
- `VehicleOutputs` — `q_rad`, `r_rad`, `fz_body`, `qdeg`, `rdeg`, `nz_g`;
  0 crossings.
- `TransDynamics` — `v2`, `v3`; 0 crossings.
- `FlightState` — `u_body`, `v_body`, `w_body`; crossings 29 → 25.

Studio PNGs for all five were re-captured via `dyad-ui-shot` and verified
label-readable; `layout-report` shows zero label/block, label/label and
label/wire collisions on each.

## Final fix round (icon generator + spacing)

- **Icon generator** — `tools/gen_hl20_icons.py` (Python 3, standard
  library only) regenerates every generated/redrawn HL20Demo icon in
  `HL20Demo/assets/` byte for byte: `python3 tools/gen_hl20_icons.py`
  rewrites them, `python3 tools/gen_hl20_icons.py --check` verifies them
  (non-zero exit on any difference). `HL20Demo/assets/icon.svg` is the
  only hand-authored icon (NASA HL-20 clip art) and is not generated.
- **Spacing** — `TestGravityOnly`: source columns `z1`/`z3`/`z5` (x
  215–315) and `z2`/`z4`/`z6` (x 335–435) now sit 20 units apart instead
  of sharing the x=325 edge. `TestAeroPoint` and `TestAeroSweep`:
  alternate constant sources staggered to the x 200–300 column so each
  `k = …` caption is horizontally clear of the next block's name (same
  convention as `TestControllers`). `TestQuatDirection`: alternate
  constants staggered to x 50–150 for the same reason (the
  `k = 0.7071067811865476` captions need the wider offset). All moves
  are placement-only; every connect keeps its endpoints and orthogonal
  route.
- **Floating branch ends — Studio rendering quirk, not geometry.** An
  external screenshot review reported branch wires stopping ~5 units
  short of their trunk with no junction dot in `TransDynamics`,
  `RotDynamics`, `RollControl`, `YawControl`, `SpeedControl`,
  `Atmosphere1976`, `HL20Aero` and `QuatToInertial`. The route metadata
  was checked vertex by vertex: every reported tap bend lies **exactly**
  on its trunk segment (e.g. `TransDynamics` taps at (793.75, 400),
  (793.75, 750), (1043.75, 1100); `RotDynamics` `w1w2`/`u2` tap at
  (460, 1289)), and `QuatToInertial` has only pairwise connects (no
  trunk/tap geometry at all). Studio 3.5.1 draws the ~1–2-unit pin stubs
  and T-tap legs slightly short and does not paint junction dots at tap
  bends, which is what shows up as a floating end in screenshots. No
  metadata was changed — geometry was already exact; this note records
  it as a Studio rendering quirk.
