# Diagram re-layout notes

Before/after renders and per-demo notes for the Dyad 3.5 autolayout pass.

Toolchain: Dyad CLI 3.5.0 (`dyad layout extract/solve/apply`, `dyad render`), layered solver `dyad-layout` 0.1.1.

Bugs in 3.5.0 `layout apply` that the notes work around:

1. Arms of multi-way `connect` statements can be attached to the wrong ends. `fix_junction_order.py` repairs this.
2. `apply` sometimes writes no edges at all. `verify_edges.py` catches it; re-run `apply`.

`apply` also rewrites the whole file, so comments and formatting can be lost. Check the diff and restore them.

Rendering quirks (not `apply` bugs): a solver `flipH` can render as a vertical flip (`y1 > y2`), so labels appear upside down; the layouts use `rot` instead of flips. A branching connection written as a single edge can render without a junction dot, so a branch reads like a crossing; the layouts rewrite it into Dyad's port, junction, port form.

| Demo | Notes |
|---|---|
| CLibraryIntegration | [LAYOUT_NOTES.md](CLibraryIntegration/LAYOUT_NOTES.md) |
| CoffeeMugDemo | [LAYOUT_NOTES.md](CoffeeMugDemo/LAYOUT_NOTES.md) |
| DrivelineSciML | [LAYOUT_NOTES.md](DrivelineSciML/LAYOUT_NOTES.md) |
| DynamicSteadyState | [LAYOUT_NOTES.md](DynamicSteadyState/LAYOUT_NOTES.md) |
| FIRFilterComponents | [LAYOUT_NOTES.md](FIRFilterComponents/LAYOUT_NOTES.md) |
| FrictionBrakeDemo | [LAYOUT_NOTES.md](FrictionBrakeDemo/LAYOUT_NOTES.md) |
| HybridTransmission | [LAYOUT_NOTES.md](HybridTransmission/LAYOUT_NOTES.md) |
| MakieWebinar | [LAYOUT_NOTES.md](MakieWebinar/LAYOUT_NOTES.md) |
| MotorTemperatureSciML | [LAYOUT_NOTES.md](MotorTemperatureSciML/LAYOUT_NOTES.md) |
| PassiveSuspension | [LAYOUT_NOTES.md](PassiveSuspension/LAYOUT_NOTES.md) |
| QuarterTruckSciML | [LAYOUT_NOTES.md](QuarterTruckSciML/LAYOUT_NOTES.md) |
| SatelliteGNC | [LAYOUT_NOTES.md](SatelliteGNC/LAYOUT_NOTES.md) |
| ThermalHouseDemo | [LAYOUT_NOTES.md](ThermalHouseDemo/LAYOUT_NOTES.md) |
| TurkeyDemo | [LAYOUT_NOTES.md](TurkeyDemo/LAYOUT_NOTES.md) |
