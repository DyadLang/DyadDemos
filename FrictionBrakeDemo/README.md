# FrictionBrakeDemo

<img src="./assets/icon.svg" width="96" align="right"/>

Braking turns a car's motion into heat in the brake disks. Do it often enough --
down a long descent, or lap after lap -- and the disks get hot enough that the
friction material loses its grip. The brakes fade.

This library models that effect in [Dyad](https://help.juliahub.com/dyad). You
get a friction brake, the disk and pad it heats up, and enough of a car around
them to drive a realistic cycle and watch the temperatures climb.

## Models

The following Dyad models are defined in the `dyad/` directory:

- **`FrictionBrake`** -- A friction brake component that converts a normalized
  brake command (0-1) into an opposing torque on a rotational shaft. It computes
  temperature-dependent friction coefficients and partitions the resulting
  friction power into heat flows to the brake disk and pad via thermal ports.

- **`BrakeThermal`** -- Tracks how hot the disk and pad get. Each part has:
  - a thermal mass that stores the heat it absorbs,
  - convective cooling to ambient air, stronger the faster the car moves,
  - radiative coupling -- pad to disk, and disk to ambient.

  Heat input ports connect it to the `FrictionBrake` heat outputs.

- **`SimplePowertrain`** -- A powertrain that converts a throttle command (0-1)
  into drive torque on a rotational shaft. Torque capacity varies with vehicle
  speed via a polynomial curve, and a first-order lag models the torque response
  dynamics.

- **`SimpleVehicle`** -- A car moving in a straight line, assembled from:
  - a rotational shaft where drive and brake torque arrive,
  - a drive inertia for the spinning parts,
  - an ideal rolling wheel that turns rotation into travel,
  - the vehicle mass,
  - a translational damper standing in for road load.

  It outputs vehicle speed and wheel speed.

- **`Driver`** -- A PID-based driver controller that takes a reference speed and
  actual speed, then outputs throttle and brake commands. Positive PID output
  maps to throttle; negative maps to braking.

- **`VehicleCycleTest`** -- The whole car wired into a closed loop. The driver
  chases a sinusoidal speed reference, so the car accelerates and brakes over
  and over, and every braking event pushes more heat into the disk and pad.

Each model file also contains its own test harnesses (prefixed with `Test` or
suffixed with `Test`) and corresponding `analysis` definitions used for
standalone verification.

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad
extension](https://help.juliahub.com/dyad/dev/getting_started/).

## Running Experiments

Three simulation scripts are provided in the `scripts/` directory. Each script
loads the library, builds a model, runs a transient simulation, and plots
results.

- **`scripts/simulate_brake_thermal_test.jl`** -- Simulates the
  `BrakeThermalTest_Constant` model for 1800 seconds with constant heat inputs
  to the disk and pad. Plots the disk and pad temperature rise over time, useful
  for verifying the thermal model in isolation.

- **`scripts/simulate_simple_vehicle_test.jl`** -- Simulates the
  `SimpleVehicleTest_CoastDown` model for 100 seconds. The vehicle starts at 108
  km/h with zero drive torque and coasts down under road load resistance,
  demonstrating the vehicle dynamics model.

- **`scripts/simulate_vehicle_cycle_test.jl`** -- Simulates the full
  `VehicleCycleTest` model for 2000 seconds. This is the main demonstration: a
  sinusoidal speed reference drives repeated acceleration and braking
  transients. It plots:
  - vehicle speed tracking,
  - disk and pad temperatures,
  - driver throttle and brake commands,
  - powertrain and brake torques,
  - heat flows into the brake.
