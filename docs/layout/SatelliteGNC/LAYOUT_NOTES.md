# SatelliteGNC layout notes (Dyad 3.5)

Re-layout of the four SatelliteGNC diagrams that have two or more
subcomponents. Only icon and placement metadata changed (plus three new icons and
four touched icons in `assets/`). Equations, connections, declarations and
comments are identical to the previous revision: `tools/strip_meta.py` on the old
and new version of every `.dyad` file gives the same output. `dyad compile .`
regenerates every file in `generated/` byte-identically.

| diagram | before | what was done | after |
|---|---|---|---|
| `TestSatelliteClosedLoop` | F: plant left of the controller, ports floating off the icons, diagonal wires | controller → plant, angle and rate feedback nested over the top | 0 crossings, no diagonals |
| `TestAllocatorJets` | F: all 9 blocks stacked on one spot | allocator on the left, the 8 jets in a 2 × 4 grid in reading order, even jets fed through the gap between the columns | 0 crossings |
| `TestFullGNC` | F: wires crossing everywhere, diagonals, unreadable labels | trajectories → controller → plant → observer; measured angles and estimated rates fed back over the top; torques branch to the observer under the plant | 6 crossings, all at the two bus branches (junction dots drawn) |
| `TestFullGNC6DOF` | F: all 15 blocks stacked on one spot | bottom row trajectories → controller → allocator → jets (2 × 4); top row plant → observer; feedback over the top; torques branch up to the observer between plant and allocator | 6 crossings, all at the two bus branches (junction dots drawn) |

Before and after renders are `<Diagram>.before.png` / `<Diagram>.after.png`
(rendered with `dyad render` and headless Chrome, at most 1100 px).

## 1. Child components (bottom-up)

All child icons are square, so the icon art and the instance label are never
stretched. Every connector has an `icon` placement box, and an identical
`diagram` placement box, centred on the left edge (inputs) or the right edge
(outputs). Each port sits on the 50-unit grid when the instance box is on it.
Offsets are in parent-diagram units from the top of the box, and adjacent ports
are 50 apart. The tool that writes them is `tools/set_ports.py`; it also sets a
connector box of 30 parent units and an instance label 36 parent units high
(`labels` with a font size of `36*1000/S`).

| component | S | left (inputs) | right (outputs) |
|---|---|---|---|
| `TrapezoidalProfile` | 200 | – | angle_ref 50, rate_ref 100, accel_ref 150 |
| `SatelliteBody` | 400 | tau_x 150, tau_y 200, tau_z 250 | phi_out 50, theta_out 100, psi_out 150 · wx_out 250, wy_out 300, wz_out 350 |
| `LuenbergerObserver` | 400 | phi_meas 50, theta_meas 100, psi_meas 150 · tau_x 250, tau_y 300, tau_z 350 | phi_hat 50, theta_hat 100, psi_hat 150 · wx_hat 250, wy_hat 300, wz_hat 350 |
| `AttitudeController` | 800 | phi/theta/psi_meas 50–150, wx/wy/wz_meas 200–300 · phi_ref 350, wx_ref 400, ax_ff 450 · theta_ref 500, wy_ref 550, ay_ff 600 · psi_ref 650, wz_ref 700, az_ff 750 | tau_x 350, tau_y 400, tau_z 450 |
| `ThrusterAllocator` | 500 | Fx/Fy/Fz_cmd 100–200 · tau_x/y/z_cmd 300–400 | cmd1–cmd4 50–200 · cmd5–cmd8 300–450 |
| `ReactionJet` | 400 | cmd 200 | fx/fy/fz_out 50–150 · tx/ty/tz_out 250–350 |
| `SatelliteBody6DOF` | 700 | tau_x/y/z 150–250 · fx/fy/fz 450–550 | phi/theta/psi_out 50–150, wx/wy/wz_out 200–300 · x/y/z_out 400–500, vx/vy/vz_out 550–650 |

`·` separates groups, which are one grid step further apart. The controller's
measurement inputs are at the top, so feedback that comes back over the top of a
diagram reaches them without crossing anything. Its references are grouped per
axis (angle, rate, acceleration feed-forward), so each `TrapezoidalProfile`
block's three outputs run in a straight, parallel bundle.

Instance sizes in the four harnesses (`tools/set_boxes.py`) are the S above.

Icons (`assets/`):
- `AttitudeController.svg` (×1.2), `LuenbergerObserver.svg` and
  `TrapezoidalProfile.svg` (×1.15): the existing art is wrapped in a centred
  scale so that its outer block reaches the icon edge, where the connectors are.
- `SatelliteBody.svg`: a block outline was added for the connectors to sit on.
- New: `ReactionJet.svg`, `ThrusterAllocator.svg` and `SatelliteBody6DOF.svg`.
  These three components had no icon before and rendered as the generic
  placeholder.

## 2. Harness layout: ops and hints per diagram

Every diagram goes through `tools/relayout2.sh COMPONENT OUTDIR ops...`:
1. `dyad layout extract`;
2. `edit_problem.py` with the ops (from the scout's layout tools);
3. `dyad layout solve`, whose placements are kept;
4. `tools/reroute.py`, which replaces every wire route;
5. `fix_junction_order.py`;
6. `dyad layout apply`, repeated until `verify_edges.py` and
   `tools/verify_applied.py` confirm that the file holds the solution;
7. with `JUNCTIONS=1`: `tools/add_junctions.py`, then `dyad format -i`;
8. `dyad render`.

Pins are `add:{"id":"pin:X","kind":{"kind":"pin","componentId":"X","at":{"x":..,"y":..}},"strength":{"tier":"required","weight":1}}`,
in half-square grid units (box centres). `tools/relayout_all.sh` contains every
run below verbatim.

All four runs share the ops `lock-orientation unpin-ports port-edges`.

**TestSatelliteClosedLoop**
- Problem edits: `grid:26x16`; pins ctrl (16,18), sat (34,18).
- reroute: `--cross 12 --prefer top --box 0,0,52,27`.

**TestAllocatorJets**
- Problem edits: `grid:22x25`; pins alloc (6,24), jet1 (22,6), jet2 (34,6),
  jet3 (22,18), jet4 (34,18), jet5 (22,30), jet6 (34,30), jet7 (22,42),
  jet8 (34,42). The solver shifts everything by +1 in x.
- reroute: `--cross 12 --box 0,0,44,50` plus these vias:
  - `--via alloc.cmd2->jet2.cmd@29,12`
  - `--via alloc.cmd4->jet4.cmd@29,24`
  - `--via alloc.cmd6->jet6.cmd@29,36`
  - `--via alloc.cmd8->jet8.cmd@29,48`

  Each even jet is reached through the gap between the two jet columns, below
  its odd neighbour.

**TestFullGNC** (`JUNCTIONS=1`)
- Problem edits: `grid:32x20`; pins traj_phi (4,18), traj_theta (4,23),
  traj_psi (4,28), ctrl (22,18), sat (40,18), obs (54,18).
- reroute: `--cross 12 --prefer top --box 1,1,64,31 --last ctrl.tau_x->obs.tau_x,ctrl.tau_y->obs.tau_y,ctrl.tau_z->obs.tau_z`.

**TestFullGNC6DOF** (`JUNCTIONS=1`)
- Problem edits: `grid:40x40`; pins traj_phi (4,40), traj_theta (4,45),
  traj_psi (4,50), ctrl (22,40), alloc (41,38), sat (41,20), obs (58,17),
  jet1 (58,28), jet2 (70,28), jet3 (58,40), jet4 (70,40), jet5 (58,52),
  jet6 (70,52), jet7 (58,64), jet8 (70,64).
- reroute: `--cross 12 --prefer top --box 1,1,80,72` plus these vias:
  - `--via alloc.cmd1->jet1.cmd@52,34@52,28`
  - `--via alloc.cmd2->jet2.cmd@64,34`
  - `--via alloc.cmd4->jet4.cmd@64,46`
  - `--via alloc.cmd6->jet6.cmd@64,58`
  - `--via alloc.cmd8->jet8.cmd@64,70`
  - `--via ctrl.tau_x->obs.tau_x@33,39@33,29@49,29@49,18`
  - `--via ctrl.tau_y->obs.tau_y@34,40@34,30@50,30@50,19`
  - `--via ctrl.tau_z->obs.tau_z@35,41@35,31@51,31@51,20`
  - `--first ctrl.tau_x->obs.tau_x,ctrl.tau_y->obs.tau_y,ctrl.tau_z->obs.tau_z`

  The torque branches leave the bus in x, y, z order from left to right, so
  they nest when they turn towards the observer. Routing them first closes the
  gap under the plant, so the angle feedback goes over the top.

### Reproducing

From `SatelliteGNC/` at the commit before this change, with the icons from
`assets/` copied in, and with `DYAD` (Dyad CLI 3.5.0), `TOOLS` (the scout layout
tools: `edit_problem.py`, `fix_junction_order.py`, `verify_edges.py`,
`svg2png.sh`) and `CHROME` set:

    docs/layout/SatelliteGNC/tools/reproduce.sh OUTDIR [BEFORE_SVG_DIR]

The script runs `dyad format`, then `set_ports.py`, `set_boxes.py`,
`relayout_all.sh` and `drop_empty_relations.py`. From a clean export of the
previous commit it rebuilt all nine `.dyad` files byte-identical to the
committed ones.

## 3. Why the extra tools (Dyad 3.5.0 behaviour)

- **The solver's router.** It assigns channel tracks greedily. Feedback bundles
  alternate over/under, jogs between offset blocks cross, and a branch loops
  round its own bus. For the two GNC loops it also reports illegal routes, and
  `apply` refuses those. `reroute.py` keeps the solver's placements and
  re-routes every wire with a grid search that:
  - never overlaps or bends on another net;
  - avoids boxes, labels and foreign ports;
  - charges for crossings and bends;
  - lets wires of one net share track, so they branch;
  - orders wires so that bundles nest.

  `--via`, `--first` and `--last` pin the routes that need a specific plan.
- **`routingRefinement` was not used.** Its sub-grid (25-unit) tracks would be
  replaced by `reroute.py` anyway.
- **`order`/`align` hints across layers were dropped as unsatisfiable**, so
  block positions are set with required `pin` constraints instead.
- **`apply` sometimes prints `wrote` but leaves the previous layout in the
  file.** It happened in both reproduction runs. `relayout2.sh` re-applies until
  `verify_applied.py` finds every placement and route of the solution in the
  file.
- **`apply` writes a branching connection as a single edge, with no junction
  dot**, so a branch reads like a crossing. `add_junctions.py` rewrites the
  branching connection into Dyad's port → junction → port form.
- **`apply` and `format` re-print the whole file** and give `analysis` blocks
  that had none an empty `relations` section. `drop_empty_relations.py` removes
  those again, to keep the diff metadata-only.

## 4. What is left, and why

- **6 crossings each in TestFullGNC and TestFullGNC6DOF.** Two 3-wire buses
  branch to two blocks: the plant's angles go to the controller and the
  observer, and the controller's torques go to the allocator or plant and to the
  observer. Both destinations take the wires in the same order, so each branch
  of three wires has to cross the bus at least 0+1+2 = 3 times. A junction dot
  marks each branch point.
- **Unwired ports.** Some ports are driven by equations, not `connect()`, so
  they have no wires. Changing that would mean changing connections, which is
  out of scope. The ports are:
  - the controller's 9 reference inputs in TestSatelliteClosedLoop;
  - the allocator's force/torque command inputs in TestAllocatorJets and
    TestFullGNC6DOF;
  - every jet output and the 6-DOF plant's force/torque inputs, which are summed
    in equations.
- **Single-instance tests** (`TestSatelliteOpenLoop`, `TestOrbitPropagation`,
  `TestSingleJet`) were out of scope. They pick up the new child icons and port
  boxes but were not re-laid out.
