# Diagram re-layout notes

Before/after renders and per-demo notes for the Dyad 3.5 autolayout pass.

Toolchain: Dyad CLI 3.5.0 (`dyad layout extract/solve/apply`, `dyad render`), layered solver `dyad-layout` 0.1.1.

Bugs in 3.5.0 `layout apply` that the notes work around:

1. A solver `flipH` is written as a vertical flip (`y1 > y2`), so labels render upside down. The layouts use `rot` instead of flips.
2. A branching connection is written as a single edge with no junction dot, so a branch reads like a crossing. The layouts rewrite it into Dyad's port, junction, port form.

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
