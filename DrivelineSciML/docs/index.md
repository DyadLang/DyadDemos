```@cardmeta
Title = "Driveline SciML — nonlinear isolator calibration"
Description = "Two-stage parameter calibration of a nonlinear torsional isolator in an EV driveline."
Tags = ["sciml", "parameter-calibration", "nonlinear-dynamics"]
Cover = "assets/icon.svg"
```

# Driveline SciML Demo

A two-stage parameter calibration of a nonlinear torsional isolator in an EV
driveline. The plant combines three torque paths — a quasi-static baseline, a
Maxwell relaxation element, and a Bouc-Wen hysteresis element — and the demo
recovers the hidden isolator parameters from designed excitations: a low-amplitude
frequency sweep followed by slow full-amplitude cycling, via SciML optimization.

!!! note
    This is a heavy SciML demo. The model diagram below renders from a snapshot,
    but the calibration runs are not executed in the documentation build. Run them
    from the `DrivelineSciML` project.

## The model

`DrivelineSystem` is the assembled two-inertia EV driveline: the torque source,
engine inertia, Maxwell-Bouc-Wen isolator, load inertia, load damper, and ground:

```@dyadviewer
entity = "DrivelineSciML.DrivelineSystem"
default = "diagram"
height = "480px"
```
