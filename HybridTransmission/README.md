# HybridTransmission

<img src="./assets/icon.svg" width="96" align="right"/>

A hybrid car carries two power sources: a gasoline engine and a battery driving
electric motors. Every moment the driver asks for speed, something has to decide
how much of that demand each source supplies. This library models that decision,
and the controller that makes it.

An Equivalent Consumption Minimization Strategy (ECMS) controller makes that
decision. Moment by moment, it splits the torque demand between the internal
combustion engine and two electric motor/generators, minimizing a weighted cost
of fuel burnt and battery drained.

The car is a torque-split hybrid with a power-split planetary gearset, and it
drives the EPA Highway Fuel Economy Test (HWFET) cycle.

## Models

The library is defined in a single Dyad file (`dyad/hybrid_transmission.dyad`)
containing the following components:

- **HybridEngine** -- [Atkinson cycle](https://en.wikipedia.org/wiki/Atkinson_cycle) petrol engine (74 kW / 99 hp), the efficiency-favouring cycle hybrids normally use with a BSFC (Brake
  Specific Fuel Consumption) map expressed as polynomials. Fuel consumption data
  is based on Guzzella & Sciarretta, *Vehicle Propulsion Systems* (3rd ed.,
  2013).
- **HybridMG** -- Permanent magnet AC motor/generator with ideal torque control.
  Used for both MG1 (25 kW, sun gear / generator) and MG2 (70 kW, ring gear /
  traction motor).
- **HybridBattery** -- Simple equivalent-circuit lumped-parameter SOC estimator
  representing a NiMH battery pack (274--330 V nominal, 5.5 kWh usable).
- **HybridVehicle** -- Lumped vehicle model (1750 kg mid-size SUV) with
  aerodynamic drag and rolling resistance.
- **HighwayDriveCycle** -- EPA HWFET speed profile (765 s, 10.26 miles, max 60
  mph). Downloaded from EPA data and encoded as a smooth piecewise
  approximation.
- **ECMSController** -- ECMS torque-split controller. Minimizes an equivalent
  fuel cost `J = fuel_rate + s * P_battery` where `s` is a dynamically adjusted
  equivalence factor driven by SOC feedback.
- **HybridPlanetaryGear** -- Planetary gear set (ratio 2.6) extending
  `RotationalComponents.IdealPlanetaryGear`, coupling engine (carrier), MG1
  (sun), and MG2/wheels (ring).
- **PowerSplitHybrid** -- Top-level test component that wires all sub-components
  together into a complete vehicle system.
- **TestPowerSplitHybrid** -- Transient analysis running `PowerSplitHybrid` for
  765 seconds (full HWFET cycle).

### How the controller splits the demand

The controller prices battery drain in units of fuel, then picks the cheapest
split at every instant.

That price is the equivalence factor `s`. It rises as the battery falls below
its target charge, pushing work onto the engine; it falls as the battery fills,
pushing work onto the motors.

Over the full 765-second highway cycle, this keeps the battery near where it
started.

Modeling choices worth knowing:

- Fuel burn comes from a BSFC map -- grams of fuel per unit of work -- fitted as
  polynomials from Guzzella & Sciarretta, *Vehicle Propulsion Systems*.
- The battery is an equivalent-circuit charge estimator with Nickel Metal
  Hydride characteristics, at the fidelity control development needs.
- The vehicle is modeled as a simple lumped mass with rolling resistance and
  aerodynamic drag.
- The coupling mechanism is modeled as an ideal planetary gear which actuates
  two electric motors MG1 and MG2.
- The controller tracks the drive cycle's speed with a proportional law; the
  torque split is the subject here.

## Notes

### Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad
extension](https://help.juliahub.com/dyad/dev/getting_started/).

### Analysis Notebook

The `scripts/analysis-notebook.ipynb` Jupyter notebook provides an interactive
workflow using `DyadOrchestrator`. It loads the component library, runs any
available analysis (such as `TestPowerSplitHybrid`), and produces artifacts
including simulation solution plots. You can also select individual symbols to
visualize specific variables from the solution.

### Helper Functions

The `src/fuel_efficiency_helpers.jl` file contains supporting Julia functions
used by the Dyad models and available for custom scripting:

- `engine_bsfc_fuel_rate(torque_nm, speed_rpm)` -- Computes engine fuel rate
  (g/s) from a parabolic BSFC map.
- `epa_highway_speed(t)` -- Returns the smooth HWFET speed profile (m/s) at a
  given time.
- `rolling_resistance_force(speed_ms, C_rr, m_kg)` -- Calculates rolling
  resistance with a velocity threshold.
- `optimal_engine_point(power_demand_kw)` -- Returns the (torque, speed)
  operating point that minimizes BSFC for a given power demand.
- `udds_speed_profile(t)` -- A simplified UDDS (urban) drive cycle speed profile
  for alternative testing.

### Drive Cycle Data

The file `hwfet_data.csv` in the project root contains the raw EPA HWFET
speed-vs-time data used as the basis for the drive cycle source block.

## Prompts Used for a Typical Demo

1. Summarize the models in this repo.
2. Please take a look at `hybrid_full_cycle.png`. The controller seems to fail
   charge sustaining operation. Can the controller be tuned to improve
   performance? Provide an assessment.
3. Can you write an optimization script to tune the controller and make a new
   plot just like the full cycle one?

## Future Improvements

1. Perfect speed tracking through a separate closed loop PID.
2. Higher fidelity battery model.
3. Pure EV and pure gas modes, selected by a state machine. The model runs only
   in hybrid mode today.
