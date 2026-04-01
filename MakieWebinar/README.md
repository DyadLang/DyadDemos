# MakieWebinar

<img src="./assets/icon.svg" width="96" align="right"/>

This library demonstrates how to use [Makie](https://docs.makie.org/), the interactive plotting library for Julia, together with [Dyad](https://help.juliahub.com/dyad) acausal models to build interactive plots and dashboards. It accompanies a webinar presented in January 2026 and covers everything from basic Makie concepts (figures, axes, observables) to advanced techniques like live parameter sweeps, real-time input control, and animated 2D spatial simulations.

<img alt="An interactive dashboard showing a lumped thermal model with T0 and Tinf parameter controls" src="plots/readme_image.png" width=500/>

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad extension](https://help.juliahub.com/dyad/dev/getting_started/).

## Scripts

The `scripts/` directory contains annotated Julia scripts that progressively build up Makie and Dyad integration skills:

### `01_intro.jl` -- Introduction to Makie
Covers the fundamentals: Figure/Axis/Plot hierarchy, updating plot attributes via observables, using tick events for live updates, recording animations, and building complex multi-axis layouts with sliders and menus.

### `02_plot_solutions.jl` -- Plotting Dyad Simulation Results
Shows how to run a Dyad transient analysis and plot the result directly, including adding legends and creating 2D phase plots by selecting specific model variables.

### `03_paramsweep.jl` -- Interactive Parameter Sweeps
Demonstrates three approaches to live parameter control, each progressively faster and more scalable:
1. **Re-running the analysis** -- simple but slow; re-creates the full analysis on each parameter change.
2. **`remake` + `solve`** -- fast; uses ModelingToolkit's `remake` to update only the changed parameters before re-solving.
3. **Slider grids** -- user-friendly variant of the `remake` approach with `SliderGrid` controls.
4. **ComputeGraph** -- the most structured approach, using Makie's `ComputePipeline` to wire textbox inputs through a dependency graph to the solver.

### `04_input_realtime.jl` -- Real-Time Input Control (WIP)
Sets up the controlled oscillator model with `ModelingToolkitInputs` so that PID gains can be changed at runtime via an `InputSystem`.

### `05_autotuning_analysis.jl` -- PID Autotuning Designer
Launches the `DyadControlSystems` PID autotuning designer UI on a pre-built active-suspension example from `DyadExampleComponents`.

### `visualize_flat_mesh.jl` -- 2D Spatial Model Animations
Creates side-by-side 3D mesh and 2D heatmap animations of the 20x20 reaction-diffusion and FitzHugh-Nagumo wave models. Uses a fixed flat mesh geometry and updates only the per-vertex color each frame for performance.

## Models

The `dyad/` directory contains seven Dyad model files spanning thermal, mechanical, electrical, and spatial-dynamics domains:

| File | Description |
|------|-------------|
| `hello.dyad` | Lumped thermal model (Newton's law of cooling) with adjustable ambient temperature and heat transfer coefficient. |
| `spring_mass.dyad` | Spring-mass system with an external step-force input. |
| `controlled_oscillator.dyad` | Undamped spring-mass oscillator with a PID damping controller. Includes test cases for strong, weak, and no damping. |
| `rc_circuit.dyad` | Tunable RC charging circuit. Tests fast, medium, and slow charging via different resistance values. |
| `rlc_resonance.dyad` | RLC resonant circuit showing underdamped, critically damped, and overdamped transient responses. |
| `diffusion_2d.dyad` | 2D diffusion on a grid using custom connector/component primitives (DiffusionPort, DiffusionCapacitor, DiffusionResistor). Includes 5x5 and 100x100 grid tests, plus FitzHugh-Nagumo excitable-media variants. |
| `reaction_diffusion.dyad` | Reaction-diffusion models with exponential growth and FitzHugh-Nagumo traveling-wave dynamics on 5x5 and 20x20 grids. |

## Project Structure

```
MakieWebinar/
  dyad/          -- Dyad model source files (.dyad)
  generated/     -- Auto-generated Julia code from Dyad models
  scripts/       -- Runnable demo scripts (start here)
  src/           -- Module definition (re-exports generated code)
  test/          -- Test runner (executes generated model tests)
  plots/         -- Output images
  assets/        -- (reserved for additional assets)
```

## Dependencies

Key dependencies (see `Project.toml` for the full list):

- **Makie / GLMakie / WGLMakie / CairoMakie** -- plotting and interactive visualization
- **DyadInterface / DyadExampleComponents / DyadControlSystems** -- Dyad model compilation and simulation
- **ModelingToolkit / ModelingToolkitInputs** -- symbolic model manipulation and `remake`
- **ElectricalComponents / TranslationalComponents / BlockComponents** -- Dyad standard-library component packages
- **GeometryBasics** -- mesh construction for the 2D spatial visualizations
