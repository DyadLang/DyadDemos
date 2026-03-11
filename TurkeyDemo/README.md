# TurkeyDemo

<img src="./assets/icon.svg" width="96" align="right"/>

A discretized thermal model of cooking a turkey, built with [Dyad](https://help.juliahub.com/dyad/dev/). The turkey is approximated as a sphere divided into concentric shells, and heat transfer from the oven to the turkey surface occurs via both convection and radiation. The simulation tracks temperature over time at every radial shell, letting you predict when the center reaches a safe internal temperature (165 F).

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad extension](https://help.juliahub.com/dyad/dev/getting_started/).

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

## Models

The Dyad models are defined in `dyad/TurkeyDiscretizedSphere.dyad` and consist of three parts:

- **`TurkeyDiscretizedSphere`** -- The core thermal component. Models the turkey as a sphere discretized into `N` concentric shells. Each shell has mass, volume, and surface area computed from the geometry. Heat conduction between shells follows Fourier's law, and energy balance ODEs govern the temperature evolution in each shell. A thermal connector at the outer surface allows coupling to external heat sources. Configurable parameters include mass (`M`), density (`rho`), specific heat capacity (`cp`), thermal conductivity (`k`), and initial temperature (`T_init`).

- **`TurkeySphereTest`** -- A test harness that wires together the full cooking system. It connects a `TurkeyDiscretizedSphere` to a fixed-temperature oven via both convection (using `ThermalComponents.Convection` with a signal-driven conductance) and radiation (using `ThermalComponents.BodyRadiation`). Parameters include oven temperature (`T_oven`), convective heat transfer coefficient (`h`), surface emissivity (`epsilon`), and turkey mass (`M_turkey`).

- **`TurkeySphereCooking`** -- A transient analysis specification that runs `TurkeySphereTest` for 14,400 seconds (4 hours) with results saved every 60 seconds.
