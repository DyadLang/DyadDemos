# HybridTransmission layout notes

Only `PowerSplitHybrid` has ≥2 subcomponents. The other components are leaves; only their
connector icon placements were touched (bottom-up fix, below).

| Diagram | Before | What was done | After |
|---|---|---|---|
| PowerSplitHybrid | C: most wires ended next to, not on, the ports painted in the icon art (the connectors had no `icon` placement and fell back to diagram positions that disagreed with the art, e.g. engine throttle declared on the right, painted on the left); stray stubs; several crossings | 1) Child icon ports fixed to match the art. 2) Controller instance enlarged to 300×300 so its 5 inputs are 50 units apart. 3) Pinned column layout + solver routing. 4) Two small route tweaks in the solution JSON | B+: 2 crossings (both unavoidable, see below), every wire ends on a drawn port, all upright |

Default solve on the new child ports: `routingRefinement=1` → 15 crossings, `=2` → 17 crossings.
That's worse than the pinned layout.

## 1. Child icon ports (`set_icon.py FILE CONN=CX,CY ...`, 0..1000 icon frame)
```
set_icon.py dyad/hybrid_engine.dyad throttle=0,500 flange=1000,500 omega_output=1000,250
set_icon.py dyad/hybrid_mg.dyad torque_cmd=0,500 flange=1000,500 omega_output=1000,250 power_elec=1000,750
set_icon.py dyad/hybrid_vehicle.dyad flange=0,500 speed_output=1000,500
set_icon.py dyad/hybrid_battery.dyad mg1_power=0,250 mg2_power=0,750 soc_output=1000,500
set_icon.py dyad/highway_drive_cycle.dyad speed_ref=1000,500
set_icon.py dyad/ecms_controller.dyad mg1_omega=0,166.6667 engine_omega=0,333.3333 speed_ref=0,500 \
  speed_actual=0,666.6667 soc=0,833.3333 engine_throttle=1000,333.3333 mg1_torque_cmd=1000,500 mg2_torque_cmd=1000,666.6667
```
Painted ports matched: engine T/flange, motor τ/flange, vehicle flange, controller E/M1/M2.
Unpainted outputs use 50-unit multiples at the 200-unit instance size. The controller's input
order is chosen so the feedback loops nest: wires from above (mg1, engine omegas) take the top
ports, `speed_ref` is in the middle straight from the drive cycle, and the wires from below
(vehicle speed, SOC) take the bottom ports. The painted `P`/`S` circles on the controller art are decoration only.

The planetary `carrier` port is inherited from `RotationalComponents.IdealPlanetaryGear` (left edge, −0.42).
Overriding it in `HybridPlanetaryGear`'s `_links` had no effect, so it stays at the top-left
rather than at the painted top port.

## 2. Instance size
`controller` diagram box: `x1 300, y1 450, x2 600, y2 750` (300×300), set before extract.

## 3. Ops (pins = centres in half-squares)
```
lock-orientation unpin-ports port-edges opt:routingRefinement=2 grid:20x14
$(pin drive_cycle 2 10) $(pin controller 10 10) $(pin engine 18 3) $(pin mg1 18 10) $(pin mg2 18 17)
$(pin transmission 25 10) $(pin vehicle 31 10) $(pin battery 24 17)
```
extract → edit_problem → solve (2 crossings) → `patch_psh.py sol0.json sol.json` → apply → verify_edges.

## 4. `patch_psh.py`
Removes a 0.25-square jog on the engine-omega entry and moves the two bottom feedback runs
(vehicle speed, SOC) one half-square lower so they clear the `mg2`/`battery` labels. The solver
doesn't know where labels are.

## Remaining crossings (topological)
- `mg1.omega_output → controller` must cross `controller.engine_throttle → engine`: mg1 sits between the controller's E and M2 fan-out.
- `mg1.power_elec → battery` must cross `mg2.flange → transmission.ring`: mg2's flange and power ports are both on its right side, and they head to opposite sides of the battery.

The controller label is larger than the others because label size scales with the instance box.
