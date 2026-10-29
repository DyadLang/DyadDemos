# HL-20 Lifting Body — Build Task

## Objective

Build an end-to-end 6-DOF flight simulation of the NASA HL-20 lifting body in
Dyad. Five validation analyses are graded against the golden solution.

## Read first

The authoritative engineering reference is in this assets directory:

| File | Content |
|---|---|
| `hl20_spec.md` | Vehicle parameters, frame conventions, equations, control laws, mixer logic, validation scenarios, initial conditions. Primary reference. |
| `readmeHL20.md` | Architecture decisions and interface contracts. |
| `nasa_appendixF_case0_man1.csv` | Digitized NASA check-case time history for scenario 5 (informational; the grader uses the golden solution as truth). |
| `scanned_pages/` | Block diagrams (CSMixer, pitch/yaw control laws) and Appendix F check-case plots from TM-107580. |
| `atmos_sigma.csv`, `atmos_sos.csv` | 1976 Standard Atmosphere tables, used by `Atmosphere1976`. |
| `HL20_aero.dml`, `atmos_76.dml` | DAVE-ML source files. Already parsed by the project module — you do not read them yourself. |

## Pre-provided

| File | Notes |
|---|---|
| `dyad/shared/HL20Aero.dyad` | Full TM-4302 body-axis coefficient buildup. Instantiate as `ChallengeComponent.shared.HL20Aero(...)` from `HL20Vehicle.dyad` (and `TestAeroSweep.dyad`). Do not modify. |
| `src/shared_utils.jl` | DAVE-ML loader and the registered symbolic functions (`hl20_poly1d`, `hl20_poly2dr`, `hl20_poly2de`) plus index accessors (`idx1d`, `grp2dr`, `grp2de`). Called by `HL20Aero.dyad`. Do not modify. |
| `assets/shared/atmos_*.csv` | Reference atmosphere CSVs from `Atmosphere1976` as `dyad://ChallengeComponent/shared/atmos_sigma.csv` (and `…/atmos_sos.csv`). |

## Files to create (in `dyad/`)

```
RigidBody6DOF.dyad         6-DOF quaternion dynamics                  (§3)
Atmosphere1976.dyad        CSV table-lookup atmosphere                (§4)
FlightState.dyad           inverse quat rotation → α, β, Euler         (§5)
AeroForceBuilder.dyad      coefficients → forces / torques            (§6)
HL20Vehicle.dyad           plant integration                          (§8)

Switch.dyad                ifelse selector
Abs.dyad                   |u| (extends SISO)
AdjustableUpperLimit.dyad  max(min(u1, u2), u_min) (extends SI2SO)

HL20Mixer.dyad             7-surface mixer + actuators                (§10)
PitchControl.dyad          NZQ pitch SAS with auto-trim               (§9.1)
RollControl.dyad           roll-rate damper                           (§9.2)
YawControl.dyad            yaw damper with washout                    (§9.3)
SpeedControl.dyad          quadratic speedbrake                       (§9.4)

TestGravityOnly.dyad       analysis TestGravityOnlySim   (5 s)
TestAeroSweep.dyad         analysis AeroSweepTransient   (35 s)
TestHL20Subsonic.dyad      analysis TestHL20SubsonicSim  (10 s)
TestControllers.dyad       analysis TestControllersSim   (15 s)
TestHL20FullSystem.dyad    analysis TestHL20FullSystemSim (10 s)
```

The grader calls each analysis by name — match these exactly.

## Constraints

- All new Dyad files go in `dyad/`. Do not touch `dyad/shared/HL20Aero.dyad`, `src/`, or anything in `assets/`.
- Mixer must be built from `BlockComponents` blocks (`Gain`, `Add`, `Add3`, `Limiter`, `SlewRateLimiter`, `FirstOrder`, `Constant`).
- Inter-component signals are individual `RealInput()` / `RealOutput()` ports — no array ports, no custom connectors.
- HL20Aero outputs are body-axis: `CX, CY, CZ, Cl, Cm, Cn`.
- `RigidBody6DOF` adds gravity internally on `der(v3)`. External force inputs do not include gravity.
- All 13 RigidBody6DOF states (`p1..p3, v1..v3, q0..q3, w1..w3`) need `initial` equations in every test that uses them. Mixer FirstOrder actuator states and pitch/yaw controller integrator states need `initial` equations in scenario 5 — see `hl20_spec.md` §11.
