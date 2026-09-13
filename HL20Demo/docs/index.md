```@cardmeta
Title = "HL-20 Flight Simulator — agent-built 6-DOF lifting body"
Description = "A 6-DOF flight simulation of the NASA HL-20 lifting body, generated end-to-end by the Dyad Agent from an engineering spec."
Tags = ["aerospace", "flight-dynamics", "control", "agent-built"]
Cover = "assets/icon.svg"
```

# HL-20 Flight Simulator

A 6-DOF flight simulation of the **NASA HL-20 lifting body**, assembled from
rigid-body quaternion dynamics, a 1976 Standard Atmosphere table lookup, a
TM-4302 body-axis aerodynamic coefficient buildup, the pitch/roll/yaw/speed
flight-control laws, and a seven-surface control-surface mixer with actuators.
What makes it notable is provenance: the entire model — plant, controllers, and
mixer — is generated from scratch by the **Dyad Agent**, working directly from
the engineering spec (`assets/shared/hl20_spec.md`) and two prompts in
`scripts/`, with no model code written by hand. The build is validated against a
golden solution and the NASA TM-107580 Appendix F closed-loop pitch-pulse
check case.

!!! note
    This is a heavy, agent-generated demo. The aerodynamic core's Dyad source is
    shown below; the full closed-loop plant, controllers, and mixer are produced
    by running the Dyad Agent prompts inside the `HL20Demo` project — start there
    to reproduce the end-to-end pitch-pulse maneuver.

## The model

`HL20Demo.shared.HL20Aero` is the pre-provided aerodynamic core of the vehicle:
the full TM-4302 body-axis coefficient buildup that maps flight state and the
seven control-surface deflections to the body-axis force and moment coefficients
(`CX, CY, CZ, Cl, Cm, Cn`). It is the aerodynamic heart around which the agent
builds the rest of the closed loop:

```@dyadviewer
entity = "HL20Demo.shared.HL20Aero"
default = "code"
height = "480px"
code_auto_height = "false"
```
