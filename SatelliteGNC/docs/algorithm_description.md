# SatelliteGNC Algorithm Description Document

## 1. System Overview

A 6-DOF satellite attitude guidance, navigation, and control (GNC) system for a
CubeSat-class platform on low Earth orbit. The system performs 3-axis
rest-to-rest slew maneuvers using bipropellant reaction jets, with angular
velocity estimation from angle measurements only.

### Architecture

```
[TrapezoidalProfile ×3]  angle_ref, rate_ref, accel_ref
         │
         ▼
[AttitudeController] ◄── ω̂x, ω̂y, ω̂z ── [LuenbergerObserver]
         │  τx_cmd, τy_cmd, τz_cmd              ▲
         ▼                                       │
[ThrusterAllocator]                              │
         │  cmd1 ... cmd8                        │
         ▼                                       │
[ReactionJet ×8] ── F, τ (summed) ──┐           │
                                     ▼           │
                              [SatelliteBody6DOF]┘
                                 ── φ, θ, ψ → Controller + Observer
                                 ── τ_applied → Observer
```

### State Count

| Subsystem | Differential States | Algebraic Variables |
|-----------|-------------------|-------------------|
| SatelliteBody6DOF | 12 | 0 |
| LuenbergerObserver | 6 | 0 |
| TrapezoidalProfile ×3 | 0 | 9 |
| AttitudeController | 0 | 3 |
| ThrusterAllocator | 0 | 16 |
| ReactionJet ×8 | 0 | 32 |
| **Total** | **18** | **60** |

---

## 2. SatelliteBody6DOF

### 2.1 Inputs and Outputs

**Inputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| tau_x | τ_x | N·m | Body-frame torque about x-axis |
| tau_y | τ_y | N·m | Body-frame torque about y-axis |
| tau_z | τ_z | N·m | Body-frame torque about z-axis |
| fx | F_x | N | Body-frame force along x-axis |
| fy | F_y | N | Body-frame force along y-axis |
| fz | F_z | N | Body-frame force along z-axis |

**Outputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| phi_out | φ | rad | Roll angle (Euler 3-2-1) |
| theta_out | θ | rad | Pitch angle (Euler 3-2-1) |
| psi_out | ψ | rad | Yaw angle (Euler 3-2-1) |
| wx_out | ω_x | rad/s | Body-frame angular velocity about x |
| wy_out | ω_y | rad/s | Body-frame angular velocity about y |
| wz_out | ω_z | rad/s | Body-frame angular velocity about z |
| x_out | x | m | ECI position x-component |
| y_out | y | m | ECI position y-component |
| z_out | z | m | ECI position z-component |
| vx_out | v_x | m/s | ECI velocity x-component |
| vy_out | v_y | m/s | ECI velocity y-component |
| vz_out | v_z | m/s | ECI velocity z-component |

**Parameters:**

| Parameter | Symbol | Units | Default | Description |
|-----------|--------|-------|---------|-------------|
| Ixx | I_xx | kg·m² | 10.0 | Moment of inertia about x |
| Iyy | I_yy | kg·m² | 8.0 | Moment of inertia about y |
| Izz | I_zz | kg·m² | 6.0 | Moment of inertia about z |
| m | m | kg | 4.0 | Satellite mass |
| mu | μ | m³/s² | 3.986004418×10¹⁴ | Earth gravitational parameter |

### 2.2 Algorithm Description

The satellite is modeled as a rigid body with coupled translational and
rotational dynamics.

**Translational dynamics** (ECI frame):

$$\dot{\mathbf{r}} = \mathbf{v}$$

$$\dot{\mathbf{v}} = -\frac{\mu}{|\mathbf{r}|^3}\mathbf{r} + \frac{1}{m} R(\phi,\theta,\psi) \mathbf{F}_{body}$$

where R(φ,θ,ψ) is the 3-2-1 (yaw-pitch-roll) rotation matrix from body frame to
ECI:

$$R = R_z(\psi) \cdot R_y(\theta) \cdot R_x(\phi)$$

**Rotational dynamics** (body frame, Euler's equations on principal axes):

$$I_{xx} \dot{\omega}_x = \tau_x + (I_{yy} - I_{zz})\omega_y\omega_z + \tau_{gg,x}$$

$$I_{yy} \dot{\omega}_y = \tau_y + (I_{zz} - I_{xx})\omega_z\omega_x + \tau_{gg,y}$$

$$I_{zz} \dot{\omega}_z = \tau_z + (I_{xx} - I_{yy})\omega_x\omega_y + \tau_{gg,z}$$

**Gravity gradient torque** (coupling orbit position to attitude):

$$\boldsymbol{\tau}_{gg} = \frac{3\mu}{|\mathbf{r}|^5} (\mathbf{r}_{body} \times I \cdot \mathbf{r}_{body})$$

where r_body = R^T · r is the satellite position expressed in body frame, and I
is the diagonal inertia tensor.

**3-2-1 Euler angle kinematics:**

$$\dot{\phi} = \omega_x + (\omega_y \sin\phi + \omega_z \cos\phi)\tan\theta$$

$$\dot{\theta} = \omega_y \cos\phi - \omega_z \sin\phi$$

$$\dot{\psi} = (\omega_y \sin\phi + \omega_z \cos\phi) / \cos\theta$$

Note: singular at θ = ±90°. Valid for maneuvers with |θ| < 80°.

### 2.3 References

- Wertz, J.R., *Space Mission Engineering: The New SMAD*, Microcosm Press, 2011,
  Ch. 19 (Attitude Dynamics).
- Sidi, M.J., *Spacecraft Dynamics and Control*, Cambridge University Press,
  1997, Ch. 4.
- Markley, F.L. and Crassidis, J.L., *Fundamentals of Spacecraft Attitude
  Determination and Control*, Springer, 2014, Ch. 3.

### 2.4 Proposed Test Plan

| Test | Configuration | Expected Result | Tolerance |
|------|--------------|-----------------|-----------|
| Circular orbit propagation | r₀ = [6771 km, 0, 0], v₀ = [0, 7672.6, 0] m/s, zero attitude/rates/forces, simulate one orbital period (5545 s) | Position returns near initial; orbital energy ΔE/E < 10⁻¹⁰ | Position error < 100 m |
| Gravity gradient torque | Same orbit, satellite tilted 5° in pitch, zero external torques | Libration oscillation about y-axis at frequency √(3)·n where n = orbital rate; analytical torque τ_y = 3n²(I_xx − I_zz)sin(θ)cos(θ) | Torque matches analytical to < 10⁻¹⁰ relative error |
| Open-loop single-axis torque | No orbit (static position), constant τ_x = 0.1 N·m, 10 s | ω_x = τ_x·t/I_xx = 0.1 rad/s; φ = 0.5·τ_x·t²/I_xx = 0.5 rad | < 0.1% error vs analytical |

---

## 3. TrapezoidalProfile

### 3.1 Inputs and Outputs

**Inputs:** None (time-driven, parameterized).

**Outputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| angle_ref | θ_ref | rad | Reference angle |
| rate_ref | ω_ref | rad/s | Reference angular rate |
| accel_ref | α_ref | rad/s² | Reference angular acceleration |

**Parameters:**

| Parameter | Symbol | Units | Default | Description |
|-----------|--------|-------|---------|-------------|
| target_angle | θ_target | rad | 0.35 | Total slew angle |
| w_max | ω_max | rad/s | 0.035 | Maximum angular rate |
| a_max | α_max | rad/s² | 0.0087 | Maximum angular acceleration |

### 3.2 Algorithm Description

Generates a rest-to-rest trapezoidal velocity profile with three phases:

**Phase timing:**
- Ramp time: t_ramp = ω_max / α_max
- Coast angle: θ_ramp = ω_max² / (2·α_max)
- Coast time: t_coast = (θ_target − 2·θ_ramp) / ω_max
- Total time: t_total = 2·t_ramp + t_coast

**Phase 1 — Accelerate** (0 ≤ t < t_ramp):
- α_ref = +α_max
- ω_ref = α_max · t
- θ_ref = ½ · α_max · t²

**Phase 2 — Coast** (t_ramp ≤ t < t_ramp + t_coast):
- α_ref = 0
- ω_ref = ω_max
- θ_ref = θ_ramp + ω_max · (t − t_ramp)

**Phase 3 — Decelerate** (t_ramp + t_coast ≤ t < t_total):
- α_ref = −α_max
- ω_ref = ω_max − α_max · (t − t_ramp − t_coast)
- θ_ref = θ_ramp + ω_max · t_coast + ω_max · t_loc − ½ · α_max · t_loc²

where t_loc = t − t_ramp − t_coast.

**Phase 4 — Hold** (t ≥ t_total):
- α_ref = 0, ω_ref = 0, θ_ref = θ_target

Assumes trapezoidal regime: θ_target > ω_max²/α_max (sufficient angle for full
coast phase).

### 3.3 References

- ESA ECSS-E-ST-60-30C, *Space Engineering: Spacecraft Attitude and Orbit
  Control System (AOCS) Performance*, 2013.
- Wie, B., *Space Vehicle Dynamics and Control*, 2nd ed., AIAA, 2008, Ch. 7.4
  (Rest-to-Rest Slew Maneuvers).

### 3.4 Proposed Test Plan

| Test | Configuration | Expected Result | Tolerance |
|------|--------------|-----------------|-----------|
| Timing verification | θ_target = 0.35 rad, ω_max = 0.035 rad/s, α_max = 0.0087 rad/s² | t_ramp = 4.023 s, t_coast ≈ 5.954 s, t_total ≈ 14.0 s | < 0.1 s |
| Final angle | Same parameters, evaluate at t > t_total | θ_ref = θ_target exactly | < 10⁻¹⁰ rad |
| Rate continuity | Evaluate ω_ref at phase boundaries | No discontinuities in rate; rate peaks at ω_max | Continuous to solver tolerance |
| Acceleration profile | Evaluate α_ref over time | Piecewise constant: +α_max, 0, −α_max, 0 | Exact match at phase interiors |

---

## 4. AttitudeController

### 4.1 Inputs and Outputs

**Inputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| phi_ref | φ_ref | rad | Reference roll angle |
| theta_ref | θ_ref | rad | Reference pitch angle |
| psi_ref | ψ_ref | rad | Reference yaw angle |
| wx_ref | ω_x,ref | rad/s | Reference roll rate |
| wy_ref | ω_y,ref | rad/s | Reference pitch rate |
| wz_ref | ω_z,ref | rad/s | Reference yaw rate |
| ax_ff | α_x,ref | rad/s² | Feedforward roll acceleration |
| ay_ff | α_y,ref | rad/s² | Feedforward pitch acceleration |
| az_ff | α_z,ref | rad/s² | Feedforward yaw acceleration |
| phi_meas | φ_meas | rad | Measured roll angle |
| theta_meas | θ_meas | rad | Measured pitch angle |
| psi_meas | ψ_meas | rad | Measured yaw angle |
| wx_meas | ω̂_x | rad/s | Measured/estimated roll rate |
| wy_meas | ω̂_y | rad/s | Measured/estimated pitch rate |
| wz_meas | ω̂_z | rad/s | Measured/estimated yaw rate |

**Outputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| tau_x | τ_x | N·m | Commanded roll torque |
| tau_y | τ_y | N·m | Commanded pitch torque |
| tau_z | τ_z | N·m | Commanded yaw torque |

**Parameters:**

| Parameter | Symbol | Units | Default | Description |
|-----------|--------|-------|---------|-------------|
| Kp_x, Kp_y, Kp_z | K_p,i | N·m/rad | 5.0, 4.0, 3.0 | Proportional gains |
| Kd_x, Kd_y, Kd_z | K_d,i | N·m·s/rad | 20.0, 16.0, 12.0 | Derivative gains |
| Ixx_ff, Iyy_ff, Izz_ff | I_i,ff | kg·m² | 10.0, 8.0, 6.0 | Feedforward inertias |

### 4.2 Algorithm Description

Per-axis PD control law with acceleration feedforward:

$$\tau_i = -K_{p,i}(\theta_{meas,i} - \theta_{ref,i}) - K_{d,i}(\hat{\omega}_i - \omega_{ref,i}) + I_{i,ff} \cdot \alpha_{ref,i}$$

The three terms serve distinct roles:
- **Proportional** (−K_p · e_θ): drives angle error to zero.
- **Derivative** (−K_d · e_ω): damps rate error. Uses observer-estimated rates,
  not measured rates directly.
- **Feedforward** (+I_ff · α_ref): applies the known inertia × commanded
  acceleration. Eliminates steady-state tracking lag during the coast phase of
  trapezoidal profiles.

**Closed-loop characteristic equation** (per axis, without feedforward,
linearized):

$$I \ddot{e} + K_d \dot{e} + K_p e = 0$$

- Natural frequency: ω_n = √(K_p / I)
- Damping ratio: ζ = K_d / (2√(K_p · I))

Default gains give ω_n = 0.707 rad/s and ζ = 1.41 (overdamped) on all axes.

Without feedforward, tracking a ramp rate reference produces steady-state error
e_ss = K_d · ω_max / K_p. The feedforward term reduces this by providing the
expected torque directly.

### 4.3 References

- Franklin, G.F., Powell, J.D., and Emami-Naeini, A., *Feedback Control of
  Dynamic Systems*, 8th ed., Pearson, 2019, Ch. 7 (PD Control).
- Wie, B., *Space Vehicle Dynamics and Control*, 2nd ed., AIAA, 2008, Ch. 7.3
  (PD Attitude Control).

### 4.4 Proposed Test Plan

| Test | Configuration | Expected Result | Tolerance |
|------|--------------|-----------------|-----------|
| Step response (no feedforward) | Step commands φ=10°, θ=5°, ψ=15°; ω_ref = 0, α_ref = 0 | Overdamped settling, no overshoot, settle within 12 s | < 1% of target at t = 30 s |
| Feedforward tracking | Trapezoidal profile with feedforward enabled | Peak tracking error < 1° during coast phase | < 1° |
| Steady-state accuracy | After maneuver completes, all rates at zero | Angle errors < 0.01° | < 0.01° |

---

## 5. LuenbergerObserver

### 5.1 Inputs and Outputs

**Inputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| phi_meas | φ_meas | rad | Measured roll angle |
| theta_meas | θ_meas | rad | Measured pitch angle |
| psi_meas | ψ_meas | rad | Measured yaw angle |
| tau_x | τ_x | N·m | Applied roll torque (known) |
| tau_y | τ_y | N·m | Applied pitch torque (known) |
| tau_z | τ_z | N·m | Applied yaw torque (known) |

**Outputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| phi_hat | φ̂ | rad | Estimated roll angle |
| theta_hat | θ̂ | rad | Estimated pitch angle |
| psi_hat | ψ̂ | rad | Estimated yaw angle |
| wx_hat | ω̂_x | rad/s | Estimated roll rate |
| wy_hat | ω̂_y | rad/s | Estimated pitch rate |
| wz_hat | ω̂_z | rad/s | Estimated yaw rate |

**Parameters:**

| Parameter | Symbol | Units | Default | Description |
|-----------|--------|-------|---------|-------------|
| Ixx, Iyy, Izz | I_i | kg·m² | 10.0, 8.0, 6.0 | Plant inertias (must match) |
| p | p | rad/s | 2.0 | Observer pole location |
| La_x, La_y, La_z | L_a,i | 1/s | 4.0 | Angle correction gains |
| Lw_x, Lw_y, Lw_z | L_ω,i | N·m/rad | 40.0, 32.0, 24.0 | Rate correction gains |

### 5.2 Algorithm Description

Per-axis Luenberger observer using a linearized copy of the single-axis dynamics
with correction terms driven by angle measurement error:

$$\dot{\hat{\theta}}_i = \hat{\omega}_i + L_{a,i}(\theta_{meas,i} - \hat{\theta}_i)$$

$$I_i \dot{\hat{\omega}}_i = \tau_i + L_{\omega,i}(\theta_{meas,i} - \hat{\theta}_i)$$

The observer is a dynamic system with 6 differential states (3 estimated angles
+ 3 estimated rates).

**Gain selection:** For double observer poles at s = −p, the gains are:

$$L_{a,i} = 2p$$

$$L_{\omega,i} = p^2 \cdot I_i$$

This places the observer error dynamics at eigenvalues s = −p (repeated), giving
a time constant of 1/p. At p = 2 rad/s, convergence occurs within approximately
3 seconds (3/p ≈ 1.5 s to 95%).

**Separation principle:** The observer pole p should be placed at 3–5× the
controller closed-loop bandwidth to ensure the estimation error decays before
the controller responds. With controller ω_n = 0.707 rad/s, the observer at p =
2.0 rad/s provides approximately 3× separation.

The observer uses a linearized model (no gyroscopic cross-coupling terms). This
is valid for small angular velocities typical of the maneuver envelope (ω <
0.035 rad/s).

### 5.3 References

- Luenberger, D.G., "Observing the State of a Linear System," *IEEE Transactions
  on Military Electronics*, Vol. 8, No. 2, 1964, pp. 74–80.
- Sidi, M.J., *Spacecraft Dynamics and Control*, Cambridge University Press,
  1997, Ch. 9.3 (State Estimation).

### 5.4 Proposed Test Plan

| Test | Configuration | Expected Result | Tolerance |
|------|--------------|-----------------|-----------|
| Convergence from zero IC | Observer starts at zero, plant has initial ω_x = 0.01 rad/s | Estimation error < 1% of initial within 3 s | |ω̂ − ω| < 10⁻⁴ rad/s at t = 3 s |
| Tracking during maneuver | Full closed-loop with trapezoidal profile | Observer tracks actual rates throughout; peak estimation error < 5% of ω_max | < 0.002 rad/s |
| Steady-state estimation | After maneuver settles | Estimation error < 10⁻⁵ rad/s | < 10⁻⁵ rad/s |

---

## 6. ReactionJet

### 6.1 Inputs and Outputs

**Inputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| cmd | u | — | Normalized thrust command (−1 to +1) |

**Outputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| fx_out | F_x | N | Body-frame force x-component |
| fy_out | F_y | N | Body-frame force y-component |
| fz_out | F_z | N | Body-frame force z-component |
| tx_out | τ_x | N·m | Body-frame torque x-component |
| ty_out | τ_y | N·m | Body-frame torque y-component |
| tz_out | τ_z | N·m | Body-frame torque z-component |

**Parameters:**

| Parameter | Symbol | Units | Default | Description |
|-----------|--------|-------|---------|-------------|
| rx, ry, rz | r_x, r_y, r_z | m | 0, 0, 0 | Mounting position from CoM |
| dx, dy, dz | d_x, d_y, d_z | — | 1, 0, 0 | Thrust direction (unit vector) |
| F_max | F_max | N | 0.1 | Maximum thrust magnitude |

### 6.2 Algorithm Description

Models a single bipropellant (bidirectional) thruster:

**Command clamping:**

$$u_{clamp} = \text{clamp}(u, -1, +1)$$

**Force production:**

$$\mathbf{F} = u_{clamp} \cdot F_{max} \cdot \hat{\mathbf{d}}$$

where d̂ = (d_x, d_y, d_z) is the thrust direction vector.

**Torque from offset mounting:**

$$\boldsymbol{\tau} = \mathbf{r} \times \mathbf{F}$$

where r = (r_x, r_y, r_z) is the thruster position relative to the center of
mass. Expanded:

$$\tau_x = r_y F_z - r_z F_y$$
$$\tau_y = r_z F_x - r_x F_z$$
$$\tau_z = r_x F_y - r_y F_x$$

A thruster at the center of mass (r = 0) produces force but no torque. A
thruster offset from the CoM produces both force and torque simultaneously.

### 6.3 References

- Wertz, J.R., *Space Mission Engineering: The New SMAD*, Microcosm Press, 2011,
  Ch. 17 (Propulsion).
- Sutton, G.P. and Biblarz, O., *Rocket Propulsion Elements*, 9th ed., Wiley,
  2017, Ch. 4.

### 6.4 Proposed Test Plan

| Test | Configuration | Expected Result | Tolerance |
|------|--------------|-----------------|-----------|
| Force only (CoM mounted) | r = [0,0,0], d = [1,0,0], cmd = 0.5 | F = [0.05, 0, 0] N, τ = [0, 0, 0] N·m | Exact |
| Force + torque (offset) | r = [0.15, 0.10, 0], d = [0,0,1], cmd = 0.5 | F = [0, 0, 0.05] N, τ = [0.005, −0.0075, 0] N·m | Exact |
| Positive saturation | cmd = 2.0 | cmd_clamped = 1.0, F = F_max · d̂ | Exact |
| Negative command | cmd = −0.5 | F = −0.5 · F_max · d̂ (reverse thrust) | Exact |

---

## 7. ThrusterAllocator

### 7.1 Inputs and Outputs

**Inputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| Fx_cmd | F_x,cmd | N | Commanded body-frame x-force |
| Fy_cmd | F_y,cmd | N | Commanded body-frame y-force |
| Fz_cmd | F_z,cmd | N | Commanded body-frame z-force |
| tau_x_cmd | τ_x,cmd | N·m | Commanded body-frame x-torque |
| tau_y_cmd | τ_y,cmd | N·m | Commanded body-frame y-torque |
| tau_z_cmd | τ_z,cmd | N·m | Commanded body-frame z-torque |

**Outputs:**

| Signal | Symbol | Units | Description |
|--------|--------|-------|-------------|
| cmd1 ... cmd8 | u_1 ... u_8 | — | Normalized jet commands (−1 to +1) |

**Parameters:**

| Parameter | Symbol | Units | Default | Description |
|-----------|--------|-------|---------|-------------|
| F_max | F_max | N | 0.1 | Maximum thrust per jet (for normalization) |

### 7.2 Algorithm Description

Maps a 6-DOF force/torque command vector to 8 individual jet thrust commands
using the Moore-Penrose pseudoinverse of the thruster configuration matrix.

**Configuration matrix B** (6×8):

The B matrix maps the thrust vector T = [T_1, ..., T_8]^T to the net
force/torque vector w = [F_x, F_y, F_z, τ_x, τ_y, τ_z]^T:

$$\mathbf{w} = B \cdot \mathbf{T}$$

Each column j of B is constructed from jet j's direction d_j and position r_j:

$$B_{1:3,j} = \mathbf{d}_j, \quad B_{4:6,j} = \mathbf{r}_j \times \mathbf{d}_j$$

**Pseudoinverse allocation:**

$$\mathbf{T} = B^+ \cdot \mathbf{w}_{cmd}$$

where B⁺ = B^T(BB^T)⁻¹ is the Moore-Penrose pseudoinverse. This minimizes ||T||₂
(minimum-energy allocation) among all solutions that achieve the commanded
force/torque.

**Normalization:**

$$u_j = T_j / F_{max}$$

The 8-jet configuration (4 z-firing + 2 y-firing + 2 x-firing on edges of a
0.3×0.2×0.1 m body) yields rank(B) = 6, confirming full 6-DOF controllability
with 2 degrees of redundancy.

Note: The pseudoinverse may produce commands |u_j| > 1 if the commanded
force/torque exceeds actuator capacity. The individual ReactionJet components
clamp to [−1, 1], which introduces allocation error under saturation.

### 7.3 References

- Durham, W.C., "Constrained Control Allocation," *Journal of Guidance, Control,
  and Dynamics*, Vol. 16, No. 4, 1993, pp. 717–725.
- Wie, B., *Space Vehicle Dynamics and Control*, 2nd ed., AIAA, 2008, Ch. 7.6
  (Thruster Control Allocation).

### 7.4 Proposed Test Plan

| Test | Configuration | Expected Result | Tolerance |
|------|--------------|-----------------|-----------|
| Pure yaw torque | τ_z = 0.01 N·m, all others zero | Net output: F = [0,0,0], τ = [0,0,0.01]; jets 1–4 off, jets 5–8 active | Force < 10⁻¹⁰ N, torque error < 10⁻¹⁰ N·m |
| Pure force | F_z = 0.1 N, all others zero | Net output: F = [0,0,0.1], τ = [0,0,0]; jets 1–4 each at cmd = 0.25/F_max | Torque < 10⁻¹⁰ N·m |
| Combined force + torque | F_x = 0.05, τ_y = 0.005 | Net output matches command | < 10⁻⁸ relative error |
| Rank verification | Compute rank(B) from configuration | rank = 6 | Exact |

---

## 8. Integrated System (TestFullGNC6DOF)

### 8.1 Inputs and Outputs

**System-level inputs (set as parameters):**

| Parameter | Value | Units | Description |
|-----------|-------|-------|-------------|
| φ_target | 0.3491 (20°) | rad | Target roll angle |
| θ_target | 0.1745 (10°) | rad | Target pitch angle |
| ψ_target | 0.5236 (30°) | rad | Target yaw angle |
| ω_max | 0.0349 (2°/s) | rad/s | Maximum slew rate |
| α_max | 0.00873 (0.5°/s²) | rad/s² | Maximum slew acceleration |

**Initial conditions:**

| State | Value | Units | Description |
|-------|-------|-------|-------------|
| pos_x | 6,771,000 | m | LEO circular orbit radius |
| pos_y, pos_z | 0 | m | Orbit plane |
| vel_y | 7672.6 | m/s | Circular orbit velocity |
| vel_x, vel_z | 0 | m/s | |
| φ, θ, ψ | 0 | rad | Initial attitude |
| ω_x, ω_y, ω_z | 0 | rad/s | Initially at rest |
| Observer states | 0 | — | Observer starts at zero |

**System-level outputs (monitored):**

| Signal | Description |
|--------|-------------|
| sat.phi, sat.theta, sat.psi | Actual Euler angles |
| sat.wx, sat.wy, sat.wz | Actual angular velocities |
| sat.pos_x, sat.pos_y, sat.pos_z | Orbital position |
| obs.wx_hat, obs.wy_hat, obs.wz_hat | Estimated rates |
| alloc.cmd1 ... alloc.cmd8 | Jet commands |

### 8.2 Algorithm Description

The integrated system executes a 3-axis attitude repointing maneuver on a
CubeSat in 400 km LEO. The signal flow is:

1. **Guidance:** Three independent TrapezoidalProfile instances generate
   per-axis angle, rate, and acceleration references.

2. **Navigation:** The LuenbergerObserver estimates angular velocities from
   measured angles (star tracker) and known applied torques. Convergence within
   ~3 s.

3. **Control:** The AttitudeController computes torque commands from angle error
   (measured), rate error (estimated), and acceleration feedforward.

4. **Allocation:** The ThrusterAllocator maps the 3-axis torque command (plus
   zero force command) to 8 jet commands via pseudoinverse.

5. **Actuation:** Eight ReactionJet instances produce body-frame forces and
   torques from the allocated commands, with saturation at ±F_max.

6. **Plant:** The SatelliteBody6DOF integrates the net forces and torques,
   propagating both the orbit (Keplerian + thrust) and attitude (Euler's
   equations + gravity gradient).

7. **Feedback:** Satellite angle measurements feed back to both the controller
   and observer. Applied torques feed to the observer.

The maneuver completes in ~19 s (longest axis: ψ = 30°) with all axes settling
by t = 30 s. The orbit radius remains constant to km-level precision over the 40
s simulation.

### 8.3 References

All references from individual component sections apply. Additionally:

- Fortescue, P., Swinerd, G., and Stark, J., *Spacecraft Systems Engineering*,
  4th ed., Wiley, 2011, Ch. 9 (Attitude and Orbit Control).
- ESA ECSS-E-ST-60-30C, *Space Engineering: AOCS Performance*, 2013.

### 8.4 Proposed Test Plan

| Test | Configuration | Expected Result | Tolerance |
|------|--------------|-----------------|-----------|
| Attitude settling | Default parameters, simulate 40 s | φ → 20°, θ → 10°, ψ → 30° | < 0.01° error at t = 40 s |
| Orbit maintenance | Monitor |r| during maneuver | |r| stays within 1 km of initial | < 1 km drift |
| Observer convergence | Monitor ω̂ − ω during maneuver | Error < 10⁻⁵ rad/s after t = 3 s | < 10⁻⁵ rad/s |
| Peak tracking error | Monitor max |θ_ref − θ_meas| during slew | < 1° with feedforward | < 1° |
| Jet saturation | Verify all |cmd_j| ≤ 1 during maneuver | No saturation with F_max = 0.5 N | All |cmd| ≤ 1 |
| Energy conservation (orbit) | Compare orbital energy at t = 0 and t = 40 | ΔE/E < 10⁻⁸ (thrust forces are small) | < 10⁻⁸ |
