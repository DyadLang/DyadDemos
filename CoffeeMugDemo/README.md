# CoffeeMugDemo

A thermal simulation library built with [Dyad](https://help.juliahub.com/dyad) that models the cooling of an espresso in a porcelain mug. The library captures heat transfer through convection, conduction, and radiation across multiple interacting subsystems -- including the coffee, the mug, a hand holding the mug, the steam rising from the top surface, and an optional metal spoon. It serves as a demonstration of modular, component-based thermal modeling using Dyad's acausal modeling language and the Julia `ModelingToolkit` ecosystem.

## Models

All Dyad models are defined in `dyad/CoffeeMugSubsystems.dyad`:

- **CoffeeMugSubsystem** -- The core subsystem containing the espresso thermal mass (60 mL, starting at 90 C) and a porcelain cup (starting at 20 C). Models internal convection from espresso to the cup inner wall, conduction through the cup wall, and external convection and radiation from the cup outer surface to the environment. Outputs the espresso temperature in degrees Celsius.

- **SteamSubsystem** -- Models heat loss from the top surface of the espresso to the surrounding air via convection and radiation.

- **SpoonSubsystem** -- Models a stainless steel teaspoon partially submerged in the espresso. It acts as a thermal fin, conducting heat from the liquid through the spoon mass and dissipating it via convection and radiation from the exposed handle.

- **HandSubsystem** -- Models a hand in contact with the outer surface of the cup, represented as a thermal mass at body temperature (37 C) connected through a contact conductance.

- **EspressoCupSystemModular** -- A top-level assembly that connects the `CoffeeMugSubsystem`, `SteamSubsystem`, and `HandSubsystem` to a fixed-temperature ambient environment (20 C). This is the baseline configuration without a spoon.

- **EspressoCupSystemWithSpoon** -- An extended top-level assembly that adds the `SpoonSubsystem` to the baseline system, allowing comparison of cooling rates with and without a spoon.

Two transient analyses are also defined:

- **EspressoCoolingModular** -- Runs `EspressoCupSystemModular` for 6000 seconds using the Rodas5P solver.
- **EspressoCoolingWithSpoon** -- Runs `EspressoCupSystemWithSpoon` for 6000 seconds using the Rodas5P solver.

## Running Experiments

The script `scripts/simulate_coffee_mug.jl` demonstrates how to simulate and visualize the espresso cooling process. It:

1. Simulates the **EspressoCupSystemModular** (no spoon) and plots the espresso temperature, cup temperature, hand temperature, and ambient temperature over time.
2. Simulates the **EspressoCupSystemWithSpoon** and plots the same quantities plus the spoon temperature.
3. Compares the espresso temperature curves from both configurations on a single plot, showing the effect of the spoon on cooling rate.

To run the script, start a Julia REPL from this project directory and execute:

```julia
include("scripts/simulate_coffee_mug.jl")
```

## Getting Started

1. Run `Julia: Start REPL` from the VS Code command palette (or start Julia in a terminal).

2. Enter the package manager by typing `]`, then run:

   ```
   pkg> instantiate
   ```

   This downloads all required dependencies (the first time may take a while).

3. To verify the models are working, run the tests from the package manager prompt:

   ```
   pkg> test
   ```

4. Return to the Julia REPL with `Backspace`/`Delete`, then load the library:

   ```julia
   using CoffeeMugDemo
   ```

5. Run a simulation using the pre-defined analyses:

   ```julia
   EspressoCoolingModular()
   EspressoCoolingWithSpoon()
   ```

6. For plotting, add the `Plots` package and follow the pattern in `scripts/simulate_coffee_mug.jl`:

   ```julia
   using Plots
   using ModelingToolkit, DyadInterface

   @named model = EspressoCupSystemModular()
   res = TransientAnalysis(; model, alg = "auto", abstol = 10.0e-3, reltol = 1.0e-3, start = 0.0, stop = 6000)
   plot(res, idxs=[model.coffeeMug.espressoTemp_degC])
   ```
