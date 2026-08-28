```@cardmeta
Title = "Dynamic Steady State — three-zone building"
Description = "One building model reused for steady-state HVAC sizing and 24-hour transient operation."
Tags = ["thermal", "buildings", "steady-state"]
Cover = "assets/icon_three_zone_building.svg"
Order = 3
```

# Dynamic Steady State Demo

A thermal-envelope model of a three-zone commercial office building. One building
model is the single source of truth for two analyses: steady-state HVAC equipment
sizing and a 24-hour transient diurnal simulation with occupancy gains and
thermostat control. The south, core, and north zones are linked by inter-zone
partition resistors.

## The model

`ThreeZoneBuilding` connects three zone-room subsystems through inter-zone
partitions and exposes a port per zone:

```@dyadviewer
entity = "DynamicSteadyState.ThreeZoneBuilding"
default = "diagram"
height = "480px"
```

## Running it

Run the 24-hour diurnal operation and plot the zone temperatures:

```@example dynamicsteadystate
using DynamicSteadyState, Plots

result = DiurnalOperation()
plot(result)
```
