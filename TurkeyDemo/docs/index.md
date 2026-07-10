```@cardmeta
Title = "Turkey — discretized sphere cooking"
Description = "Radial heat conduction in a turkey modeled as concentric spherical shells."
Tags = ["thermal", "discretization", "cooking"]
Cover = "assets/icon.svg"
```

# Turkey Demo

A discretized thermal model of cooking a turkey approximated as a sphere divided
into concentric shells. Heat reaches the surface from the oven by both convection
and radiation, then conducts inward shell by shell, so you can track when the
center reaches a safe internal temperature.

## The model

`TurkeySphereTest` places the discretized turkey in an oven environment with
convective and radiative heat transfer:

```@dyadviewer
entity = "TurkeyDemo.TurkeySphereTest"
default = "diagram"
height = "480px"
```

## Running it

Simulate four hours of cooking and plot the surface temperature in °F:

```@example turkey
using TurkeyDemo, ModelingToolkit, DyadInterface, Plots

@named model = TurkeySphereTest()
res = TransientAnalysis(; model, stop = 14400)
plot(res, idxs = [TurkeyDemo.KelvinToFahrenheit(model.turkey.surface.T)])
```
