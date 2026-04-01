# ThermalHouseDemo

<img src="./assets/icon.svg" width="96" align="right"/>

A Dyad-based thermal modeling library for simulating the heating dynamics of a residential house. It models heat transfer through the building envelope (walls, roof, floor, windows, doors), air infiltration, solar gains, internal gains, and HVAC heating, allowing you to study how indoor temperature responds to weather conditions and control strategies.

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad extension](https://help.juliahub.com/dyad/dev/getting_started/).

## Running Experiments

Each `.dyad` file defines `analysis` blocks that serve as ready-to-run experiments:

- **`TestHouseWinterDesign`** -- Simulates the open-loop `ThermalHouse` with a constant 7.5 kW heater and 0 C outdoor temperature for 2 hours. Use this to observe how interior temperature evolves with fixed heating.
- **`TestControlledHouseWinterDesign`** -- Simulates the PI-controlled house starting at 15.5 C with a 21.1 C setpoint and 0 C outdoors for 2 hours. Use this to observe the controller warming the house to the setpoint.

You can run these analyses and plot the results from the Julia REPL:

```julia
using ThermalHouseDemo
using Plots

# Run the open-loop winter design analysis
sol = TestHouseWinterDesign()
plot(sol)

# Run the closed-loop controlled analysis
sol = TestControlledHouseWinterDesign()
plot(sol)
```

You can also customize parameters via keyword arguments, for example:

```julia
# Run for 4 hours instead of 2
sol = TestHouseWinterDesign(stop=14400.0)

# Change the PI controller gains
sol = TestControlledHouseWinterDesign(k_p=15000.0, T_i=300.0)
```

## Models

The `dyad/` directory contains two component models and their associated test analyses:

### ThermalHouse (`dyad/ThermalHouse.dyad`)

An open-loop thermal model of a house. It accepts three external inputs -- heater power (`Q_heater`), solar irradiance (`solar_irradiance`), and ambient temperature (`T_ambient`) -- and outputs the interior temperature (`T_interior`). Key features:

- **Building geometry** parameterized for a default 1000 sq ft house (floor area, wall height, window-to-wall ratio, number of doors).
- **Envelope heat loss** through walls, windows, doors, roof, and floor, each with configurable U-values.
- **Air infiltration and ventilation** losses based on air changes per hour (ACH).
- **Thermal mass** accounting for air volume, drywall, and floor slab.
- **Solar heat gain** through windows (via SHGC and orientation factor).
- **Internal gains** from occupants, lighting, and appliances.

The file also includes `TestThermalHouse`, a test component that wires constant signals into the house model (7500 W heater, 0 C outdoor temperature, no solar), and `TestHouseWinterDesign`, a transient analysis that runs this test for 7200 seconds (2 hours).

### ThermalHouseControlled (`dyad/ThermalHouseControlled.dyad`)

A closed-loop variant that wraps `ThermalHouse` with a PI (proportional-integral) controller. It accepts a temperature setpoint (`T_setpoint`), solar irradiance, and ambient temperature as inputs, and outputs the interior temperature and heater power. The PI controller automatically modulates heater output (clamped between 0 and `Q_max`) to track the setpoint.

The file also includes `TestThermalHouseControlled`, a test component with constant setpoint (21.1 C) and outdoor (0 C) signals, and `TestControlledHouseWinterDesign`, a transient analysis that starts the house at 15.5 C (288.7 K) and simulates the controller warming it up over 7200 seconds.
