# CoffeeMugDemo

<img src="./assets/icon.svg" width="96" align="right"/>

Pour an espresso at 90 C into a cold porcelain cup and it starts cooling
immediately. How fast? Does holding the cup change the answer? Does leaving a
metal spoon in it? This library answers those questions by simulating the
espresso, the cup, and everything touching them.

It is built with [Dyad](https://help.juliahub.com/dyad), a modeling language
where you describe physical parts and how they are wired together, and the Julia
`ModelingToolkit` ecosystem solves for the behavior.

## The approach

The espresso loses heat along four paths, each modeled as its own reusable
piece:

- through the cup wall to the surrounding air,
- from its open top surface into the rising steam,
- into your hand, wherever it grips the cup,
- along a metal spoon, if one is left standing in the cup.

Each piece is a component with thermal ports on it. Wiring the ports together
builds a whole cup, and swapping one piece in or out -- the spoon, say -- gives
you a second cup to compare against the first.

## Models

All Dyad models are defined in `dyad/CoffeeMugSubsystems.dyad`:

- **CoffeeMugSubsystem** -- The core subsystem containing the espresso thermal
  mass (60 mL, starting at 90 C) and a porcelain cup (starting at 20 C). It
  outputs the espresso temperature in degrees Celsius and models three
  heat-transfer paths:
  1. Convection from the espresso to the inner wall of the cup.
  2. Conduction through the cup wall.
  3. Convection and radiation from the outer surface to the environment.

- **SteamSubsystem** -- Models heat loss from the top surface of the espresso to
  the surrounding air via convection and radiation.

- **SpoonSubsystem** -- Models a stainless steel teaspoon partially submerged in
  the espresso. It acts as a thermal fin, conducting heat from the liquid
  through the spoon mass and dissipating it via convection and radiation from
  the exposed handle.

- **HandSubsystem** -- Models a hand in contact with the outer surface of the
  cup, represented as a thermal mass at body temperature (37 C) connected
  through a contact conductance.

- **EspressoCupSystemModular** -- A top-level assembly that connects the
  `CoffeeMugSubsystem`, `SteamSubsystem`, and `HandSubsystem` to a
  fixed-temperature ambient environment (20 C). This is the baseline
  configuration without a spoon.

- **EspressoCupSystemWithSpoon** -- An extended top-level assembly that adds the
  `SpoonSubsystem` to the baseline system, allowing comparison of cooling rates
  with and without a spoon.

Two transient analyses are also defined:

- **EspressoCoolingModular** -- Runs `EspressoCupSystemModular` for 6000 seconds
  using the Rodas5P solver.
- **EspressoCoolingWithSpoon** -- Runs `EspressoCupSystemWithSpoon` for 6000
  seconds using the Rodas5P solver.

## Notes

### Getting started

Download this folder to your machine and open it in VS Code with the [Dyad
extension](https://help.juliahub.com/dyad/dev/getting_started/).

### Running experiments

The script `scripts/simulate_coffee_mug.jl` demonstrates how to simulate and
visualize the espresso cooling process. It:

1. Simulates the **EspressoCupSystemModular** (no spoon) and plots the espresso
   temperature, cup temperature, hand temperature, and ambient temperature over
   time.
2. Simulates the **EspressoCupSystemWithSpoon** and plots the same quantities
   plus the spoon temperature.
3. Compares the espresso temperature curves from both configurations on a single
   plot, showing the effect of the spoon on cooling rate.

To run the script, start a Julia REPL from this project directory and execute:

```julia
include("scripts/simulate_coffee_mug.jl")
```
