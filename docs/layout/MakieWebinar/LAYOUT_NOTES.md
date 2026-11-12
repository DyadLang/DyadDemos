# MakieWebinar layout notes

Laid out with the Dyad 3.5.0 CLI (`dyad layout extract/solve/apply`) and the
`relayout.sh` / `edit_problem.py` helper scripts (from the layout-tools bundle, not committed here).
Every diagram below uses the base ops `lock-orientation unpin-ports port-edges`
plus `pin` constraints. Pins are component **centres** in half-squares (1 half-square = 50 diagram units).

```sh
pin() { echo "add:{\"id\":\"pin:$1\",\"kind\":{\"kind\":\"pin\",\"componentId\":\"$1\",\"at\":{\"x\":$2,\"y\":$3}},\"strength\":{\"tier\":\"required\",\"weight\":1}}"; }
cd MakieWebinar
relayout.sh COMP OUTDIR lock-orientation unpin-ports port-edges $(pin a X Y) ...
```

| Diagram | Before | What was done | After |
|---|---|---|---|
| TestDiffusion5x5, TestDiffusion30x30, TestReactionDiffusion5x5, TestFitzHughNagumo5x5, TestReactionGrowth5x5, TestReactionGrowth20x20, TestFHNWave5x5, TestFHNWave20x20 | F: all 4 arrays stacked on top of each other | No `connect()` the solver can see (all in `for` loops), so the solver can't place them. Pinned one identical row in all 8 harnesses | A: tidy row of 4, the same in all 8 |
| TunableRCCircuit | F: unplaced, everything stacked | Pinned loop: signal above source, R and C on the bottom row, ground at the end | A: 0 crossings |
| TunableRLCResonance | F: unplaced | Same layout as the RC circuit, with the capacitor in the source's position | A: 0 crossings |
| ControlledOscillator | C+: diagonal ff_input wire, pid→force wire ended in mid-air, sideways `control_force` label | Pinned: controller column on the left, force at right, spring–mass row below, sensor feedback underneath. All blocks upright | A-: 0 crossings, no diagonals |
| SpringMassSystem | B-: `f` input wire was not attached to `f` or to `force_source.f` | Pinned (same mechanical arrangement as ControlledOscillator); gave `f` an explicit `placement.icon` (left middle) so its port on parent icons stays put | A |
| TestSpringMassSystem | B: wire entered `system` at a port drawn inside the box | Default ops only, after the `f` icon fix | A: one straight wire |

## Exact hints

PDE harnesses (in `reaction_diffusion.dyad` the arrays are named `r_h r_v bounds` instead of `r_horiz r_vert boundaries`).
There are no connections, so this ran extract → edit_problem → solve → apply directly, without `relayout.sh`:
```
lock-orientation $(pin caps 2 2) $(pin r_horiz 5 2) $(pin r_vert 8 2) $(pin boundaries 11 2)
```
TunableRCCircuit:
```
$(pin voltage_signal 4 2) $(pin source 8 4) $(pin resistor 10 8) $(pin capacitor 14 8) $(pin ground 18 10)
```
TunableRLCResonance:
```
$(pin capacitor 8 4) $(pin resistor 10 8) $(pin inductor 14 8) $(pin ground 18 10)
```
ControlledOscillator (`setpoint` y=4.54 lines its output up with `pid.u_s`, which sits at ±0.46 on the pid's left edge):
```
$(pin ff_input 3 1) $(pin setpoint 3 4.54) $(pin pid 7 5) $(pin control_force 13 7) $(pin ground 11 9)
$(pin mass 13 11) $(pin spring 9 11) $(pin fixed 7 13) $(pin velocity_sensor 13 14)
```
SpringMassSystem:
```
$(pin f 0 1) $(pin force_source 9 3) $(pin ground 7 5) $(pin mass 9 7) $(pin spring 5 7) $(pin fixed 3 9)
```
then by hand: `f` gets `"icon": {"x1": -50, "y1": 450, "x2": 50, "y2": 550}` next to its diagram placement.

TestSpringMassSystem: base ops only.

## Known render quirks (not layout defects)
- `dyad render` draws boundary RealInput/RealOutput triangles at about 21% scale in the top-left corner
  of their box, because the connector SVG has `width="210"`. That is why the `f` triangle in
  SpringMassSystem looks detached from its wire. Studio draws it in the right place.
- T-joints made by two separate 2-way `connect()`s, such as spring–mass–sensor, get no junction dot.
- The solver's `flipH` is written by `apply` as a vertical flip (y1>y2), so the label ends up
  upside down. Don't use flips.
