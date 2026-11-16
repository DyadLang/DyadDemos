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
  false junctions, zero unrouted connects.

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
| HL20Demo.shared.HL20Aero | 500 | 82 | 0 |
| HL20Demo.HL20Vehicle | 276 | 128 | 0 |
| HL20Demo.RigidBody6DOF | 222 | 3 | 0 |
| HL20Demo.QuatToInertial | 195 | 3 | 0 |
| HL20Demo.FlightState | 173 | 29 | 0 |
| HL20Demo.QuatToBody | 163 | 2 | 0 |
| HL20Demo.HL20FullSystem | 138 | 94 | 0 |
| HL20Demo.shared.HL20CN | 122 | 91 | 0 |
| HL20Demo.shared.HL20CR | 122 | 91 | 0 |
| HL20Demo.shared.HL20CY | 113 | 81 | 0 |
| HL20Demo.shared.HL20CM | 100 | 77 | 0 |
| HL20Demo.shared.HL20CD | 97 | 69 | 0 |
| HL20Demo.shared.HL20CL | 97 | 69 | 0 |
| HL20Demo.AeroForceBuilder | 48 | 56 | 0 |
| HL20Demo.HL20Mixer | 33 | 44 | 0 |
| HL20Demo.TestQuatRoundTrip | 12 | 0 | 0 |
| HL20Demo.PitchControl | 10 | 12 | 0 |
| HL20Demo.TestMixerAssist | 4 | 0 | 0 |
| HL20Demo.TestQuatDirection | 4 | 0 | 0 |
| HL20Demo.TestControllers | 3 | 23 | 0 |
| HL20Demo.RollControl | 2 | 2 | 0 |
| HL20Demo.YawControl | 2 | 1 | 0 |
| HL20Demo.TestGravityOnly | 2 | 0 | 0 |
| HL20Demo.SpeedControl | 0 | 1 | 0 |
| HL20Demo.Atmosphere1976 | 0 | 0 | 0 |
| HL20Demo.TestAeroPoint | 0 | 0 | 0 |
| HL20Demo.TestAeroSweep | 0 | 0 | 0 |
| HL20Demo.TestHL20FullSystem | 0 | 0 | 0 |
| HL20Demo.TestHL20Subsonic | 0 | 0 | 0 |
| HL20Demo.QuatKinematics | new | 65 | 0 |
| HL20Demo.QuatToDCM | new | 62 | 0 |
| HL20Demo.shared.AeroCYCN | new | 61 | 0 |
| HL20Demo.shared.AeroLateralCoeffs | new | 60 | 0 |
| HL20Demo.EulerAngles | new | 53 | 0 |
| HL20Demo.shared.AeroLongitudinal | new | 46 | 0 |
| HL20Demo.shared.AeroCLCD | new | 45 | 0 |
| HL20Demo.DCMMatVec | new | 29 | 0 |
| HL20Demo.AeroAngles | new | 18 | 0 |
| HL20Demo.AirData | new | 14 | 0 |
| HL20Demo.RotDynamics | new | 11 | 0 |
| HL20Demo.TransDynamics | new | 0 | 0 |
| HL20Demo.VehicleOutputs | new | 0 | 0 |
| HL20Demo.shared.AeroAirData | new | 0 | 0 |

¹ defects = overlapping blocks + wires through blocks/ports + diagonal
segments + false junctions + label overlaps + unrouted connects.

Exceptions above the ~80-crossing target, one line each:

- **HL20Vehicle (128)** — 46-pin strongly-connected loop; residual crossings
  are concentrated where the 6-signal force/moment feedback bus descends
  past the input-port wall; the bus lanes are ordered (deep dives first).
- **HL20FullSystem (94)** — 16-signal feedback bus; feedback pins were moved
  to controller icon bottom edges making the bus itself near-zero-crossing;
  remaining crossings sit in the east-side output tap zone (the port-descent
  wall is solid, any eastbound wire pays ~10X).
- **HL20CN / HL20CR (91), HL20CY (81), HL20Aero (82)** — coefficient
  fan-in diagrams: ~12 deflection buses share each table column; crossings
  are the buses crossing each other's taps and are order-optimal for the
  fixed pin order.
- **HL20CM (77)** — same fan-in structure plus the pitch-damper chain.

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
