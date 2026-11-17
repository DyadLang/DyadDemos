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

- `tools/partition_check.py` — flattened connect-endpoint partitions
  (through sub-components) compared to the pre-pass snapshot: **every
  existing component boundary MATCH** (e.g. HL20Aero 155/155 nets,
  HL20Vehicle 338/338, HL20FullSystem 450/450).
- Numeric parity of `HL20Demo.shared.HL20Aero` against the spec equations
  (the equation-level implementation): **max |Δ| = 4.44e-16 over 1000
  randomized input cases** (baseline was 4.44e-16).
- `dyad compile` clean; **1549/1549 generated tests + 20/20 aero tests
  pass**, including TestQuatDirection, TestQuatRoundTrip, TestMixerAssist.
- `layout-report` on all 43 diagrams: **zero** overlapping ports/blocks,
  zero wires through blocks or port glyphs, zero diagonal segments, zero
  false junctions, zero unrouted connects, zero wires routed outside the
  diagram bounding box. Five diagrams carry a single structural
  label/wire contact each (six total), documented below — a bottom-edge
  pin sitting inside its own block's name-label band.

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
all 43 diagrams except six structural label/wire contacts on five
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
FlightState     → QuatToBody + AeroAngles + EulerAngles
HL20Vehicle     → RigidBody6DOF + AirData + FlightState + AeroForceBuilder + VehicleOutputs
HL20FullSystem  → (unchanged components; feedback pins moved to controller icon bottom edges)
```

New components live in `dyad/QuatBlocks.dyad`, `dyad/RigidBodyBlocks.dyad`,
`dyad/FlightStateBlocks.dyad`, `dyad/VehicleBlocks.dyad` and
`dyad/shared/AeroGroups.dyad`, each with its own icon asset and a clean
internal diagram laid out with the same conventions.

## Conventions used

- Boundary port glyphs 50 units tall; port centers ≥100 units apart.
- Many-pin block icons grown to ~50 units per pin before routing.
- All placements on 50-unit multiples; orthogonal routes only — every
  `connect()` carries explicit edge metadata.
- Multi-way `connect()` nets for shared-input fan-outs (single trunks with
  junction dots), verified equivalent by the partition check.

## Before/after metrics (layout-report)

| diagram | crossings before | crossings after | defects after¹ |
|---|---:|---:|---|
| HL20Demo.shared.HL20Aero | 500 | 59 | 0 |
| HL20Demo.HL20Vehicle | 276 | 119 | 2 lbl/wire |
| HL20Demo.RigidBody6DOF | 222 | 3 | 0 |
| HL20Demo.QuatToInertial | 195 | 3 | 0 |
| HL20Demo.FlightState | 173 | 9 | 0 |
| HL20Demo.QuatToBody | 163 | 0 | 0 |
| HL20Demo.HL20FullSystem | 138 | 62 | 1 lbl/wire |
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
| HL20Demo.TestControllers | 3 | 1 | 1 lbl/wire |
| HL20Demo.RollControl | 2 | 2 | 0 |
| HL20Demo.YawControl | 2 | 1 | 0 |
| HL20Demo.TestGravityOnly | 2 | 0 | 0 |
| HL20Demo.SpeedControl | 0 | 1 | 0 |
| HL20Demo.Atmosphere1976 | 0 | 0 | 0 |
| HL20Demo.TestAeroPoint | 0 | 0 | 1 lbl/wire |
| HL20Demo.TestAeroSweep | 0 | 0 | 1 lbl/wire |
| HL20Demo.TestHL20FullSystem | 0 | 0 | 0 |
| HL20Demo.TestHL20Subsonic | 0 | 0 | 0 |
| HL20Demo.QuatKinematics | new | 55 | 0 |
| HL20Demo.QuatToDCM | new | 25 | 0 |
| HL20Demo.shared.AeroCYCN | new | 46 | 0 |
| HL20Demo.shared.AeroLateralCoeffs | new | 55 | 0 |
| HL20Demo.EulerAngles | new | 19 | 0 |
| HL20Demo.shared.AeroLongitudinal | new | 46 | 0 |
| HL20Demo.shared.AeroCLCD | new | 45 | 0 |
| HL20Demo.DCMMatVec | new | 15 | 0 |
| HL20Demo.AeroAngles | new | 18 | 0 |
| HL20Demo.AirData | new | 10 | 0 |
| HL20Demo.RotDynamics | new | 1 | 0 |
| HL20Demo.TransDynamics | new | 0 | 0 |
| HL20Demo.VehicleOutputs | new | 0 | 0 |
| HL20Demo.shared.AeroAirData | new | 0 | 0 |

¹ defects = overlapping blocks + wires through blocks/ports + diagonal
segments + false junctions + label overlaps + unrouted connects +
wires leaving the diagram bounds. The only non-zero defect class is
label/wire.

Remaining label/wire contacts (5 diagrams, 6 total) are structural: a
bottom-edge pin sits directly above its own block's name label, so any
orthogonal approach crosses the label band. Dodging every such pin
requires braided edge-runs that add more crossings than they save;

- **HL20Vehicle (2)** — `aero` and `forces` name labels.
- **HL20FullSystem (1)** — the `pitch` controller name label.
- **TestControllers, TestAeroPoint, TestAeroSweep (1 each)** — the
  driven component's name label.

Exceptions above the ~80-crossing target, one line each:

- **HL20Vehicle (119)** — 46-pin strongly-connected loop; residual
  crossings concentrate at the mixer→vehicle command fan (a complete
  comb: every column through the fan crosses 7–8 wires) and the
  ALT_FT→NZ feedback descents across the riser fence. ~110 is the
  practical floor without moving blocks.
- **HL20FullSystem (62)** — DLEDEG's mixer→pitch wire pays ~13X crossing
  the command comb; ALT_FT's riser crosses all 10 feedback risers (~11X);
  the `pitch` label contact is structural as above.
- **HL20Aero (59), AeroLateralCoeffs (55), QuatKinematics (55),
  AeroLongitudinal/AeroCYCN (46), AeroCLCD (45), HL20CN/CR (35)** —
  same-order coefficient/product fans: a planar floor ≈ C(n,2) per fan
  (each tap must cross every other tap's drop when source and sink
  orders disagree); the layouts sit at or near that floor.
- **HL20Mixer (33), QuatToDCM (25)** — residual fan-in crossings at the
  planarity floor for their fixed pin orders.

## Pitch-bus fix round

A follow-up pass fixed `PitchControl`'s crowded bottom bus edge: its icon
was widened so the eight bottom pins sit ≥50 units apart (~50.6), and the
`pitch` block in `HL20FullSystem` was grown to x 700–1150, y 200–300 so
those pins land on its bottom edge with matching spacing. The grown block
was placed to keep the existing command-drop corridor (x 1170–1300) clear,
so crossings held at 62 with zero diagonals and zero wires through blocks.
`TestControllers` was re-pinned for the wider icon (1 crossing). An earlier
attempt in the same round produced a worse `HL20FullSystem` (~88 crossings)
and was reverted to the 8acf83e baseline; the final metric table above is
the kept result.

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

## Older notes (superseded by the restructure above)

The previous two layout rounds used the `dyad layout` solver
(`extract` → `edit_problem.py` → `solve` → `fix_junction_order.py` →
`apply` → `verify_edges.py`). Its quirks are still worth knowing when
touching these files:

- `apply` can drop edge metadata while placements update — always run
  `HL20Demo/tools/verify_edges.py` after applying.
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
