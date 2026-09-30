```@cardmeta
Title = "Satellite GNC — observer-based attitude control"
Description = "A CubeSat three-axis repointing maneuver, flown with ideal torques and with eight thrusters."
Tags = ["aerospace", "control", "state-estimation"]
Cover = "assets/icon.svg"
```

# Satellite GNC Demo

A CubeSat-class spacecraft flies a rest-to-rest three-axis repointing maneuver —
roll 20°, pitch 10°, yaw 30° simultaneously — tracking a trapezoidal slew
profile on each axis.

To arrive on target without overshooting, the controller has to know how fast
the craft is already turning, and the one sensor aboard reports only which way
it is pointing. A Luenberger observer supplies the missing turn rate: it runs a
small model of the spacecraft alongside the real one and nudges that model into
agreement with each new star-tracker angle.

The loop ships twice. The 3-DOF version uses ideal torque actuation. The 6-DOF
version flies a 400 km orbit, where the same controller acts through eight
discrete thrusters and a pseudoinverse allocator.

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
