# PassiveSuspension layout notes

Dyad 3.5.0 CLI with `relayout.sh COMP OUTDIR lock-orientation unpin-ports port-edges <pins>`.
`pin NAME X Y` = a required `pin` constraint, centre in half-squares (50 units); the helper is
defined in `../MakieWebinar/LAYOUT_NOTES.md`. Multi-way junctions are pseudo-components
`__junction_N` in the problem file and can be pinned like any block.

| Diagram | Before | What was done | After |
|---|---|---|---|
| MyActiveSuspension | D: pid upside down (rot 180), MassSpringDampers and force at rot 90/270 (sideways labels), pid wires ending in mid-air | All blocks upright. Same car+wheel row and road row as the passive model, with force‖seat in a row above (seat and force are anti-parallel, so the only planar drawing is side by side). Controller above, pid output wraps over the top into `force.f`. Pinned both junctions | A: 0 crossings, junction dots on the routes |
| MyPassiveSuspension | B+: fine, but long loop over the top and a jog in the road wire | Re-laid on the same grid as the active model so the two read alike | A: 0 crossings, straight road wire |

Unpinned default solve of MyActiveSuspension (for comparison): 1 crossing, an undotted T, and the
mechanical stack upside down (road on top).

## Exact hints

MyActiveSuspension:
```
$(pin set_point 8 3) $(pin seat_pos 8 6.46) $(pin pid 12 6) $(pin force 4 9) $(pin seat 8 9)
$(pin car_and_suspension 4 13) $(pin wheel 8 13) $(pin road 8 16) $(pin road_data 4 16)
$(pin __junction_14 2 11) $(pin __junction_15 6 9)
```
(`__junction_14` = `connect(car_and_suspension.flange_m, seat.flange_sd, force.flange_a)`,
`__junction_15` = `connect(seat.flange_m, force.flange_b, seat_pos.flange)`; `seat_pos` y=6.46 lines
up with `pid.u_m`.) Without the junction pins the solver put one junction off its routes.

MyPassiveSuspension:
```
$(pin seat 8 9) $(pin car_and_suspension 4 13) $(pin wheel 8 13) $(pin road 8 16) $(pin road_profile 4 16)
```
