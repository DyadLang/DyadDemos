# HL-20 Lifting Body — Architecture Reference

Subsonic flight simulation of the NASA HL-20 lifting body: 6-DOF rigid-body
dynamics, tabulated aerodynamics, 1976 Standard Atmosphere, control surface
mixer, and SAS flight control laws. The closed-loop system reproduces the aft
pitch-stick pulse from NASA TM-107580 Appendix F.

## Reference documents

| File | Content |
|---|---|
| `hl20_spec.md` | **Condensed engineering spec.** Equations, parameters, control laws, mixer logic. Primary reference. |
| `prompt.md` | Build-task statement (objective, files to create, constraints). |
| `scanned_pages/` | TM-107580 block diagrams (CSMixer, pitch/yaw control laws) and Appendix F check-case plots. |
| `nasa_appendixF_case0_man1.csv` | Digitized NASA reference time history for scenario 5 (informational). |

## Architecture decisions

### Scalar ports

All inter-component signals are individual `RealInput()` / `RealOutput()`
ports. Vectors are separate named scalars (e.g. `vel_1`, `vel_2`, `vel_3`).
No custom connectors or array ports.

### Frame convention

NED inertial frame (1=North, 2=East, 3=Down). Altitude = −pos_3. Quaternion is
scalar-first (qw, qx, qy, qz), body→inertial. SI units for dynamics
(m, kg, N, rad/s); aero interfaces use degrees and feet. All internal
computations are SI; imperial conversions (psf, fps, degrees) happen only at
aero-model boundaries and controller output interfaces.

### Pre-provided aero infrastructure

The HL-20 aerodynamic database (~72 lookup tables) is encoded in
`HL20_aero.dml`. The project ships:

- `src/shared_utils.jl` — DAVE-ML loader plus three registered symbolic
  functions (`hl20_poly1d`, `hl20_poly2dr`, `hl20_poly2de`) and three
  index accessors (`idx1d`, `grp2dr`, `grp2de`). Both the golden and the
  agent workspaces include this file, so the registered functions are
  available as `ChallengeComponent.<name>` from any `.dyad` file.
- `dyad/shared/HL20Aero.dyad` — body-axis coefficient buildup that calls
  those registered functions. Already wired with the correct varID groups;
  the agent only instantiates it as `ChallengeComponent.shared.HL20Aero(...)`.

### Atmosphere model

`Atmosphere1976` uses `DyadData.DyadTimeseries` + `BlockComponents.Tables.Interpolation`
(linear interpolation, constant extrapolation) over `assets/shared/atmos_sigma.csv`
and `assets/shared/atmos_sos.csv`, referenced as
`dyad://ChallengeComponent/shared/atmos_sigma.csv` and `…/atmos_sos.csv`.

## Component hierarchy

```
HL20Vehicle
├── RigidBody6DOF     Newton–Euler 6-DOF, quaternion orientation
├── Atmosphere1976    CSV table lookup for σ and speed of sound
├── FlightState       Inverse quaternion rotation → aero angles, Euler, airspeed
├── HL20Aero          (pre-provided) TM-4302 coefficient buildup
└── AeroForceBuilder  Coefficients → inertial forces + body torques (CG offset)

HL20Mixer             TM-107580 Appendix C, BlockComponents-based
├── Switch            ifelse(selector > threshold, A, B)
├── Abs               |u| (extends SISO)
└── AdjustableUpperLimit  max(min(u1, u2), u_min) (extends SI2SO)

PitchControl   TM-107580 §4.1 NZQ pitch SAS with auto-trim
RollControl    TM-107580 §4.1 roll-rate damper
YawControl     TM-107580 §4.1 yaw damper with washout
SpeedControl   TM-107580 §4.1 speedbrake shaping
```

### Interface contracts

| Component | Forces / velocities | Torques / rates |
|---|---|---|
| `RigidBody6DOF` | inertial NED | body frame |
| `AeroForceBuilder` | force out: inertial NED | torque out: body |
| `FlightState` | input: inertial NED velocity | output: degrees |
| `HL20Aero` | — | body rates input (rad/s) |

`RigidBody6DOF` adds gravity internally on `der(v3)`. External forces do
**not** include gravity. `AeroForceBuilder` also exposes the body-Z aero
force component to the vehicle for normal load factor (NZ) computation.

### HL20Vehicle outputs

The vehicle exposes feedback signals consumed by the controllers:
`ALPHA_DEG, BETADEG, BETADOT, MACH_out, PDEG, QDEG, RDEG, SINPHI, COSPHI,
COSTHE, QBAR, EAS, NZ, V_FPS`. See `hl20_spec.md` §8 for definitions.

### Mixer actuator chain

Each of the 7 surfaces:
`FirstOrder(τ = 0.05 s) → SlewRateLimiter(±20°/s) → Limiter(per-surface range)`.

## Validation scenarios

Scenarios, exact initial conditions, and constant input values for every test
are in `hl20_spec.md` §11. Summary:

| # | Analysis | Stop | Description |
|---|---|---|---|
| 1 | `TestGravityOnlySim` | 5 s | RigidBody6DOF alone, gravity-only freefall |
| 2 | `AeroSweepTransient` | 35 s | HL20Aero, α ramp −5° → +30° at Mach 0.2 |
| 3 | `TestHL20SubsonicSim` | 10 s | Open-loop vehicle plant at NASA trim |
| 4 | `TestControllersSim` | 15 s | Four controllers standalone with constant inputs |
| 5 | `TestHL20FullSystemSim` | 10 s | Closed-loop pitch pulse, matches NASA Appendix F |

## Debugging guide

- **Gravity-only fails:** check gravity direction (+pos_3 = NED down), quaternion kinematics signs, all six force/torque inputs wired.
- **Aero sweep discontinuities:** confirm the project module exposes the registered functions as `ChallengeComponent.hl20_poly1d`, etc.
- **Integrated tests fail after gravity-only passes:** check frame contracts — forces in inertial NED, torques in body, altitude = `−pos_3 × ft_per_m`.
- **NaN / divergence:** check division safety (`v_scalar`, `vrw_fps` denominators) and that all differential states have `initial` equations.
- **Closed-loop transient at t = 0:** ensure mixer FirstOrder actuator states are initialized at their equilibrium values (spec §11), not zero.
