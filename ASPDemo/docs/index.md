```@cardmeta
Title = "Activated Sludge Process — BSM1 wastewater plant"
Description = "A BSM1 activated-sludge wastewater treatment plant balancing effluent quality against aeration energy."
Tags = ["process", "wastewater", "control", "components"]
Cover = "assets/icon.svg"
```

# Activated Sludge Process Demo

An Activated Sludge Process (ASP) wastewater treatment plant implementing the
IWA/COST Benchmark Simulation Model No. 1 (BSM1). A five-tank biological reactor
train — two anoxic denitrification tanks feeding three aerated nitrification tanks —
discharges into a ten-layer Takács secondary clarifier with return-sludge, waste-sludge,
and internal-recycle loops. All ~40 components (ASM1 reactor kinetics, sedimentation
layers, hydraulic elements, sensors, and control blocks) are built from scratch in Dyad.
The engineering tradeoff of interest is effluent cleanliness — the chemical oxygen demand
at `sensor_effluent` — against the aeration energy spent by the three blowers.

!!! note
    This is a heavy demo. The model diagram below renders from a snapshot, but the
    simulations are not executed in the documentation build. Run them from the
    `ASPDemo` project.

## The model

`BenchPlant` is the assembled BSM1 plant: the CSV-driven influent source, the
denitrification and nitrification reactor train, the Takács clarifier, the recycle
and sludge pumps, the aeration blowers, and the PI controllers regulating dissolved
oxygen and nitrate.

```@dyadviewer
entity = "ASPDemo.BenchPlant"
default = "diagram"
height = "480px"
```
