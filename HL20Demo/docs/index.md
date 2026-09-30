```@cardmeta
Title = "HL-20 Flight Simulator — agent-built 6-DOF lifting body"
Description = "A 6-DOF flight simulation of the NASA HL-20 lifting body, generated end-to-end by the Dyad Agent from an engineering spec."
Tags = ["aerospace", "flight-dynamics", "control", "agent-built"]
Cover = "assets/icon.svg"
```

# HL-20 Flight Simulator

The **Dyad Agent** wrote this entire flight simulator — the vehicle, its
autopilot, and the logic that moves its control surfaces — from a written
engineering spec (`assets/shared/hl20_spec.md`) and two prompts in `scripts/`.
No model code was typed by hand.

The vehicle is the **NASA HL-20**, a proposed crew-carrying spaceplane that
flies on the shape of its own body rather than on wings. The model follows its
motion through the air — where it is, how fast it is going, and which way it is
pointing — from these parts:

| Part | What it does |
|---|---|
| Rigid-body dynamics | Moves and turns the vehicle under the forces acting on it |
| 1976 Standard Atmosphere | Looks up air density and pressure for the current altitude |
| Aerodynamics (NASA TM-4302) | Turns airspeed, attitude, and surface angles into forces and torques |
| Flight-control laws | Steers pitch, roll, yaw, and speed toward the commanded values |
| Surface mixer and actuators | Spreads each command across the seven moving surfaces |

Two references check the result: a golden solution, and NASA's own published
pitch-pulse test case from TM-107580 Appendix F.

!!! note
    This is a heavy, agent-generated demo. The aerodynamic core's Dyad source is
    shown below. Running the Dyad Agent prompts inside the `HL20Demo` project
    produces the full closed-loop plant, controllers, and mixer — start there to
    reproduce the end-to-end pitch-pulse maneuver.

## The model

`HL20Demo.shared.HL20Aero` is the pre-provided aerodynamic core of the vehicle:
the full TM-4302 body-axis coefficient buildup. Flight state and the seven
control-surface deflections go in; the body-axis force and moment coefficients
(`CX, CY, CZ, Cl, Cm, Cn`) come out.

The agent builds the rest of the closed loop around it:

```@dyadviewer
entity = "HL20Demo.shared.HL20Aero"
default = "code"
height = "480px"
code_auto_height = "false"
```
