# DrivelineSciML diagram re-layout (Dyad 3.5 autolayout)

Toolchain: Dyad CLI 3.5.0 (`483d92b`), `JULIA_EXECUTABLE="julia +dyad-3.5.0"`, plus the
layout scripts (`relayout.sh`, `edit_problem.py`, `fix_junction_order.py`,
`verify_edges.py`, `svg2png.sh`). After `dyad compile .`, run
`scripts/fix_analysis_codegen.jl` as usual; `generated/` is then unchanged by the layout.

Only the changed component blocks were spliced back from `dyad layout apply`'s
whole-file re-print. `MaxwellBoucWenIsolator` (no sub-components) and `TestTipInTorque`
(one) have no diagram to lay out.

## Prerequisite fix (separate commit)

The four harnesses connected to `model.torque.tau`. The Dyad 3.5 diagram tooling
rejects that ("Connector reference model.torque.tau isn't supported"), so they could not
be rendered or extracted. `DrivelineSystem` now has a `tau = RealInput()` (icon port at
the left, on the shaft line), wired as `connect(tau, torque.tau)`, and the harnesses
connect to `model.tau`. All 27 `Pkg.test()` assertions pass. The harness "before" images
below were therefore rendered after this fix but before any layout, with every block
at its default position.

`TipInTorque.y` had no icon placement, so the tooling used a default position. It now
sits at the right-centre of the icon (`x1 950, y1 450, x2 1050, y2 550`), which was done
before laying out `TestDrivelineTipIn`.

## Summary

| Diagram | Before | What was done | After |
|---|---|---|---|
| DrivelineSystem | F: no placements, 7 blocks stacked, labels on top of each other | solver + `collapsePendants`, grounds tightened by hand | one left→right chain, both supports hang straight down, 0 crossings |
| TestDrivelineChirp | F: failed to render (`model.torque.tau`). After the fix, defaults stacked | solver, then compacted by hand | sources → adder → model, 0 crossings |
| TestDrivelineChirpMaxwellOnly | same as above | same spec as TestDrivelineChirp | same |
| TestDrivelineSlowCycle | F: failed to render. After the fix, defaults stacked | solver, default ops | sine → model, one straight wire |
| TestDrivelineTipIn | F: failed to render. After the fix, defaults stacked | `TipInTorque.y` icon port added, then solver default ops | tipin → model, one straight wire |

## Recipes (run from `DrivelineSciML/`)

Hand-spec coordinates are in half-squares. A block at `[cx, cy]` is the 100×100 box
centred on `(50·cx, 50·cy)`. A route is the connect's interior waypoints `M`, times 50.

### DrivelineSystem

```sh
relayout.sh DrivelineSystem OUT lock-orientation unpin-ports port-edges opt:collapsePendants=true
```

Without `collapsePendants`, `ground` sits right of the damper and its wire loops over the
top. With it, both supports sit 150 units below the chain. Hand edits:

```json
{"place": {"torque_support": [7, 8], "ground": [29, 8]},
 "route": {"torque.support, torque_support.spline": [],
           "load_damper.spline_b, ground.spline": [[29, 5]]}}
```

`ground` is one column right of the damper, so its wire is a clean L. Directly under
the damper, the wire doubled back through the damper's label.

### TestDrivelineChirp and TestDrivelineChirpMaxwellOnly

```sh
relayout.sh TestDrivelineChirp OUT lock-orientation unpin-ports port-edges
relayout.sh TestDrivelineChirpMaxwellOnly OUT lock-orientation unpin-ports port-edges
```

The solver left `mean_torque` 250 units below `chirp`. Both harnesses were then
compacted with the same hand spec. The adder sits between the two sources and in line
with the model; the gap keeps the `chirp` label (below its box) clear of the
`mean_torque` label (above its box).

```json
{"place": {"chirp": [5, 4], "mean_torque": [5, 8], "torque_sum": [10, 6], "model": [15, 6]},
 "route": {"chirp.y, torque_sum.u1": [[7.5, 4], [7.5, 5.4]],
           "mean_torque.y, torque_sum.u2": [[7.5, 8], [7.5, 6.6]],
           "torque_sum.y, model.tau": []}}
```

### TestDrivelineSlowCycle and TestDrivelineTipIn

```sh
relayout.sh TestDrivelineSlowCycle OUT lock-orientation unpin-ports port-edges
relayout.sh TestDrivelineTipIn OUT lock-orientation unpin-ports port-edges
```

Used as solved: two blocks and one straight wire each.

## Renderer note

The boundary `RealInput` triangle in `DrivelineSystem` renders about 50 units up and to
the left of its wire end. The cause is the connector icon, a nested
`<svg width="210" height="210">`, not the layout.
