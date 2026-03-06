# FrictionBrakeDemo

This library provides acausal, equation-based models of a vehicle friction brake system with coupled thermal effects, built using the Dyad modeling language. It includes individual subsystem models for a friction brake, brake thermal dynamics, a simple powertrain, a driver controller, and a simple vehicle, which can be composed together into full-system simulations. The primary goal is to demonstrate how braking energy is converted to heat and how disk and pad temperatures evolve under realistic driving cycles.

## Models

The following Dyad models are defined in the `dyad/` directory:

- **`FrictionBrake`** -- A friction brake component that converts a normalized brake command (0-1) into an opposing torque on a rotational shaft. It computes temperature-dependent friction coefficients and partitions the resulting friction power into heat flows to the brake disk and pad via thermal ports.

- **`BrakeThermal`** -- A thermal model of the brake disk and pad. Each has its own thermal mass, speed-dependent convective cooling to ambient, and radiation coupling. The disk also radiates to ambient. External heat input ports allow coupling to the `FrictionBrake` heat outputs.

- **`SimplePowertrain`** -- A powertrain that converts a throttle command (0-1) into drive torque on a rotational shaft. Torque capacity varies with vehicle speed via a polynomial curve, and a first-order lag models the torque response dynamics.

- **`SimpleVehicle`** -- A longitudinal vehicle model with a rotational shaft interface, drive inertia, an ideal rolling wheel converting rotation to translation, vehicle mass, and a translational damper representing road load resistance. Outputs vehicle speed and wheel speed signals.

- **`Driver`** -- A PID-based driver controller that takes a reference speed and actual speed, then outputs throttle and brake commands. Positive PID output maps to throttle; negative maps to braking.

- **`VehicleCycleTest`** -- The full integrated test model. It connects the `Driver`, `SimplePowertrain`, `FrictionBrake`, `SimpleVehicle`, and `BrakeThermal` into a closed-loop system driven by a sinusoidal speed reference, producing repeating acceleration and braking transients that exercise the brake thermal dynamics.

Each model file also contains its own test harnesses (prefixed with `Test` or suffixed with `Test`) and corresponding `analysis` definitions used for standalone verification.

## Running Experiments

Three simulation scripts are provided in the `scripts/` directory. Each script loads the library, builds a model, runs a transient simulation, and plots results.

- **`scripts/simulate_brake_thermal_test.jl`** -- Simulates the `BrakeThermalTest_Constant` model for 1800 seconds with constant heat inputs to the disk and pad. Plots the disk and pad temperature rise over time, useful for verifying the thermal model in isolation.

- **`scripts/simulate_simple_vehicle_test.jl`** -- Simulates the `SimpleVehicleTest_CoastDown` model for 100 seconds. The vehicle starts at 108 km/h with zero drive torque and coasts down under road load resistance, demonstrating the vehicle dynamics model.

- **`scripts/simulate_vehicle_cycle_test.jl`** -- Simulates the full `VehicleCycleTest` model for 2000 seconds. This is the main demonstration: a sinusoidal speed reference drives repeated acceleration and braking transients. The script plots vehicle speed tracking, disk and pad temperatures, driver throttle/brake commands, powertrain and brake torques, and heat flows into the brake.

## Getting Started

This library was created with the Dyad Studio VS Code extension. Your Dyad
models should be placed in the `dyad` directory and the files should be
given the `.dyad` extension. Several such files have already been placed
in there to get you started. The Dyad compiler will compile the Dyad models
into Julia code and place it in the `generated` folder. Do not edit the
files in that directory or remove/rename that directory.

To run the provided example models:

1. Run `Julia: Start REPL` from the command palette.

2. Type `]`. This will take you to the package manager prompt.

3. At the `pkg>` prompt, type `instantiate` (this downloads all the Julia libraries
   you will need, and the very first time you do it it might take a while).

4. From the same `pkg>` prompt, type `test`. This will run the full test suite
   to make sure all models are working as expected. It may take some time but
   you should eventually see a result indicating all tests passed.

5. Use the `Backspace`/`Delete` key to return to the normal Julia REPL, it should
   look like this: `julia>`.

6. Type `using FrictionBrakeDemo`. This will load your model library.

7. Type `BrakeThermalAnalysis_Constant()` to run a simulation of the
   `BrakeThermalTest_Constant` model. The first time you run it, this might take
   a few seconds, but each successive time you run it, it should be very fast.

8. To see simulation results type `using Plots` (and answer `y` if asked if you
   want to add it as a dependency).

9. To plot results of the `BrakeThermalAnalysis_Constant` simulation, simply type
   `plot(BrakeThermalAnalysis_Constant())`.

10. You can plot variations on that simulation using keyword arguments. For example,
    try `plot(BrakeThermalAnalysis_Constant(stop=1500, Q_disk=8000))`.
