```@cardmeta
Title = "Thermal House — building heating dynamics"
Description = "Heat transfer through a building envelope with HVAC and weather-driven control."
Tags = ["thermal", "components", "buildings"]
Cover = "assets/icon.svg"
Order = 2
```

# Thermal House Demo

A Dyad thermal model of a residential house, for studying how indoor temperature
responds to the weather outside and the heating strategy inside.

The house loses heat through its envelope — walls, roof, floor, windows, and
doors — and through air leaking in and out. It gains heat from the sun, from
whatever is running indoors, and from the HVAC.

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
