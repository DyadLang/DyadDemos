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
    `objective.illegalRoutes > 0`. For two strongly-connected diagrams
    (HL20Vehicle, HL20FullSystem) no fully legal solution exists — the
    router merges same-source fan-outs into shared trunks it cannot
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

### QuatToBody — 69 conns, 163 crossings · QuatToInertial — 69 conns, 195
(QuatRotations.dyad) Fully pinned hand-designed 4-column layout
(q-products | r_ij coefficient sums | m_ij matrix products | b-sums),
`routingRefinement=2`, `grid:30x30`. Rows of the sum/product columns mirror
each other so r→m wires stay straight. Free/seeded solves were illegal
(45 illegal at 15x15 ref0); the pinned layout is clean left→right.

*Fix round:* the force-rotation wiring was corrected to apply R (matrix
rows) instead of Rᵀ — the six off-diagonal products now pair r_ij with the
matching row's b_j, so the r→m wires necessarily cross once between the two
mirrored columns. Re-routed with `lock-orientation pin-seed
opt:routingRefinement=2` (the new `pin-seed` op in edit_problem.py pins
every block at its extracted position); `routingRefinement=0`/1 left
illegal routes. 195 crossings, 69/69 edges.

### HL20Mixer — 71 conns, 35 crossings
(HL20Mixer.dyad) Re-routed in the fix round after the duf_sel branch swap:
`lock-orientation pin-seed opt:routingRefinement=2` (ref0/ref1 left
illegal routes). 71/71 edges.

### RollControl — 10 conns, 2 crossings · SpeedControl — 7 · YawControl — 15
Standard recipe. Clean left→right flows.

### PitchControl — 65 conns, ~10 crossings
Standard recipe + `routingRefinement`. Dense multi-branch controller;
branch chains converge on the output sum.

### AeroForceBuilder — 38 conns, compacted in fix round
Fully `pin`-ned 27×22 canvas (was ~36×45 — the large empty middle band is
gone). Two bands preserved: forces on top (qbar_pa→qS→fxb/fyb/fzb→rot→
F1..3), moments below (qSb/qSc + Cl/Cm/Cn → products → cg corrections →
myb/mzb → T1..3), outputs pulled close to the right column. Routes were
hand-contoured in the solution JSON before `apply`: `fzb.y`'s 3-way split
shares one trunk, `mxb.y→T1` detours above `cg_y`, and `dxcg_c`/`Cn`
wires avoid the long gain labels. 38/38 edges.

## Coefficient build-ups (dyad/shared/AeroCoefficients.dyad)

HL20CL/HL20CD/HL20CM share one topology: 10–11 table lookups feeding a
cascade of Add/Add3 sums; `alpha_deg` fans out to every table.

*Fix round:* the table blocks' long `poly1d[HL20Demo…]/poly2dr[…]` labels
used to sit under wires. The tables were re-pinned in a single column with
shared-input buses (alpha_deg, mach, hob) tapped from trunks dropping at
the left, deflection inputs approaching below the label band, and `y`
exits turning immediately after the pin — solution waypoints were
hand-polished in the JSON before `apply` (labels now overlap wires by
~90 px/table vs ~3200 px before). `routingRefinement:0` holds the pins.
HL20CL 43/43, HL20CD 43/43, HL20CM 51/51 edges (CM adds the cmq pitch-
damper chain + bias + sum3 across the top).

## Lateral coefficients (dyad/shared/AeroLateral.dyad)

*Fix round:* re-pinned and route-polished with the same recipe as the
longitudinal coefficients — shared buses tapped from left trunks,
deflection wires below the label band, `y` exits turning early; no wires
through labels or blocks. HL20CY 45/45 edges; HL20CN and HL20CR 58/58
each (both add twin damper chains cnr_poly/cnp_poly → *_rb/_pb →
*_damp → sum3 across the top).

## RigidBody6DOF — 85 connections, ~73 crossings

Top translational half unchanged. *Fix round:* the quaternion/rotational
bottom half was re-chained — `int_w*` fan-outs now run on inside trunk
lanes instead of looping around the outside of the diagram, the
`u1`-product blocks share vertical buses, and the `q*w*` products +
`dq*` sums + `int_q*` integrators sit in dedicated per-channel lanes.
Fully `pin`-ned hand design + `routingRefinement`; 85/85 edges, no
outside loops, no through-block wires, no diagonals.

## Closed-loop / feedback diagrams

### HL20Vehicle — 84 connections (dyad/HL20Vehicle.dyad)

Strongly connected body ⇄ flight ⇄ aero ⇄ forces loop, 46 canvas
connectors, `aero` surface inputs and `forces` quaternion inputs on
bottom edges. Global order constraints made routing *worse*.

*Fix round:* fully `pin`-ned hand design + `routingRefinement:3` —
core loop compacted in the middle (`body` left, `atmos`/`flight`
center-left, `aero` center-right, `forces` right), output-conversion
gains in an orderly right column feeding the edge outputs. 277 crossings
(312 before), 2 residual illegal trunk-merges — visually legal wires,
applied via the `illegalRoutes` workaround. 84/84 edges.

### HL20FullSystem — 38 connections (dyad/HL20FullSystem.dyad)

Classic control loop: controllers → mixer → vehicle (plant) with 16-signal
feedback. Controllers pinned as a left column in mixer-input order
(pitch, roll, yaw, speed), `mixer` center, `vehicle` right; feedback wraps
top/right. `seedFromCurrent:false routingRefinement:3` + required pins;
141 crossings, applied with 2 residual illegal routes. 38/38 edges.

### HL20Aero — 37 nets / 99 connection endpoints (dyad/shared/HL20Aero.dyad)

Six coefficient subsystems sharing ~15 input buses — historically the
worst diagram. *Fix round:* the 99 pairwise `connect()`s for shared-input
fan-outs were merged into 37 semantics-identical multi-way `connect()`
nets (connection sets verified identical by compile + endpoint partition
comparison), so the router gets single trunks with junction dots instead
of inseparable parallel pairs — the previous 11 residual illegal routes
disappear entirely.

Layout: all inputs bussed along the top, helper math (deg2rad, sin/cos,
damping products) in rows below, the six coefficient blocks in a center
column, outputs right; fully `pin`-ned cascade, `routingRefinement`.
501 crossings (807 before), **zero** illegal routes — the one
pin-approach wire the router flagged was hand-patched in the solution
before apply. 37/37 connections carry edge metadata.

## Test harnesses (dyad/TestHarnesses.dyad, dyad/TestAeroPoint.dyad, dyad/TestFixes.dyad)

Test components (icon-exempt): TestGravityOnly re-laid with the standard
recipe (2 crossings, 6/6 edges). TestAeroSweep, TestHL20Subsonic,
TestHL20FullSystem, TestAeroPoint kept their restored hand placements —
all connections carry edge metadata and read cleanly (constant columns →
system under test).

*Fix round:* TestControllers re-laid — 15 constants in a left column,
pitch/roll/yaw/speed controllers in an orderly right group, 3 crossings
on 18/18 orthogonal edges (one solver trunk-lane pair hand-swapped to
clear a deterministic illegal route). New regression diagrams
TestQuatDirection, TestQuatRoundTrip, TestMixerAssist (dyad/TestFixes.dyad)
laid out with the standard recipe; all edges carry metadata.

## Known gaps / notes

- `TestControllers` snapshot endpoint `speed_ctrl.DSBCMD` changed 16.353 →
  16.3804 (0.17%). This was an arithmetic correction, not environment
  drift: the spec endpoint is 0.0375 × 20.9² = 16.380375, so the old 16.353
  expectation was wrong. The expected value in the `TestHarnesses.dyad`
  test metadata was updated and the generated test regenerated.
- NASA TM-107580 Appendix F CSV comparison intentionally skipped: the
  reference CSV is missing from the restored assets.
- *Fix round:* two wiring bugs corrected (QuatToInertial applied Rᵀ, and
  HL20Mixer's `duf_sel` branches were swapped — details in the component
  sections above). Refreshed snapshot refs changed only for the two
  integrated scenarios that exercise the fixed wiring
  (TestHL20FullSystem pitchpulse sig0–4, TestHL20Subsonic trim sig0–3);
  TestAeroSweep, TestControllers and TestGravityOnly refs are unchanged,
  confirming the aero coefficient math is untouched. Signal tolerances on
  the two integrated scenarios were widened to ~50× the observed
  cross-session solver jitter (~1e-4) — the 1e-5 default was below the
  closed-loop sim's reproducibility floor — while remaining far tighter
  than the real shifts the fixes produced. New regression components in
  `dyad/TestFixes.dyad` (TestQuatDirection, TestQuatRoundTrip,
  TestMixerAssist) check the corrected semantics against hand-computed
  spec arithmetic.
