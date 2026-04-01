# HybridTransmission

<img src="./assets/icon.svg" width="96" align="right"/>

A Dyad component library modeling a torque-split hybrid electric vehicle with power-split architecture. The system uses an Equivalent Consumption Minimization Strategy (ECMS) controller to optimally split torque demand between an internal combustion engine and two electric motor/generators, minimizing a weighted cost of fuel burn and battery drain in real time. The vehicle follows an EPA Highway Fuel Economy Test (HWFET) drive cycle.

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad extension](https://help.juliahub.com/dyad/dev/getting_started/).

## Running Experiments

### Analysis Notebook

The `scripts/analysis-notebook.ipynb` Jupyter notebook provides an interactive workflow using `DyadOrchestrator`. It loads the component library, runs any available analysis (such as `TestPowerSplitHybrid`), and produces artifacts including simulation solution plots. You can also select individual symbols to visualize specific variables from the solution.

### Helper Functions

The `src/fuel_efficiency_helpers.jl` file contains supporting Julia functions used by the Dyad models and available for custom scripting:

- `engine_bsfc_fuel_rate(torque_nm, speed_rpm)` -- Computes engine fuel rate (g/s) from a parabolic BSFC map.
- `epa_highway_speed(t)` -- Returns the smooth HWFET speed profile (m/s) at a given time.
- `rolling_resistance_force(speed_ms, C_rr, m_kg)` -- Calculates rolling resistance with a velocity threshold.
- `optimal_engine_point(power_demand_kw)` -- Returns the (torque, speed) operating point that minimizes BSFC for a given power demand.
- `udds_speed_profile(t)` -- A simplified UDDS (urban) drive cycle speed profile for alternative testing.

### Drive Cycle Data

The file `hwfet_data.csv` in the project root contains the raw EPA HWFET speed-vs-time data used as the basis for the drive cycle source block.

## Models

The library is defined in a single Dyad file (`dyad/hybrid_transmission.dyad`) containing the following components:

- **HybridEngine** -- Atkinson cycle ICE (74 kW / 99 hp) with a BSFC (Brake Specific Fuel Consumption) map expressed as polynomials. Fuel consumption data is based on Guzzella & Sciarretta, *Vehicle Propulsion Systems* (3rd ed., 2013).
- **HybridMG** -- Permanent magnet AC motor/generator with ideal torque control. Used for both MG1 (25 kW, sun gear / generator) and MG2 (70 kW, ring gear / traction motor).
- **HybridBattery** -- Simple equivalent-circuit lumped-parameter SOC estimator representing a NiMH battery pack (274--330 V nominal, 5.5 kWh usable).
- **HybridVehicle** -- Lumped vehicle model (1750 kg mid-size SUV) with aerodynamic drag and rolling resistance.
- **HighwayDriveCycle** -- EPA HWFET speed profile (765 s, 10.26 miles, max 60 mph). Downloaded from EPA data and encoded as a smooth piecewise approximation.
- **ECMSController** -- ECMS torque-split controller. Minimizes an equivalent fuel cost `J = fuel_rate + s * P_battery` where `s` is a dynamically adjusted equivalence factor driven by SOC feedback.
- **HybridPlanetaryGear** -- Planetary gear set (ratio 2.6) extending `RotationalComponents.IdealPlanetaryGear`, coupling engine (carrier), MG1 (sun), and MG2/wheels (ring).
- **PowerSplitHybrid** -- Top-level test component that wires all sub-components together into a complete vehicle system.
- **TestPowerSplitHybrid** -- Transient analysis running `PowerSplitHybrid` for 765 seconds (full HWFET cycle).

## Demo Notes

1. This is a model of a torque-split hybrid transmission, and follows an ECMS (Equivalent Consumption Minimization Strategy) control strategy to split torque demand between the battery and the engine.
2. ECMS: the core principle is that in real-time, a weight cost that is the sum of fuel-burn and battery drain is minimized. The relative costs of fuel burn and battery drain are determined by an equivalent factor. In this model, an effective equivalent factor is set dynamically.
3. Fuel burn is determined by a BSFC (Brake Specific Fuel Consumption) map in the engine component, expressed as polynomials. This was extracted by our agent from a book called *Vehicle Propulsion Systems*.
4. The battery is a very simple equivalent circuit lumped parameter SOC estimator, loosely based on a Nickel Metal Hydride chemistry. This was developed just for the control systems development.
5. A standard EPA Highway Drive cycle was downloaded from the internet by the agent and used as a source block. Vehicle speed tracking is not the focus of this model so a simple proportional law is incorporated in the controller.
6. The vehicle is modeled as a simple lumped mass with rolling resistance and aerodynamic drag.
7. The coupling mechanism is modeled as an ideal planetary gear which actuates two electric motors MG1 and MG2.

## Prompts Used for a Typical Demo

1. Summarize the models in this repo.
2. Please take a look at `hybrid_full_cycle.png`. The controller seems to fail charge sustaining operation. Can the controller be tuned to improve performance? Provide an assessment.
3. Can you write an optimization script to tune the controller and make a new plot just like the full cycle one?

## Future Improvements

1. Perfect speed tracking through a separate closed loop PID.
2. Higher fidelity battery model.
3. This model operates only in hybrid mode. With state machines you can operate this in pure EV or pure gas mode.
