```@cardmeta
Title = "Satellite GNC — observer-based attitude control"
Description = "A CubeSat three-axis repointing maneuver, flown with ideal torques and with eight thrusters."
Tags = ["aerospace", "control", "state-estimation"]
Cover = "assets/icon.svg"
```

# Satellite GNC Demo

A CubeSat-class spacecraft flies a rest-to-rest three-axis repointing maneuver —
roll 20°, pitch 10°, yaw 30° simultaneously — tracking a trapezoidal slew profile
on each axis. Rate feedback comes from a Luenberger observer driven by star-tracker
angles alone, so the controller damps rates it never measures. The loop ships
twice: a 3-DOF version with ideal torque actuation, and a 6-DOF version in a 400 km
orbit where the same controller acts through eight discrete thrusters and a
pseudoinverse allocator.

## The model

`TestFullGNC` is the assembled 3-DOF loop: three slew profiles, the PD-with-
feedforward attitude controller, the observer closing the rate loop, and the
rigid-body plant:

```@dyadviewer
entity = "SatelliteGNC.TestFullGNC"
default = "diagram"
height = "480px"
```

## Running it

Run the 40 s maneuver and plot the attitude response:

```@example satellitegnc
using SatelliteGNC, Plots

result = TestFullGNCSim()
plot(result)
```

The thruster-actuated orbital variant is `TestFullGNC6DOFSim()`, built on
`TestFullGNC6DOF`. See the demo's `notes.md` for the architecture and pole
placement, and `docs/algorithm_description.md` for the per-component
specifications.
