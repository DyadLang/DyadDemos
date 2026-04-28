# 3-DOF Satellite Attitude GNC Closed-Loop System

## Overview

This system implements a closed-loop attitude control architecture for a rigid-body satellite with 3 rotational degrees of freedom. The architecture follows a standard GNC decomposition: guidance (slew profile generation), navigation (state estimation), and control (torque computation).



\### Plant: Rigid Body Dynamics



The satellite is modeled using Euler's rotational equations of motion on principal axes:



$$

Ixx·ω̇x = τx + (Iyy − Izz)·ωy·ωz
Iyy·ω̇y = τy + (Izz − Ixx)·ωz·ωx
Izz·ω̇z = τz + (Ixx − Iyy)·ωx·ωy

$$
Attitude kinematics use the 3-2-1 (yaw-pitch-roll) Euler angle convention. The gyroscopic cross-coupling terms (ωi·ωj products) are retained — they become significant during multi-axis maneuvers when angular rates are non-negligible simultaneously.

The plant has 6 differential states: 3 angular velocities (ωx, ωy, ωz) and 3 Euler angles (φ, θ, ψ). Inertia parameters are representative of a CubeSat-class platform (Ixx = 10, Iyy = 8, Izz = 6 kg·m²).





Guidance: Trapezoidal Velocity Profile
Each axis has an independent rest-to-rest slew profile that respects rate and acceleration constraints:

ω\_max = 0.0349 rad/s (2°/s)
α\_max = 0.00873 rad/s² (0.5°/s²)
The profile has three phases: constant acceleration to ω\_max, coast at ω\_max, constant deceleration to rest. This is the standard AOCS slew profile (ESA ECSS-E-ST-60-30C). Each profile outputs three signals: angle reference, rate reference, and acceleration reference. The rate and acceleration outputs enable the controller to perform rate error damping and torque feedforward.

The three axes execute simultaneously with different target angles (φ → 20°, θ → 10°, ψ → 30°), so each profile has a different coast duration and total slew time.





Navigation: Luenberger Observer
Angular velocities are estimated from angle measurements and known applied torques using a Luenberger observer. The observer runs a linearized copy of the single-axis dynamics with correction terms driven by angle measurement error:

dθ̂/dt = ω̂ + La·(θ\_meas − θ̂)
I·dω̂/dt = τ + Lw·(θ\_meas − θ̂)
Gains are parameterized by a single pole location p = 2 rad/s, giving La = 2p = 4 and Lw = p²·I per axis. This places double observer poles at s = −2, yielding convergence within approximately 3 seconds. The observer pole is placed at roughly 3× the controller's closed-loop bandwidth to satisfy the separation principle.

The observer adds 6 differential states (3 estimated angles + 3 estimated rates) to the system.





Control: PD with Feedforward
The controller computes torque commands per axis:

τi = −Kp\_i·(θ\_meas − θ\_ref) − Kd\_i·(ω̂ − ω\_ref) + Ii·α\_ref

The three terms serve distinct roles:

Proportional: drives angle error to zero
Derivative: damps rate error using observer-estimated rates (not measured rates, since rate gyros are not modeled)
Feedforward: applies the known inertia × commanded acceleration, eliminating the tracking lag that a pure PD controller would exhibit during the coast phase of the slew
Gains are chosen for overdamped response: ζ = Kd / (2·√(Kp·I)) = 1.41 on all axes, with natural frequency ωn = √(Kp/I) = 0.707 rad/s. The overdamped tuning avoids overshoot, which is typical for precision pointing applications.

Note that the controller uses measured angles directly (assuming a star tracker or similar sensor) but uses observer-estimated rates rather than measured rates. This is representative of missions where a rate gyro is either unavailable, noisy, or reserved for high-rate modes.





Signal Flow
\[Trapezoidal Profiles ×3]
│ angle\_ref, rate\_ref, accel\_ref
▼
\[Attitude Controller] ◄── estimated rates ── \[Luenberger Observer]
│ τx, τy, τz                                    ▲
▼                                                │
\[Satellite Body] ── measured angles ─────────────────┘
── measured angles ──► \[Controller: φ,θ,ψ feedback]
── applied torques ──► \[Observer: known inputs]
The controller torques are fed to both the plant and the observer — the observer requires knowledge of applied torques to propagate its internal dynamics model.

Performance
At the default parameters, the system achieves:

Metric	Value
Steady-state angle error	< 0.01° on all axes
Peak tracking error during slew	0.56°
Observer convergence time	\~3 s
Observer rate estimation error after convergence	< 6×10⁻⁶ rad/s
Longest axis slew time (ψ = 30°)	\~19 s
Total simulation (settling + margin)	40 s

