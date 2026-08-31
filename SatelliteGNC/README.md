# SatelliteGNC

<img src="./assets/icon.svg" width="96" align="right"/>

A satellite attitude guidance, navigation, and control library built with
[Dyad](https://help.juliahub.com/dyad). A CubeSat-class spacecraft flies a rest-to-rest three-axis
repointing maneuver — roll 20°, pitch 10°, yaw 30° simultaneously — tracking a trapezoidal slew
profile on each axis. Rate feedback comes from a Luenberger observer driven by star-tracker angles
alone, so the controller damps rates it never measures. The loop ships twice: a 3-DOF version with
ideal torque actuation, and a 6-DOF version in a 400 km orbit where the same controller acts through
eight discrete thrusters and a pseudoinverse allocator. Comparing the two — tracking accuracy,
thruster authority, coupling into the orbit — is the point of the demo.

![Closed-loop repointing maneuver: attitude cube, Euler angles vs. references, observer rate estimates](./full_gnc_maneuver.gif)

## Getting Started

Download this folder to your machine and open it in VS Code with the
[Dyad extension](https://help.juliahub.com/dyad/dev/getting_started/).

## Models

The following Dyad models are defined in the `dyad/` directory:

- **`SatelliteBody`** (`satellite_body.dyad`) — Rigid-body rotational plant: Euler's equations on
  principal axes (`Ixx, Iyy, Izz = 10, 8, 6 kg·m²`) with 3-2-1 Euler-angle kinematics. The
  gyroscopic cross-coupling terms are retained, so multi-axis slews see the real coupling.

- **`SatelliteBody6DOF`** (`satellite_body_6dof.dyad`) — The same rotational dynamics plus two-body
  Keplerian translation in ECI (`m = 4 kg`), body-frame thrust rotated into ECI, and gravity-gradient
  torque from the orbital position. 12 states.

- **`TrapezoidalProfile`** (`trajectory_profile.dyad`) — Single-axis slew reference: accelerate at
  `a_max`, coast at `w_max`, decelerate to rest. It emits angle, rate, and acceleration references;
  the latter two drive rate-error damping and torque feedforward. The closed-loop assemblies run
  three of these at `w_max = 0.0349 rad/s` (2°/s) and `a_max = 0.00873 rad/s²` (0.5°/s²).

- **`AttitudeController`** (`attitude_controller.dyad`) — Per-axis PD with inertia feedforward,
  `τ = -Kp·(θ_meas - θ_ref) - Kd·(ω̂ - ω_ref) + I·α_ref`. Gains `Kp = 5, 4, 3` and `Kd = 20, 16, 12`
  put every axis at `ωn = 0.707 rad/s`, `ζ = 1.41`.

- **`LuenbergerObserver`** (`observer.dyad`) — Estimates body rates from angle measurements and the
  known applied torques, using a linearized single-axis copy of the plant. Double poles per axis at
  `-p` with `p = 2 rad/s`, giving `La = 2p` and `Lw = p²·I`.

- **`ReactionJet`** (`reaction_jet.dyad`) — One bipropellant thruster at body-frame position `r` with
  direction `d̂`: `F = cmd·F_max·d̂` and `τ = r × F`, with `cmd` clamped to `[-1, 1]`.

- **`ThrusterAllocator`** (`thruster_allocator.dyad`) — Maps commanded body forces and torques onto
  eight jet commands through the pseudoinverse of the 6×8 configuration matrix. The matrix has rank
  6, so the cluster is fully 6-DOF controllable with two redundant directions.

The two closed-loop assemblies each define a 40 s transient analysis:

| Model | Analysis | Loop |
|---|---|---|
| `TestFullGNC` (`full_gnc.dyad`) | `TestFullGNCSim` | 3 profiles → controller → `SatelliteBody`, observer closing the rate loop, ideal torque actuation |
| `TestFullGNC6DOF` (`full_gnc_6dof.dyad`) | `TestFullGNC6DOFSim` | Same guidance, navigation, and control, with `ThrusterAllocator` → 8 × `ReactionJet` (`F_max = 0.5 N`) actuating `SatelliteBody6DOF` on a 400 km circular orbit |

Each component file also carries its own unit test and analysis — open-loop and closed-loop plant
checks, one-orbit propagation, a single jet, the allocator-plus-jets cluster — all run by `Pkg.test()`.

## Running Experiments

`scripts/analysis-notebook.ipynb` loads the library through `DyadOrchestrator` and runs any analysis
in it: set `analysis_name` to one of the names listed by the `list_analyses` cell — for the full
maneuvers, `"TestFullGNCSim"` or `"TestFullGNC6DOFSim"` — and run the cells.

## Further Reading

- [`notes.md`](./notes.md) — Architecture of the 3-DOF loop: plant equations, choice of slew profile,
  observer pole placement and the separation-principle argument, the role of each controller term,
  and the closed-loop performance recorded at the shipped defaults.
- [`docs/algorithm_description.md`](./docs/algorithm_description.md) — Per-component specification:
  I/O tables, equations, literature references, and the test plan behind each component's tests.
