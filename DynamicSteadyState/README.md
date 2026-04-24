# DynamicSteadyState

<img src="./assets/icon_three_zone_building.svg" width="96" align="right"/>

A Dyad component library modeling a three-zone commercial office building thermal envelope. One building model serves as the single source of truth for two different analyses: a steady-state HVAC equipment sizing analysis and a 24-hour transient diurnal operation simulation with thermostat control. The three zones (south-facing, core, north-facing) are connected by inter-zone partition resistors. Each zone includes wall, window, roof, slab, and infiltration heat paths, a lumped thermal mass, and a proportional thermostat heater. Boundary conditions include a time-varying outdoor temperature, a stable ground temperature, occupancy-modulated internal gains, and solar gains.

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad extension](https://help.juliahub.com/dyad/dev/getting_started/).

## Running Experiments

Each analysis can be run from the Julia REPL after loading the library:

```julia
using DynamicSteadyState
using Plots
```

### Steady-State HVAC Sizing

Two steady-state analyses determine the required HVAC capacity by fixing zone temperatures at 21 °C and letting the solver compute the heat flow at each zone port.

- **`HVACSizing`** — Design-day conditions: −5 °C outdoor, 10 °C ground, peak occupancy internal gains (600, 500, 400 W), and design-average solar gains (1500 W south, 375 W north).
- **`ColdNightSizing`** — Cold-night conditions: −10 °C outdoor, 10 °C ground, no internal or solar gains (worst-case heating demand).

```julia
# Run the design-day sizing
result = HVACSizing()
sol = result.sol

# Run the cold-night sizing
result = ColdNightSizing()
sol = result.sol
```

### 24-Hour Diurnal Operation

**`DiurnalOperation`** runs the same building with time-varying boundary conditions over a full day (86 400 s). A sinusoidal outdoor temperature swings from −10 °C to 0 °C, solar gains follow a daytime sine peaking at noon, and internal gains are modulated by a representative weekday office occupancy schedule. Thermostat heaters on each zone are sized from the steady-state results with a 1.2× safety factor. Zones start cold at 12 °C.

```julia
# Run the 24-hour transient simulation
result = DiurnalOperation()
plot(result)
```

## Models

All Dyad models are defined in two files in the `dyad/` directory:

### `dyad/hello.dyad`

- **Hello** — A minimal lumped thermal model demonstrating Newton's law of cooling. A single thermal mass cools or heats toward an ambient temperature.
- **World** — Transient analysis running `Hello` for 10 seconds.

### `dyad/building_model.dyad`

#### Reusable Components

- **HeatCapacitorNoInit** — Identical to `ThermalComponents.Components.HeatCapacitor` but omits the built-in initial condition, allowing the test harness to supply initial conditions for transient analysis while leaving steady-state analysis free of over-determined initialization constraints.

- **ThermostatHeater** — A proportional thermostat heater. Computes a heating demand proportional to the gap between a setpoint and the zone temperature, clamped between 0 and a maximum capacity `Q_max`.

- **OfficeOccupancy** — A representative weekday office occupancy schedule outputting a fraction (0–1) via piecewise-linear interpolation of hourly breakpoints. Ramping up from 6 AM, peaking at 95% during work hours with a lunch dip, and tapering off in the evening.

- **ZoneRoom** — A lumped single-zone thermal model. Encapsulates per-zone envelope heat paths (wall, window, roof, slab, infiltration) and thermal mass. Outdoor and ground temperatures enter as causal signal inputs via `PrescribedTemperature`. A single `HeatPort` zone port is exposed for HVAC, gains, and inter-zone connections.

- **ThreeZoneBuilding** — The top-level building envelope. Three `ZoneRoom` blocks (south, core, north) connected by inter-zone partition resistors. Outdoor and ground temperatures fan out to each zone as signal inputs. Three `HeatPort` zone ports are exposed for external HVAC and gain connections.

#### Test Harnesses and Analyses

- **TestSteadySizing** / **HVACSizing** — Wires the building with constant boundary conditions (−5 °C outdoor, 10 °C ground), peak internal and solar gains, and `FixedTemperature` setpoints at 21 °C on each zone. The steady-state solver determines the required heat flow at each port.

- **TestColdNightSizing** / **ColdNightSizing** — Same building with −10 °C outdoor, no internal or solar gains, and 21 °C zone setpoints. Determines worst-case heating demand.

- **TestDiurnalOperation** / **DiurnalOperation** — Wires the building with sinusoidal outdoor temperature and solar gains, occupancy-modulated internal gains, and `ThermostatHeater` controllers sized from the steady-state results. Runs a 24-hour transient simulation starting from 12 °C.
