# TurkeyDemo

<img src="./assets/icon.svg" width="96" align="right"/>

Roasting a turkey comes down to two questions: how long will a bird this size
take, and is the middle safe to eat (165 F) before the outside dries out?

Heat enters at the skin and takes hours to reach the center, so the two ends of
the bird are never at the same temperature. This demo simulates that journey,
using [Dyad](https://help.juliahub.com/dyad/dev/).

## The approach

The turkey is treated as a sphere sliced into concentric shells, like the layers
of an onion. Each shell stores heat and passes it inward to the next, so the
model can show the outside browning while the middle is still cold.

The oven reaches the outermost shell two ways: hot air moving over the skin
(convection) and the oven walls glowing at the bird (radiation). From there,
heat travels inward shell by shell.

The interactive dashboard plots the center and edge temperatures of the turkey
in degrees Fahrenheit, marks the oven temperature, and highlights the point
where the center reaches the safe internal temperature of 165 F. Change the oven
setting or the size of the bird and the curves redraw.

<img src="./assets/dashboard.png" width="500"/>

## Models

The Dyad models are defined in `dyad/TurkeyDiscretizedSphere.dyad`:

| Model | What it is |
| --- | --- |
| `TurkeyDiscretizedSphere` | The bird itself, as `N` concentric shells. Each shell gets its mass, volume and surface area from the geometry; Fourier's law moves heat between neighbours, and an energy balance sets how fast each shell warms. A thermal connector on the outer shell is where the oven attaches. |
| `TurkeySphereTest` | The bird in an oven: a `TurkeyDiscretizedSphere` wired to a fixed-temperature source through `ThermalComponents.Convection` (with a signal-driven conductance) and `ThermalComponents.BodyRadiation`. |
| `TurkeySphereCooking` | A transient analysis specification that runs `TurkeySphereTest` for 14,400 seconds (4 hours) with results saved every 60 seconds. |

Parameters you can change:

| Model | Parameters |
| --- | --- |
| `TurkeyDiscretizedSphere` | mass `M`, density `rho`, specific heat capacity `cp`, thermal conductivity `k`, initial temperature `T_init` |
| `TurkeySphereTest` | oven temperature `T_oven`, convective heat transfer coefficient `h`, surface emissivity `epsilon`, turkey mass `M_turkey` |

## Notes

### Getting started

Install [Dyad](https://help.juliahub.com/dyad/dev/installation.html) if you
haven't already. Then download this folder to your machine and open it in VS
Code with the [Dyad
extension](https://help.juliahub.com/dyad/dev/getting_started/).

### Running the dashboard (`scripts/dashboard.jl`)

1. Open this folder in a new VS Code window.
2. Run `Julia: Start REPL` from the VS Code command palette.
3. In the Julia REPL, paste the following code and press `Enter`:
   ```julia
   include("scripts/dashboard.jl")
   ```

This opens a GLMakie window showing temperature over time, with textboxes to
adjust oven temperature, turkey mass, density, and radius. The simulation
re-runs automatically when you change any parameter (this may take a few
seconds).

### Quick simulation (`scripts/simulate_turkey_test.jl`)

Runs the `TurkeySphereTest` model for 4 hours and plots the results using
`Plots.jl`. This is useful for a quick, non-interactive look at the temperature
profiles (oven, surface, and center temperatures in degrees Fahrenheit).

```julia
include("scripts/simulate_turkey_test.jl")
```
