```@cardmeta
Title = "HL-20 Fully Graphical 6-DOF Flight Simulation"
Description = "The NASA HL-20 as a fully graphical Dyad model: every math block and connection visible — block aerodynamics, rigid-body dynamics, atmosphere, control laws, mixer, and closed-loop pitch-pulse validation."
Tags = ["aerospace", "flight-dynamics", "control", "agent-built"]
Cover = "assets/icon.svg"
```

# HL-20 Flight Simulator

This checkout contains a **fully graphical** 6-DOF simulation of the NASA
HL-20 lifting body: every operation that feeds the dynamics — aerodynamic
coefficient build-up, forces and moments, atmosphere, flight-state kinematics,
integrators, the surface mixer and the SAS control laws — is a wired
`BlockComponents` block laid out in hierarchical diagrams. The engineering
spec (`assets/shared/hl20_spec.md`) and the Dyad Agent prompts in `scripts/`
document how the model was derived.

The vehicle is the **NASA HL-20**, a proposed crew-carrying spaceplane that
flies on the shape of its own body rather than on wings. The requested
simulator would follow its
motion through the air — where it is, how fast it is going, and which way it is
pointing — using these parts:

| Part | What it does |
|---|---|
| Rigid-body dynamics | Moves and turns the vehicle under the forces acting on it |
| 1976 Standard Atmosphere | Looks up air density and pressure for the current altitude |
| Aerodynamics (NASA TM-4302) | Turns airspeed, attitude, and surface angles into forces and torques |
| Flight-control laws | Steers pitch, roll, yaw, and speed toward the commanded values |
| Surface mixer and actuators | Spreads each command across the seven moving surfaces |

The closed-loop analysis `TestHL20FullSystemSim` reproduces the Appendix F
aft pitch-stick pulse end-to-end; see `docs/diagrams/` for rendered images of
every component diagram and `docs/LAYOUT_NOTES.md` for how each layout was
produced.

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
