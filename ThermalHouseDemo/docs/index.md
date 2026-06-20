```@cardmeta
Title = "Thermal House — building heating dynamics"
Description = "Heat transfer through a building envelope with HVAC and weather-driven control."
Tags = ["thermal", "components", "buildings"]
Cover = "assets/icon.svg"
```

# Thermal House Demo

A Dyad thermal model of a residential house. It captures heat transfer through
the building envelope — walls, roof, floor, windows, and doors — together with
air infiltration, solar and internal gains, and HVAC heating, so you can study
how indoor temperature responds to weather and control strategy.

## The model

`ThermalHouse` assembles the envelope losses, infiltration, thermal mass, and
heat sources around a single interior air node:

```@dyadviewer
entity = "ThermalHouseDemo.ThermalHouse"
default = "diagram"
height = "480px"
```

## Running it

Run the open-loop winter design analysis and plot the result:

```@example thermalhouse
using ThermalHouseDemo, Plots

sol = TestHouseWinterDesign()
plot(sol)
```
