# FIRFilterComponents layout notes

## Environment workaround (not committed)
`DiscreteComponents = "0.6.0"` does not resolve against the available registry. To render and lay out,
a scratch copy of the project was made outside the repo with the compat relaxed to `"0.5"`. Only
`dyad/firfilter.dyad` was copied back. `Project.toml` is unchanged. Compiling in the scratch copy
produced a `generated/` byte-identical to the committed one.

| Diagram | Before | What was done | After |
|---|---|---|---|
| FIRFilter | B: clean, but gain1–3 were at rot 90, so their names and `k=` values were sideways | All gains upright. Delay line on top, each gain directly under its tap, adder chain on the bottom row. Pinned placement, routes written by hand | A: 0 crossings, no diagonals, junction dots on the taps |
| TestFIRFilter | A-: clean | Unchanged. Before re-laying FIRFilter, its `realinput`/`realoutput` got explicit `placement.icon` boxes at their previous positions (left/right middle), so the FIRFilter icon in TestFIRFilter doesn't move | A- (render identical) |

## Exact steps for FIRFilter
1. `realinput` icon `{"x1": -50, "y1": 450, "x2": 50, "y2": 550}`, `realoutput` icon `{"x1": 950, "y1": 450, "x2": 1050, "y2": 550}`.
2. extract, then `edit_problem.py` with
```
lock-orientation unpin-ports port-edges grid:14x9
$(pin realinput 0 3) $(pin realoutput 25 13)
$(pin unitdelay 4 3) $(pin unitdelay1 8 3) $(pin unitdelay2 12 3) $(pin unitdelay3 16 3)
$(pin __junction_1 6 3) $(pin __junction_3 14 3)
$(pin gain 3 8) $(pin gain1 7 8) $(pin gain2 15 8) $(pin gain3 19 8)
$(pin add 10 13) $(pin add1 18 13) $(pin add3 22 13)
```
3. solve → `fir_routes.py sol0.json hand0.json` → `fix_junction_order.py` → apply → verify_edges.

Why hand routes: the router always leads out one half-square from each port. With blocks this
close together that produced S-bends, and in one case two different nets touching at a point
(gain.y and the gain1 tap at (5,8); gain2.y and the gain3 tap at (18,8)). `fir_routes.py` keeps
the solved placements, replaces every route with a plain orthogonal one, and moves the two tap
junctions half a square left. That way the last segment into `gain1.u`/`gain2.u` is horizontal:
the Gain's rendered port sits a few units left of the box edge, so a vertical final segment
showed up as a slight diagonal.
