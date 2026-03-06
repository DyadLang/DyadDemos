# FrictionBrakeDemo

This library provides acausal, equation-based models of a vehicle friction brake system with coupled thermal effects, built using the Dyad modeling language. It includes individual subsystem models for a friction brake, brake thermal dynamics, a simple powertrain, a driver controller, and a simple vehicle, which can be composed together into full-system simulations. The primary goal is to demonstrate how braking energy is converted to heat and how disk and pad temperatures evolve under realistic driving cycles.

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad extension](https://help.juliahub.com/dyad/dev/getting_started/).

## Running Experiments

Three simulation scripts are provided in the `scripts/` directory. Each script loads the library, builds a model, runs a transient simulation, and plots results.

- **`scripts/simulate_brake_thermal_test.jl`** -- Simulates the `BrakeThermalTest_Constant` model for 1800 seconds with constant heat inputs to the disk and pad. Plots the disk and pad temperature rise over time, useful for verifying the thermal model in isolation.

- **`scripts/simulate_simple_vehicle_test.jl`** -- Simulates the `SimpleVehicleTest_CoastDown` model for 100 seconds. The vehicle starts at 108 km/h with zero drive torque and coasts down under road load resistance, demonstrating the vehicle dynamics model.

- **`scripts/simulate_vehicle_cycle_test.jl`** -- Simulates the full `VehicleCycleTest` model for 2000 seconds. This is the main demonstration: a sinusoidal speed reference drives repeated acceleration and braking transients. The script plots vehicle speed tracking, disk and pad temperatures, driver throttle/brake commands, powertrain and brake torques, and heat flows into the brake.

## Models

The following Dyad models are defined in the `dyad/` directory:

- **`FrictionBrake`** -- A friction brake component that converts a normalized brake command (0-1) into an opposing torque on a rotational shaft. It computes temperature-dependent friction coefficients and partitions the resulting friction power into heat flows to the brake disk and pad via thermal ports.

- **`BrakeThermal`** -- A thermal model of the brake disk and pad. Each has its own thermal mass, speed-dependent convective cooling to ambient, and radiation coupling. The disk also radiates to ambient. External heat input ports allow coupling to the `FrictionBrake` heat outputs.

- **`SimplePowertrain`** -- A powertrain that converts a throttle command (0-1) into drive torque on a rotational shaft. Torque capacity varies with vehicle speed via a polynomial curve, and a first-order lag models the torque response dynamics.

- **`SimpleVehicle`** -- A longitudinal vehicle model with a rotational shaft interface, drive inertia, an ideal rolling wheel converting rotation to translation, vehicle mass, and a translational damper representing road load resistance. Outputs vehicle speed and wheel speed signals.

- **`Driver`** -- A PID-based driver controller that takes a reference speed and actual speed, then outputs throttle and brake commands. Positive PID output maps to throttle; negative maps to braking.

- **`VehicleCycleTest`** -- The full integrated test model. It connects the `Driver`, `SimplePowertrain`, `FrictionBrake`, `SimpleVehicle`, and `BrakeThermal` into a closed-loop system driven by a sinusoidal speed reference, producing repeating acceleration and braking transients that exercise the brake thermal dynamics.

Each model file also contains its own test harnesses (prefixed with `Test` or suffixed with `Test`) and corresponding `analysis` definitions used for standalone verification.
