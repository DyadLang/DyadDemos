```@cardmeta
Title = "Coffee Mug — modular thermal cooling"
Description = "Espresso cooling across coffee, mug, hand, steam, and an optional spoon."
Tags = ["thermal", "components", "beginner"]
Cover = "assets/icon.svg"
```

# Coffee Mug Demo

A thermal model of an espresso cooling in a porcelain mug, built with Dyad. It
captures convection, conduction, and radiation across interacting subsystems —
the coffee, the mug, a hand, the rising steam, and an optional metal spoon.

## The model

`EspressoCupSystemModular` connects the coffee-mug, steam, and hand subsystems
to a fixed-temperature ambient environment:

```@dyadviewer
entity = "CoffeeMugDemo.EspressoCupSystemModular"
default = "diagram"
height = "480px"
```

## Running it

Simulate the espresso cooling over 6000 s and plot the espresso temperature:

```@example coffee
using CoffeeMugDemo, ModelingToolkit, DyadInterface, Plots

@named model = EspressoCupSystemModular()
res = TransientAnalysis(; model, alg = ODEAlg.Auto(),
                        abstol = 10e-3, reltol = 1e-3, start = 0.0, stop = 6000)
plot(res, idxs = [model.coffeeMug.espressoTemp_degC])
```
