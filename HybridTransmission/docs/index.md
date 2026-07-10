```@cardmeta
Title = "Hybrid Transmission — ECMS power-split powertrain"
Description = "A power-split hybrid EV whose ECMS controller optimally splits torque between engine and two motor/generators over the HWFET cycle."
Tags = ["automotive", "powertrain", "control", "optimization"]
Cover = "assets/icon.svg"
```

# Hybrid Transmission Demo

A power-split hybrid electric vehicle that uses an Equivalent Consumption
Minimization Strategy (ECMS) controller to optimally split torque demand between
an Atkinson-cycle internal-combustion engine and two permanent-magnet
motor/generators. The controller minimizes an equivalent cost `J = fuel_rate + s * P_battery`,
where the equivalence factor `s` is dynamically adjusted from battery
state-of-charge feedback, trading fuel burn against battery drain in real time.
The engine, MG1, and MG2 are coupled through an ideal planetary gear set, and the
1750 kg vehicle follows the EPA Highway Fuel Economy Test (HWFET) drive cycle.

!!! note
    This is a heavy demo. The model diagram below renders from a snapshot, but the
    simulations are not executed in the documentation build. Run them from the
    `HybridTransmission` project.

## The model

`PowerSplitHybrid` is the complete closed-loop vehicle: the HWFET drive cycle
source, ECMS controller, engine, the MG1/MG2 motor/generators, planetary
transmission, battery, and lumped vehicle body wired together:

```@dyadviewer
entity = "HybridTransmission.PowerSplitHybrid"
default = "diagram"
height = "480px"
```
