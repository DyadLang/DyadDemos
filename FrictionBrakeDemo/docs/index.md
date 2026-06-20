```@cardmeta
Title = "Friction Brake — thermal braking dynamics"
Description = "Vehicle friction brake converting braking energy to disk and pad heat over a drive cycle."
Tags = ["thermal", "automotive", "components"]
Cover = "assets/icon.svg"
```

# Friction Brake Demo

An acausal, equation-based model of a vehicle friction brake with coupled thermal
effects. It shows how braking energy is converted to heat and how disk and pad
temperatures evolve under a realistic driving cycle.

## The model

`VehicleCycleTest` connects the driver, powertrain, friction brake, vehicle, and
brake-thermal subsystems into a closed-loop drive cycle:

```@dyadviewer
entity = "FrictionBrakeDemo.VehicleCycleTest"
default = "diagram"
height = "480px"
```

## Running it

Simulate the drive cycle and plot the reference and actual vehicle speed:

```@example frictionbrake
using FrictionBrakeDemo, ModelingToolkit, DyadInterface, Plots

@named model = VehicleCycleTest()
res = TransientAnalysis(; model, stop = 2000)
plot(res, idxs = [model.vehicle_speed_ref.y, model.vehicle.vehicle_speed])
```
