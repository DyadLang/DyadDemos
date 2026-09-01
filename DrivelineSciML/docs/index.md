```@cardmeta
Title = "Driveline SciML — nonlinear isolator calibration"
Description = "Two-stage parameter calibration of a nonlinear torsional isolator in an EV driveline."
Tags = ["sciml", "parameter-calibration", "nonlinear-dynamics"]
Cover = "assets/icon.svg"
Order = 1
```

# Driveline SciML Demo

An electric car has a rubbery coupling between its motor and its wheels that
soaks up shock. Nobody has measured how it behaves, so this demo shakes it in
controlled ways and fits a model to what comes back.

That coupling is a **nonlinear torsional isolator**: a twisting spring and
damper whose stiffness depends on how fast and how far it is twisted. Its
torque comes from three paths at once:

- a baseline path — how it responds to slow, steady twisting;
- a Maxwell relaxation element — extra stiffness that shows up only at high
  frequencies;
- a Bouc-Wen hysteresis element — torque that depends on where the twist has
  been, not just where it is now.

The demo recovers the hidden parameters in two stages. Stage 1 shakes the
coupling gently across a sweep of frequencies; Stage 2 cycles it slowly at full
amplitude. Both stages fit with SciML optimization.

!!! note
    This is a heavy SciML demo. The model diagram below renders from a
    snapshot; run the calibration itself from the `DrivelineSciML` project.

## The model

`DrivelineSystem` is the assembled driveline: the torque source, engine
inertia, Maxwell-Bouc-Wen isolator, load inertia, load damper, and ground:

```@dyadviewer
entity = "DrivelineSciML.DrivelineSystem"
default = "diagram"
height = "480px"
```
