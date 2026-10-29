# 3-DOF Satellite Attitude GNC Closed-Loop System

## Overview

This system implements a closed-loop attitude control architecture for a
rigid-body satellite with 3 rotational degrees of freedom. The architecture
follows a standard GNC decomposition:

- **Guidance** — slew profile generation
- **Navigation** — state estimation
- **Control** — torque computation

## Plant: Rigid Body Dynamics

The satellite is modeled using Euler's rotational equations of motion on
principal axes:

```text
Ixx·ω̇x = τx + (Iyy − Izz)·ωy·ωz
Iyy·ω̇y = τy + (Izz − Ixx)·ωz·ωx
Izz·ω̇z = τz + (Ixx − Iyy)·ωx·ωy
```

Attitude kinematics use the 3-2-1 (yaw-pitch-roll) Euler angle convention. The
gyroscopic cross-coupling terms (ωi·ωj products) are retained — they become
significant during multi-axis maneuvers when angular rates are non-negligible
simultaneously.

The plant has 6 differential states: 3 angular velocities (ωx, ωy, ωz) and 3
Euler angles (φ, θ, ψ). Inertia parameters are representative of a CubeSat-class
platform (Ixx = 10, Iyy = 8, Izz = 6 kg·m²).

## Guidance: Trapezoidal Velocity Profile

Each axis has an independent rest-to-rest slew profile that respects rate and
acceleration constraints:

- `ω_max` = 0.0349 rad/s (2°/s)
- `α_max` = 0.00873 rad/s² (0.5°/s²)

Each profile runs three phases, the standard AOCS slew shape (ESA
ECSS-E-ST-60-30C):

1. accelerate at `α_max` until the rate reaches `ω_max`
2. coast at `ω_max`
3. decelerate at `α_max` back to rest

It publishes one signal per phase quantity, and the controller consumes all
three:

| Output | Controller use |
|---|---|
| angle reference | proportional term drives the angle error to zero |
| rate reference | derivative term damps the rate error |
| acceleration reference | feedforward term applies I·α ahead of any error |

The three axes execute simultaneously with different target angles (φ → 20°,
θ → 10°, ψ → 30°), so each profile has a different coast duration and total
slew time.

## Navigation: Luenberger Observer

Angular velocities are estimated from angle measurements and known applied
torques using a Luenberger observer. The observer runs a linearized copy of the
single-axis dynamics with correction terms driven by angle measurement error:

```text
dθ̂/dt   = ω̂ + La·(θ_meas − θ̂)
I·dω̂/dt = τ + Lw·(θ_meas − θ̂)
```

A single pole location p = 2 rad/s parameterizes both gains, giving La = 2p = 4
and Lw = p²·I per axis. That places double observer poles at s = −2, which
converge within approximately 3 seconds.

The observer pole sits at roughly 3× the controller's closed-loop bandwidth,
satisfying the separation principle. The observer adds 6 differential states to
the system: 3 estimated angles and 3 estimated rates.

## Control: PD with Feedforward

The controller computes torque commands per axis:

```text
τi = −Kp_i·(θ_meas − θ_ref) − Kd_i·(ω̂ − ω_ref) + Ii·α_ref
```

The three terms serve distinct roles:

- **Proportional** — drives angle error to zero.
- **Derivative** — damps rate error using observer-estimated rates. Rate gyros
  are not modeled, so a measured rate is never available.
- **Feedforward** — applies the known inertia × commanded acceleration. This
  eliminates the tracking lag that a pure PD controller would exhibit during
  the coast phase of the slew.

Gains are chosen for overdamped response: ζ = Kd / (2·√(Kp·I)) = 1.41 on all
axes, with natural frequency ωn = √(Kp/I) = 0.707 rad/s. The overdamped tuning
keeps the response free of overshoot, which is typical for precision pointing
applications.

The controller reads angles straight from the star tracker and takes its rates
from the observer. That split is representative of missions where the rate gyro
is unavailable, noisy, or reserved for high-rate modes.

## Signal Flow

```text
[Trapezoidal Profiles ×3]
        │ angle_ref, rate_ref, accel_ref
        ▼
[Attitude Controller] ◄── estimated rates ── [Luenberger Observer]
        │ τx, τy, τz                                    ▲
        ▼                                               │
[Satellite Body] ── measured angles ────────────────────┘
```

Two of those signals feed a second consumer:

| Signal | Second consumer | Role there |
|---|---|---|
| measured angles | attitude controller | φ, θ, ψ feedback |
| applied torques | Luenberger observer | known inputs |

The controller torques reach both the plant and the observer, because the
observer needs the applied torques to propagate its internal dynamics model.

## Performance

At the default parameters, the system achieves:

| Metric | Value |
|---|---|
| Steady-state angle error | < 0.01° on all axes |
| Peak tracking error during slew | 0.56° |
| Observer convergence time | ~3 s |
| Observer rate estimation error after convergence | < 6×10⁻⁶ rad/s |
| Longest axis slew time (ψ = 30°) | ~19 s |
| Total simulation (settling + margin) | 40 s |
