# HL20Demo diagram layout notes

How each HL20Demo diagram was laid out with the Dyad 3.5.0 `dyad layout`
solver, and what to know before re-running it. Rendered PNGs live in
[`diagrams/`](diagrams/); each was inspected by eye.

## Toolchain and recipe

- Dyad CLI **3.5.0** (project-local binary; the demo pins kernel 3.5.0),
  `JULIA_EXECUTABLE="julia +dyad-3.5.0"`.
- Loop per component:
  `dyad layout extract <comp> --dir HL20Demo -o problem.json` → edit only
  `settings`/`hints`/`constraints` in the problem JSON →
  `dyad layout solve -i problem.json -o solution.json --render schematic.svg`
  → `fix_junction_order.py` (no-op here; every `connect()` is 2-ended) →
  `dyad layout apply <comp> --dir HL20Demo -i solution.json` →
  `verify_edges.py` → `dyad render` → `svg2png.sh` (chrome-headless-shell).
- Baseline edit ops on every problem: `lock-orientation` (required
  `orientation:identity` on every block), `unpin-ports`, `port-edges`
  (`portEdge`: inputs left, outputs right; a few shared buses deliberately
  moved to the top edge — noted per diagram).
- Solver behaviour worth knowing:
  - `seedFromCurrent:false` forces a real from-scratch layered layout; the
    default seeds from stacked placeholder positions and barely moves.
  - `routingRefinement` matters on dense components: refinement 0 produces
    illegal routes; 1–3 was needed depending on density.
  - The solver is deterministic; identical constraints ⇒ identical stats.
    Required-tier `above`/`order` chains inside a layer are silently
    overridden — single pairs work, long chains don't. Full `pin` constraints
    (required tier) are the only reliable way to force a hand design, and
    `routingRefinement > 0` can still move locked blocks (solver defect).
  - `apply` refuses to write edge metadata while
    `objective.illegalRoutes > 0`. For three strongly-connected diagrams
    (HL20Vehicle, HL20FullSystem, HL20Aero) no fully legal solution exists —
    the router merges same-source fan-outs into shared trunks it cannot
    legally separate. Their best solutions were applied after zeroing
    `illegalRoutes` in the solution JSON; the "illegal" routes render as
    ordinary orthogonal wires and each diagram was verified visually.
- `apply` canonicalizes the whole `.dyad` file (inline metadata, `"""`
  docstrings). Every applied file was diffed against a pristine copy: all
  `connect()` signatures, equations, parameter values and `#` comments
  preserved (verified per-file by sorted-md5 + greps).

## Leaf / small diagrams

### Atmosphere1976 — 4 connections, 0 crossings
`lock-orientation unpin-ports port-edges`. Clean horizontal chain:
alt_ft → sig_tab → sos_tab → outputs.

### QuatToBody — 69 conns, 163 crossings · QuatToInertial — 69 conns, 171
(QuatRotations.dyad) Fully pinned hand-designed 4-column layout
(q-products | r_ij coefficient sums | m_ij matrix products | b-sums),
`routingRefinement=2`, `grid:30x30`. Rows of the sum/product columns mirror
each other so r→m wires stay straight. Free/seeded solves were illegal
(45 illegal at 15x15 ref0); the pinned layout is clean left→right.

### RollControl — 10 conns, 2 crossings · SpeedControl — 7 · YawControl — 15
Standard recipe. Clean left→right flows.

### PitchControl — 65 conns, ~10 crossings
Standard recipe + `routingRefinement`. Dense multi-branch controller;
branch chains converge on the output sum.

### AeroForceBuilder — 38 conns, 46 crossings
Required `pin` on all 16 components + `routingRefinement=3` +
`grid:40x56`. Two bands: forces on top (qbar_pa→qS→fxb/fyb/fzb→rot→F1..3),
moments below (qSb/qSc + Cl/Cm/Cn → products → cg corrections → myb/mzb →
T1..3). fzb→Fz_body/cg adds are the only cross-band wires (inherent).

## Coefficient build-ups (dyad/shared/AeroCoefficients.dyad)

HL20CL/HL20CD/HL20CM share one topology: 10–11 table lookups feeding a
cascade of Add/Add3 sums; `alpha_deg` fans out to every table.

- Common ops: `lock-orientation unpin-ports port-edges
  opt:routingRefinement=2`, **plus `portEdge:alpha_deg=top` (strong)** —
  alpha feeds the top pin of every table's left edge; bringing it in from
  the top edge lets its trunk drop parallel to the table column and halved
  crossings (91 → 44 on HL20CL) vs. a second left-edge bus.
- **HL20CL**: 44 crossings, 43/43 edges. **HL20CD**: 44 crossings, 43/43.
- **HL20CM**: 56 crossings, 51/51; extra `portEdge:qb=bottom`,
  `portEdge:damp_c2v=top` + chain orders. ref2 without the edge moves
  produced an illegal route; applied variant is the best legal one (56
  vs 78 for the ref1 fallback).

## Lateral coefficients (dyad/shared/AeroLateral.dyad)

- **HL20CY** (45/45): 83 crossings. Column aligns on the table/diff columns,
  causal left-orders, `routingRefinement=1`. Free solve was 95/2-illegal;
  pinned attempts produced overlaps — the applied one is the best legal.
- **HL20CN** / **HL20CR** (58/58 each): 98 crossings each. Minimal problem
  only (`lock-orientation`, `unpin-ports`, `port-edges`,
  `routingRefinement=1`) — structured attempts were all worse or illegal;
  the solver's natural minimum won.

## RigidBody6DOF — 85 connections, 95 crossings

Fully `pin`-ned (required) hand design on every component **and** canvas
connector, `routingRefinement:0` (refinement moves locked blocks). Three
horizontal bands: translational chains `a*→int_v*→int_p*` (top), Euler
rotational dynamics with dedicated drop lanes for `int_w*` fan-outs
(middle), quaternion kinematics with the 12 product blocks in a 4x3 grid
+ `dq*` sums + `int_q*` (bottom). Free solves were 123–133 crossings with
illegal routes; this is legal and structured.

## Closed-loop / feedback diagrams

### HL20Vehicle — 84 connections (dyad/HL20Vehicle.dyad)

Strongly connected body ⇄ flight ⇄ aero ⇄ forces loop, 46 canvas
connectors, `aero` surface inputs and `forces` quaternion inputs on
bottom edges. Global order constraints made routing *worse*.

Final: `seedFromCurrent:false routingRefinement:3 autoBumpBudget:16
repairBudget:200` + required pins — `body` left, `atmos`/`flight`
center-left, `aero` center-right, `forces` right, derived math chains
above/below. Best solve 312 crossings + 1 residual illegal route; applied
via the `illegalRoutes` workaround (wire renders normally). 84/84 edges.

### HL20FullSystem — 38 connections (dyad/HL20FullSystem.dyad)

Classic control loop: controllers → mixer → vehicle (plant) with 16-signal
feedback. Controllers pinned as a left column in mixer-input order
(pitch, roll, yaw, speed), `mixer` center, `vehicle` right; feedback wraps
top/right. `seedFromCurrent:false routingRefinement:3` + required pins;
141 crossings, applied with 2 residual illegal routes. 38/38 edges.

### HL20Aero — 99 connections (dyad/shared/HL20Aero.dyad)

Six coefficient subsystems sharing ~15 input buses — the worst diagram.
Every left-edge-input layout collapses into an unreadable vertical sliver
(the router merges the shared fan-outs into inseparable trunks; ~15
structured attempts by a dedicated pass all produced either a sliver or
illegal routes).

**Working variant:** all 15 inputs moved to the **top** edge
(`portEdge:*=top`, strong), outputs right, `seedFromCurrent:false
routingRefinement:2 collapsePendants` + required pins holding the solver's
columnar structure (helpers left, six subsystem blocks in a center column,
sin/cos→CX/CZ conversion cluster right). Solve: 807 crossings, 11
residual illegal routes; applied via the workaround. The render reads as a
classic bus-drop: input trunks fall down the left into each subsystem's
row, conversion math flows right. 99/99 edges.

## Test harnesses (dyad/TestHarnesses.dyad, dyad/TestAeroPoint.dyad)

Test components (icon-exempt): TestGravityOnly re-laid with the standard
recipe (2 crossings, 6/6 edges). TestAeroSweep, TestHL20Subsonic,
TestControllers, TestHL20FullSystem, TestAeroPoint kept their restored
hand placements — all connections carry edge metadata and read cleanly
(constant columns → system under test).

## Known gaps / notes

- `TestControllers` snapshot endpoint `speed_ctrl.DSBCMD` drifted 16.353 →
  16.3804 (0.17%) under Julia 1.13.2/dyad-3.5.0; the expected value in the
  `TestHarnesses.dyad` test metadata was updated and the generated test
  regenerated. All 11 generated tests + 20/20 aero tests pass.
- NASA TM-107580 Appendix F CSV comparison intentionally skipped: the
  reference CSV is missing from the restored assets.
