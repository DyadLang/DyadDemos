# TurkeyDemo

A discretized thermal model of cooking a turkey, built with [Dyad](https://help.juliahub.com/dyad/dev/). The turkey is approximated as a sphere divided into concentric shells, and heat transfer from the oven to the turkey surface occurs via both convection and radiation. The simulation tracks temperature over time at every radial shell, letting you predict when the center reaches a safe internal temperature (165 F).

## Models

The Dyad models are defined in `dyad/TurkeyDiscretizedSphere.dyad` and consist of three parts:

- **`TurkeyDiscretizedSphere`** -- The core thermal component. Models the turkey as a sphere discretized into `N` concentric shells. Each shell has mass, volume, and surface area computed from the geometry. Heat conduction between shells follows Fourier's law, and energy balance ODEs govern the temperature evolution in each shell. A thermal connector at the outer surface allows coupling to external heat sources. Configurable parameters include mass (`M`), density (`rho`), specific heat capacity (`cp`), thermal conductivity (`k`), and initial temperature (`T_init`).

- **`TurkeySphereTest`** -- A test harness that wires together the full cooking system. It connects a `TurkeyDiscretizedSphere` to a fixed-temperature oven via both convection (using `ThermalComponents.Convection` with a signal-driven conductance) and radiation (using `ThermalComponents.BodyRadiation`). Parameters include oven temperature (`T_oven`), convective heat transfer coefficient (`h`), surface emissivity (`epsilon`), and turkey mass (`M_turkey`).

- **`TurkeySphereCooking`** -- A transient analysis specification that runs `TurkeySphereTest` for 14,400 seconds (4 hours) with results saved every 60 seconds.

## Getting Started

This library was created with the Dyad Studio VS Code extension. Your Dyad models should be placed in the `dyad` directory and the files should be given the `.dyad` extension. The Dyad compiler will compile the Dyad models into Julia code and place it in the `generated` folder. Do not edit the files in that directory or remove/rename that directory.

A complete tutorial on using Dyad Studio can be found [here](https://help.juliahub.com/dyad/dev/). But you can run the provided example models by doing the following:

1. Run `Julia: Start REPL` from the command palette.

2. Type `]`. This will take you to the package manager prompt.

3. At the `pkg>` prompt, type `instantiate` (this downloads all the Julia libraries you will need, and the very first time you do it it might take a while).

4. From the same `pkg>` prompt, type `test`. This will test to make sure the models are working as expected.

5. Use the `Backspace`/`Delete` key to return to the normal Julia REPL, it should look like this: `julia>`.

6. Type `using TurkeyDemo`. This will load your model library.

7. Type `TurkeySphereCooking()` to run a 4-hour transient simulation of the turkey cooking model. The first time you run it, this might take a few seconds, but each successive time you run it, it should be very fast.

8. To see simulation results type `using Plots` (and answer `y` if asked if you want to add it as a dependency).

9. To plot results of the `TurkeySphereCooking` simulation, simply type `plot(TurkeySphereCooking())`.

10. You can plot variations on that simulation using keyword arguments. For example, try `plot(TurkeySphereCooking(stop=18000))` for a 5-hour cook.

## Running Experiments

Two scripts are provided in the `scripts/` directory:

### Quick Simulation (`scripts/simulate_turkey_test.jl`)

Runs the `TurkeySphereTest` model for 4 hours and plots the results using `Plots.jl`. This is useful for a quick, non-interactive look at the temperature profiles (oven, surface, and center temperatures in degrees Fahrenheit).

```julia
include("scripts/simulate_turkey_test.jl")
```

### Interactive Dashboard (`scripts/dashboard.jl`)

<img src="./assets/dashboard.png" width="500"/>

Launches a GLMakie interactive dashboard that visualizes temperature over time with adjustable parameters. The dashboard plots the center and edge temperatures of the turkey in degrees Fahrenheit, marks the oven temperature, and highlights the point where the center reaches the safe internal temperature of 165 F.

To launch the dashboard:

1. Install [Dyad](https://help.juliahub.com/dyad/dev/installation.html) if you haven't already.

2. Open this folder in a new VS Code window.
3. Run `Julia: Start REPL` from the VS Code command palette.

4. In the Julia REPL, paste the following code and press `Enter`:
   ```julia
   include("scripts/dashboard.jl")
   ```

This opens a GLMakie window showing temperature over time, with textboxes to adjust oven temperature, turkey mass, density, and radius. The simulation re-runs automatically when you change any parameter (this may take a few seconds).
