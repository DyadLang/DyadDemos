# HL-20 Engineering Spec

All data below is extracted from NASA TM-107580, NASA TM-4302, and the HL20 DAVE-ML aero database. This file replaces reading those documents directly.

---

## 1. Vehicle Parameters

| Parameter | Value | Unit | Notes |
|-----------|-------|------|-------|
| mass | 8664.1 | kg | (19,100 lbs) |
| Ixx | 10186.272 | kg·m² | (7,512 slug·ft²) |
| Iyy | 45557.464 | kg·m² | (33,594 slug·ft²) |
| Izz | 48333.264 | kg·m² | (35,644 slug·ft²) |
| g | 9.81 | m/s² | |
| S_ref | 286.45 | ft² | Reference area |
| CBAR | 28.24 | ft | Reference chord |
| BSPAN | 13.89 | ft | Reference span |
| Xcg | 0.555 | fraction | CG location (fraction of body length from nose) |
| XRP | 0.54 | fraction | Moment reference point (wind tunnel data) |

---

## 2. Frame Conventions

- **Inertial frame**: NED (North-East-Down). Axis 1=North, 2=East, 3=Down.
- **Altitude**: `alt = −pos_3` (positive up, since pos_3 is positive down in NED).
- **Quaternion**: Scalar-first `[qw, qx, qy, qz]`, body→inertial rotation.
- **Body frame**: X-forward, Y-right, Z-down.
- **Units**: All dynamics in SI (m, kg, N, rad/s). Aero interfaces and controllers use imperial (ft, fps, psf, deg, deg/s). Conversions happen at component boundaries.

### Interface Contracts

| Component | Forces/Velocities | Torques/Rates |
|-----------|-------------------|---------------|
| RigidBody6DOF | Inertial NED | Body frame |
| AeroForceBuilder | Force output: Inertial NED | Torque output: Body |
| FlightState | Input: Inertial NED velocity | Output: degrees |
| HL20Aero | — | Body rates input (rad/s) |

`RigidBody6DOF` adds gravity internally (`+mass*g` in the NED-down direction on axis 3). External forces do **not** include gravity.

---

## 3. RigidBody6DOF Equations

Standard flat-earth 6DOF with quaternion orientation. No products of inertia.

**Parameters:** mass, Jxx, Jyy, Jzz, g.

**Inputs** (RealInput): F1, F2, F3 (external forces, inertial NED, N), T1, T2, T3 (external torques, body frame, N·m).

**Outputs** (RealOutput): pos_1, pos_2, pos_3 (position, m), vel_1, vel_2, vel_3 (velocity, m/s), qw, qx, qy, qz (quaternion), omega_1, omega_2, omega_3 (body angular rates, rad/s).

**Internal state variables:** p1, p2, p3 (position), v1, v2, v3 (velocity), q0, q1, q2, q3 (quaternion), w1, w2, w3 (angular rates).

**Position kinematics:**
```
d(pos)/dt = vel    (inertial NED)
```

**Translational dynamics** (inertial frame, gravity added internally):
```
mass * d(v1)/dt = F1_ext
mass * d(v2)/dt = F2_ext
mass * d(v3)/dt = F3_ext + mass * g
```

**Quaternion kinematics** (body→inertial, scalar-first q=[q0,q1,q2,q3]):
```
d(q0)/dt = 0.5 * (-q1*w1 - q2*w2 - q3*w3)
d(q1)/dt = 0.5 * ( q0*w1 + q2*w3 - q3*w2)
d(q2)/dt = 0.5 * ( q0*w2 - q1*w3 + q3*w1)
d(q3)/dt = 0.5 * ( q0*w3 + q1*w2 - q2*w1)
```

**Euler's equations** (body frame, diagonal inertia):
```
Ixx * d(w1)/dt = T1 + (Iyy - Izz) * w2 * w3
Iyy * d(w2)/dt = T2 + (Izz - Ixx) * w3 * w1
Izz * d(w3)/dt = T3 + (Ixx - Iyy) * w1 * w2
```

---

## 4. Atmosphere Model

Uses `DyadData.DyadTimeseries` + `BlockComponents.Tables.Interpolation` with CSV files:
- `atmos_sigma.csv`: altitude (ft) → density ratio σ (sigma = ρ/ρ_SL)
- `atmos_sos.csv`: altitude (ft) → speed of sound (m/s)

Interpolation: linear, constant extrapolation.

---

## 5. FlightState Computation

Converts inertial NED velocity + quaternion to body-frame velocity, aero angles, and Euler angles.

**Inverse quaternion rotation** (inertial→body, using body→inertial quaternion):
```
u_body = (1 - 2(qy² + qz²)) * v1 + 2(qx*qy + qw*qz) * v2 + 2(qx*qz - qw*qy) * v3
v_body = 2(qx*qy - qw*qz) * v1 + (1 - 2(qx² + qz²)) * v2 + 2(qy*qz + qw*qx) * v3
w_body = 2(qx*qz + qw*qy) * v1 + 2(qy*qz - qw*qx) * v2 + (1 - 2(qx² + qy²)) * v3
```

**Airspeed:**
```
v_scalar = sqrt(u² + v² + w² + ε)     (ε = 1e-6 for numerical safety)
```

**Aero angles (degrees):**
```
alpha = atan2(w_body, u_body) * (180/π)
beta  = atan2(v_body, sqrt(u_body² + w_body²)) * (180/π)
```

**Euler angles from quaternion (degrees):**
```
phi   = atan2(2(qw*qx + qy*qz), 1 - 2(qx² + qy²)) * (180/π)
theta = asin(clamp(2(qw*qy - qz*qx), -1, 1)) * (180/π)
psi   = atan2(2(qw*qz + qx*qy), 1 - 2(qy² + qz²)) * (180/π)
```

---

## 6. Aerodynamic Force Builder (TM-4302 eqs 7–12)

Converts nondimensional aero coefficients (body-axis CX, CY, CZ, Cl, Cm, Cn from HL20Aero) to dimensional forces and moments, then rotates forces to inertial NED.

**Unit conversion:**
```
S_m2   = S_ref / ft_per_m²
CBAR_m = CBAR / ft_per_m
BSPAN_m = BSPAN / ft_per_m
qbar_Pa = qbar_psf * 47.880259
```

**Body-frame forces (N):**
```
Fx_b = qbar_Pa * S_m2 * CX
Fy_b = qbar_Pa * S_m2 * CY
Fz_b = qbar_Pa * S_m2 * CZ
```

**Body-frame moments (N·m) with CG offset correction:**
```
dxcg = Xcg - XRP    (fractional offset, positive = CG aft of ref point)

Mx_b = qbar_Pa * S_m2 * BSPAN_m * Cl
My_b = qbar_Pa * S_m2 * CBAR_m  * Cm  + dxcg * CBAR_m * Fz_b
Mz_b = qbar_Pa * S_m2 * BSPAN_m * Cn  - dxcg * CBAR_m * Fy_b
```
The CG offset is along the body x-axis only: `ΔM = r × F = [0, +dxcg·c·Fz, −dxcg·c·Fy]`.

**Rotate body forces to inertial NED** using quaternion rotation matrix R (body→inertial):
```
F_inertial = R * F_body
```
where R is the standard quaternion rotation matrix from q=[qw,qx,qy,qz].

**Output Fz_body** separately for NZ computation.

---

## 7. HL20Aero Model (Pre-provided)

`dyad/shared/HL20Aero.dyad` and the registered symbolic functions in `src/shared_utils.jl` are **pre-provided**. Do not modify them or rebuild the coefficient buildup. Instantiate the component as `ChallengeComponent.shared.HL20Aero(...)` from inside your `HL20Vehicle.dyad` (and `TestAeroSweep.dyad`) and wire its ports.

### Interface (for wiring into HL20Vehicle)

**Inputs:**
- `alpha_deg`, `beta_deg`: aero angles (deg)
- `mach`: Mach number
- `vrw_fps`: relative wind velocity (fps)
- `hob`: height over body span (= alt_ft / BSPAN)
- `pb`, `qb`, `rb`: body angular rates (rad/s)
- `DBFUL`, `DBFUR`, `DBFLL`, `DBFLR`, `DWFL`, `DWFR`, `DRUD`: surface deflections (deg)

**Parameters (defaults baked in):**
- `Cm_bias = 0.006449`: trim correction added to `Cm` to balance the pitching moment at the NASA reference trim condition.

**Outputs (body-axis):** `CX`, `CY`, `CZ`, `Cl`, `Cm`, `Cn`. The grader checks these names.

### Registered Symbolic Functions (FYI, used inside `HL20Aero.dyad`)

Loaded by the project module from the DAVE-ML files in `assets/shared/` and exposed as `ChallengeComponent.<name>`:

| Function | Signature | Purpose |
|----------|-----------|---------|
| `hl20_poly1d` | `(group_idx, alpha_deg, x)` | 1D polynomial table |
| `hl20_poly2dr` | `(group_idx, alpha_deg, defl, mach)` | 2D table, referenced breakpoints |
| `hl20_poly2de` | `(group_idx, alpha_deg, defl, mach)` | 2D table, embedded breakpoints |

Index accessors (called at model-construction time, return constant `Integer`s):
- `ChallengeComponent.idx1d("CL0A")`
- `ChallengeComponent.grp2dr("CLBFLL")`
- `ChallengeComponent.grp2de("CLRUD")`

---

## 8. HL20Vehicle Integration

The vehicle wires together: RigidBody6DOF, Atmosphere1976, FlightState, HL20Aero, AeroForceBuilder.

### Key computations inside the vehicle

```
alt_ft    = -body.pos_3 * ft_per_m
vrw_fps   = v_scalar * ft_per_m
mach      = v_scalar / (sos_mps + 0.01)
qbar_psf  = 0.5 * 0.002378 * sigma * vrw_fps²      (ρ_SL = 0.002378 slug/ft³)
hob       = alt_ft / (BSPAN + 0.01)
```

### Controller Feedback Outputs

| Signal | Definition |
|--------|------------|
| ALPHA_DEG | angle of attack (deg) |
| BETADEG | sideslip (deg) |
| BETADOT | p·sin(α) − r·cos(α), converted to deg/s |
| MACH_out | Mach number |
| PDEG, QDEG, RDEG | body rates (deg/s) = ω × (180/π) |
| SINPHI, COSPHI | sin/cos of Euler bank angle φ |
| COSTHE | cos of Euler pitch angle θ |
| QBAR | dynamic pressure (psf) |
| EAS | equivalent airspeed (knots) = vrw_fps × √σ / 1.6878 |
| NZ | aero normal load factor = −Fz_body / (mass × g) |
| V_FPS | total airspeed (fps) |

---

## 9. Control Laws (TM-107580 §4.1, Manual SAS Mode)

### 9.1 Pitch Control (NZQ)

**Parameters:**
```
RSQLAW = 0.6    COLMAX = 7.5    GDQDC = 5.0     GDEGCM = -3.0
GQBAR1 = 179.0  FQBA = 1.0      FQBB = 1.0      FQBT = 0.50
FNZA = 0.10     FNZB = 1.0      FNZT = 0.30     FATT = 0.45
```

**Stick shaping:**
```
COLSHC = (1 - RSQLAW) * DCPILOT + RSQLAW * DCPILOT * |DCPILOT| / COLMAX
```

**Gain scheduling:**
```
GQBAR = clamp(GQBAR1 / (QBAR + 0.1), 0.2, 2.0)
GMACH = clamp(5.0 * MACH - 4.0, 1.0, 6.0)
GQ    = GQBAR * GMACH
```

**Pitch rate path** (lead-lag filter `(FQBA·s + FQBB)/(FQBT·s + 1)`):
```
TANPHIL = clamp(SINPHI / (COSPHI + 1e-6), -1.0, 1.0)
QCOORD  = QDEG - RDEG * TANPHIL
d(QDEGF)/dt = (QCOORD - QDEGF) / FQBT
QDEG_filtered = (FQBA/FQBT) * QCOORD + (FQBB - FQBA/FQBT) * QDEGF
DEQ = GQ * (QDEG_filtered - GDQDC * COLSHC)
```

**NZ feedback → gamma-dot estimate** (lead-lag filter `(FNZA·s + FNZB)/(FNZT·s + 1)`):
```
COORDNZ = clamp(COSTHE / (COSPHI + 1e-6), 0.90, 1.41)
GAMDOT  = 1843.0 * (NZ - COORDNZ) / (VTOTALI + 0.1)
d(GAMDOTF)/dt = (GAMDOT - GAMDOTF) / FNZT
GAMDOT_filtered = (FNZA/FNZT) * GAMDOT + (FNZB - FNZA/FNZT) * GAMDOTF
DEGC = -GDEGCM * GQ * GAMDOT_filtered
```

**Auto trim** (lagged elevator feedback, τ = FATT):
```
d(DETRIM)/dt = (DLEDEG - DETRIM) / FATT
```

**Total elevator command:**
```
DECMD = DEQ + DEGC + DETRIM
```

**State variables:** QDEGF, GAMDOTF, DETRIM (3 differential states).

**Inputs:** DCPILOT, QDEG, RDEG, NZ, SINPHI, COSPHI, COSTHE, DLEDEG, QBAR, MACH, VTOTALI.

**Output:** DECMD.

### 9.2 Roll Control

**Parameters:**
```
GDADWL = 0.67    GDADWR = 0.67    GDAP = -1.4
```

**Equations:**
```
DADIR = GDADWL * DWPILOT   (if DWPILOT < 0)
DADIR = GDADWR * DWPILOT   (if DWPILOT >= 0)
DAP   = GDAP * PDEG
DACMD = clamp(DADIR + DAP, -30, 30)
```

No state variables. Inputs: DWPILOT, PDEG. Output: DACMD.

### 9.3 Yaw Control

**Parameters:**
```
GDRDP = -11.1    GDRDA = -0.01    GRSAS = 40.0    TAU_WASH = 2.0
```

**Equations:**
```
DRDIR = GDRDP * DPPILOT
d(RBWASH)/dt = (RDEG - RBWASH) / TAU_WASH
GDRDAX = GDRDA  (if MACH > 0.9, else 0)
DRSAS  = GDRDAX * DACMD + GRSAS * (RDEG - RBWASH) * 0.01745
DRCMD  = DRDIR + DRSAS
```

One state variable: RBWASH. Inputs: DPPILOT, RDEG, DACMD, MACH. Output: DRCMD.

### 9.4 Speed Control

**Parameters:**
```
DSBSF1 = 0.0    DSBSF2 = 0.0375
```

**Equations (manual mode, no autospeed):**
```
DSBDIR = DSBSF1 * DLSBCOM + DSBSF2 * DLSBCOM²
DSBCMD = DSBDIR
```

No state variables. Input: DLSBCOM. Output: DSBCMD.

---

## 10. Control Surface Mixer (TM-107580, SUBROUTINE PLSURF, Subsonic Only)

Inputs: DECMD, DACMD, DRCMD, DSBCMD.
Outputs: 7 actuated surface positions (DLE, DRE, DUL, DUR, DLL, DLR, DR).

### 10.1 Command Limiting

```
DECMDL  = clamp(DECMD, -30, 30)
DACMDL  = clamp(DACMD, -30, 30)
DRCMDL  = clamp(DRCMD, -30, 30)
```

### 10.2 Speedbrake Authority and Shaping

```
SBAUTH  = DBFMAX - |DACMDL|            (DBFMAX = 60)
DSBCMDL = clamp(DSBCMD, 0.001, SBAUTH)

DBFSBLC = DSBCMDL                       (lower body flap speedbrake)
DBFSBUC = -0.333 * DBFSBLC             (if DBFSBLC <= 15)
DBFSBUC = 10.0 - DBFSBLC               (if DBFSBLC > 15)
```

### 10.3 Elevon Commands

```
DLEC = DECMDL    (left wing flap = limited elevator)
DREC = DECMDL    (right wing flap = limited elevator)
```

### 10.4 Body Flap Aileron (Subsonic, MACH < 1.2)

```
DULCMD =  DACMDL     →  limited to [-100, 0]   →  DULCMDL
DLLCMD =  DACMDL     →  limited to [0, 100]    →  DLLCMDL
DURCMD = -DACMDL     →  limited to [-100, 0]   →  DURCMDL
DLRCMD = -DACMDL     →  limited to [0, 100]    →  DLRCMDL
```

### 10.5 Body Flap Elevator Assist

```
DUFDE = (DLEC + 15)  if DLEC < -15,  else 0
DLFDE = (DLEC - 15)  if DLEC >  15,  else 0
```

### 10.6 Total Body Flap Commands

```
DULC = DULCMDL + DBFSBUC + DUFDE
DURC = DURCMDL + DBFSBUC + DUFDE
DLLC = DLLCMDL + DBFSBLC + DLFDE
DLRC = DLRCMDL + DBFSBLC + DLFDE
```

### 10.7 Actuator Chains

Each of the 7 surfaces passes through: **FirstOrder(τ=0.05s) → SlewRateLimiter(±20°/s) → PositionLimiter**.

| Surface | Input | Position Limits |
|---------|-------|-----------------|
| DLE (left wing flap) | DLEC | [-30, +30] |
| DRE (right wing flap) | DREC | [-30, +30] |
| DUL (upper left body flap) | DULC | [-60, 0] |
| DUR (upper right body flap) | DURC | [-60, 0] |
| DLL (lower left body flap) | DLLC | [0, +60] |
| DLR (lower right body flap) | DLRC | [0, +60] |
| DR (rudder) | DRCMDL | [-30, +30] |

### Helper Components Needed

- **Switch**: `y = ifelse(selector > threshold, A, B)`
- **Abs**: `y = |u|` (extends SISO)
- **AdjustableUpperLimit**: `y = max(min(u1, u2), u_min)` (extends SI2SO)

Also output `DLEDEG = DLE` for pitch SAS feedback.

---

## 11. Validation Scenarios

| # | Analysis Name | Stop | Description |
|---|---------------|------|-------------|
| 1 | `TestGravityOnlySim` | 5 s | RigidBody6DOF alone. |
| 2 | `AeroSweepTransient` | 35 s | HL20Aero alone, α ramp −5→+30°. |
| 3 | `TestHL20SubsonicSim` | 10 s | HL20Vehicle plant, constant surfaces at NASA trim. |
| 4 | `TestControllersSim` | 15 s | Four controllers standalone with constant inputs. |
| 5 | `TestHL20FullSystemSim` | 10 s | Full closed loop (Vehicle + Controllers + Mixer), aft pitch stick pulse. Matches TM-107580 Appendix F, Trim Case 0, Maneuver 1. |

The grader compares state and observed signals from each analysis against the golden solution. Match the analysis names exactly.

### Scenario 1 — `TestGravityOnlySim`

`RigidBody6DOF` alone, with these instance parameters:
```
mass=1000, Jxx=100, Jyy=200, Jzz=300, g=9.81
```
All six external inputs (F1, F2, F3, T1, T2, T3) tied to constant `0`. Initial state:
```
p1=0, p2=0, p3=−1000   v1=100, v2=0, v3=0
q0=1, q1=0, q2=0, q3=0   w1=0, w2=0, w3=0
```

### Scenario 2 — `AeroSweepTransient`

`HL20Aero` alone. Drive `alpha_deg` with a ramp: height=35.0, duration=35.0, offset=−5.0, start_time=0.0. Hold the rest at:
```
beta_deg=0,  mach=0.2,  vrw_fps=223.3,  hob=100,
pb=qb=rb=0,  DBFUL=DBFUR=DBFLL=DBFLR=DWFL=DWFR=DRUD=0
```

### Scenario 3 — `TestHL20SubsonicSim`

`HL20Vehicle` (no controllers, no mixer). Constant surface commands at NASA trim:
```
DFWL=DFWR=5.5,  DBFUL=DBFUR=−6.42,  DBFLL=DBFLR=16.42,  DRUD=0
```
Vehicle ICs: subsonic (see below).

### Scenario 4 — `TestControllersSim`

Instantiate `PitchControl` with parameter `DETRIM0=5.5` (initial value of the auto-trim integrator). Drive every controller input from a constant source:

| Controller | Port | Constant value |
|---|---|---|
| pitch | DCPILOT | 0.0 |
| pitch | QDEG | 0.0 |
| pitch | RDEG | 0.0 |
| pitch | NZ | 1.0 |
| pitch | SINPHI | 0.0 |
| pitch | COSPHI | 1.0 |
| pitch | COSTHE | 0.98 |
| pitch | DLEDEG | 5.5 |
| pitch | QBAR | 300.0 |
| pitch | MACH | 0.54 |
| pitch | VTOTALI | 585.0 |
| roll | DWPILOT | 0.0 |
| roll | PDEG | 0.0 |
| yaw | DPPILOT | 0.0 |
| yaw | RDEG | 0.0 |
| yaw | MACH | 0.54 |
| speed | DLSBCOM | 20.9 |

Cross-controller wiring: `roll.DACMD → yaw.DACMD`. Initial conditions on the differential states:
```
pitch.DETRIM = 5.5,  pitch.GAMDOTF = 0.0,  pitch.QDEGF = 0.0,  yaw.RBWASH = 0.0
```

Graded variables: `DECMD, DACMD, DRCMD, DSBCMD, QDEGF, GAMDOTF, DETRIM, RBWASH`.

### Subsonic Initial Conditions (Scenarios 3, 5)

Approximate trim at 300 KEAS / 10,000 ft. The `Cm_bias` baked into `HL20Aero` nearly zeros the pitching moment here. NZ ≈ 0.97 (slightly below 1g), so the open-loop vehicle drifts slowly in pitch.

```
pos   = [0, 0, −3048] m          (10,000 ft altitude)
vel   = [170.678, 0, 52.18176]   (~178 m/s, −17° FPA)
quat  = [0.9950556, 0, −0.09932, 0]
omega = [0, 0, 0]
```

### Scenario 5 — `TestHL20FullSystemSim`

Wire `HL20Vehicle`, `PitchControl(DETRIM0=5.5)`, `RollControl`, `YawControl`, `SpeedControl`, and `HL20Mixer` in closed loop. Controller inputs come from the vehicle feedback outputs (§8) and the pilot commands; controller outputs drive the mixer; mixer surface outputs drive the vehicle surface inputs.

**Pilot inputs (constant blocks unless noted):**
```
DCPILOT  = 1.0 pulse, width 1 s, starting at t = 1 s, else 0   (pitch stick)
DWPILOT  = 0.0                                                  (roll stick)
DPPILOT  = 0.0                                                  (rudder pedals)
DLSBCOM  = 20.925                                               (speedbrake → DSBCMD ≈ 16.42 via §9.4)
```

**Initial conditions** (vehicle ICs from "Subsonic Initial Conditions" above, plus):
```
pitch.QDEGF = 0.0,  pitch.GAMDOTF = 0.0,  pitch.DETRIM = 5.5,  yaw.RBWASH = 0.0

mixer.le_fo.x = mixer.re_fo.x = 5.5
mixer.ul_fo.x = mixer.ur_fo.x = -6.42
mixer.ll_fo.x = mixer.lr_fo.x = 16.42
mixer.dr_fo.x = 0.0
```

### Ground-Truth Reference

`assets/shared/nasa_appendixF_case0_man1.csv` contains time histories digitized from the NASA check-case plots (`scanned_pages/appf_sub_235` through `appf_sub_253`): columns `time, ALPDEG, QDEG, DECMD, DSBCMD, GAMMAD, DLE`. Precision ±0.1–0.2° depending on axis-grid resolution. The file is informational — the grader scores against the golden simulation, not against this CSV.

---

## 12. Debugging Guide

- **Gravity-only fails:** Check gravity direction (+pos_3 = NED down). Check quaternion kinematics signs. Check all six force/torque inputs are wired.
- **Aero sweep discontinuities:** Check that the aero model compiles and the lookup functions are accessible via `ChallengeComponent.hl20_poly1d(...)` etc.
- **Integrated tests fail after gravity-only passes:** Check frame contracts — forces must be in inertial NED, torques in body frame, altitude = −pos_3 × ft_per_m.
- **NaN / divergence:** Check division safety (v_scalar, vrw_fps denominators). Check missing initial conditions.
- **Mixer startup transient:** Ensure all FirstOrder actuator states are initialized at their equilibrium values.
