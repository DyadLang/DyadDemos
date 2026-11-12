# LinearActuatorSystem

An electric linear actuator turns a motor's spin into a straight push: a small
DC motor turns a lead screw, and a nut on that screw moves a carriage along a
guide. This library models one such actuator with
[Dyad](https://help.juliahub.com/dyad), from the 24 V supply all the way to the
carriage, along with the controller that keeps it moving at the right speed.

The actuator runs a back-and-forth move: speed up, cruise, stop, wait, then do
the same in reverse. Partway through the forward stroke, an 800 N load suddenly
starts pushing back on the carriage. The controller has to hold the commanded
speed through that load hit without drawing more current than the motor drive
allows.

## How it is put together

```
speed profile → speed PI → current PI → PWM → H-bridge → DC motor → gearbox → lead screw → carriage
                   ↑           ↑                              │         │
                   │           └──── armature current ────────┘         │
                   └───────────────── Hall speed sensor ────────────────┘
```

The controller is cascaded: two loops, one inside the other. The outer loop
compares the commanded motor speed with the Hall sensor's estimate and asks
for a motor current. The inner loop compares that request with the measured
armature current and sets the voltage across the motor. The inner loop is
tuned to respond much faster than the outer one, so the speed loop sees the
current loop as almost instantaneous.

The power electronics are averaged over each switching cycle. The model gets
the average voltage and current right but leaves out the 20 kHz switching
ripple, which keeps the simulation fast.

With the default parameters, the 3000 rpm cruise speed moves the carriage at
50 mm/s. Each stroke is about 25 mm. Holding off the 800 N load takes about
2.5 A of motor current, well inside the 8 A current limit.

## Models

The following Dyad models are defined in the `dyad/` directory:

- **`LinearActuator`**: the complete system, wired as in the diagram above.
  Motor: 1 Ω, 1 mH, 0.05 N·m/A torque constant. Drive train: 5:1 gearbox,
  5 mm screw lead, 10 kg carriage. The 800 N load is applied at 0.3 s. It
  also declares three analysis points for control design: the voltage
  command `u_v`, the measured current `y_i` and the measured speed `y_n`.

- **`CascadeController`**: the outer speed PI and inner current PI, both
  `LimPID` blocks with anti-windup. The speed loop's output is limited to
  ±8 A and the current loop's to the available bridge voltage. In
  `LinearActuator`, the current loop is tuned by Ziegler–Nichols. The speed
  loop is tuned by hand, because Ziegler–Nichols makes it unstable; the
  reasoning is in the model's docstring.

- **`AveragedPWM`**: turns the voltage command into a modulation index for
  the bridge. It scales by the DC-link voltage, adds the modulator's
  1.5-period dead time (as a Padé approximation) and limits the index to
  ±0.98.

- **`AveragedHBridge`**: a cycle-averaged full H-bridge with 10 mΩ switch
  resistance. Power in from the DC link matches power out to the motor,
  minus the switch losses.

- **`HallSpeedSensor`**: estimates shaft speed in rpm. Real Hall sensors
  count edges over a short window (2 ms here). The model represents this as
  a first-order lag, which takes no torque from the shaft.

- **`LeadScrewDriveTrain`**: motor shaft → gearbox → screw inertia → lead
  screw → carriage mass with viscous guide friction, plus an input for the
  external load force. The gearbox and screw are ideal: rigid, lossless and
  backlash-free.

- **`SpeedProfile`**: the trapezoidal forward/reverse speed command. It
  ramps up over 0.1 s, cruises for 0.4 s, ramps down, waits 0.3 s and then
  repeats in reverse.

The 1.8 s `LinearActuatorTransient` analysis simulates the full move.

## Tests

`dyad/ComponentTests.dyad` has a test model for each building block, each
checked against a final value that can be worked out by hand:

- **`TestAveragedHBridge`**: an R-L load on a 24 V bridge, with the
  modulation index stepping from +0.5 to −0.5 at 50 ms. The load current
  must settle at −11.76 A, and the current drawn from the DC link at 5.88 A.
- **`TestAveragedPWM`**: a voltage command ramped from −30 V to +30 V,
  past the ±24 V the DC link can supply, then stepped down to −2 V at
  15 ms to show the dead time. The modulation index must start limited at
  −0.98 and end at −2/24.
- **`TestHallSpeedSensor`**: an inertia sped up to 10 rad/s by a torque
  pulse, then left to coast. The sensor must read 95.493 rpm at the end.
- **`TestLeadScrewDriveTrain`**: 5 mN·m on the input shaft, which becomes
  31.42 N at the carriage, against a 15.71 N opposing load from 1 s. The
  carriage must settle at 0.157 m/s against the guide friction.
- **`TestSpeedProfile`**: the default forward/reverse move. The speed
  command must be back at zero at the end.

Each test also compares its full output signal against a recording in
`test/snapshots/`.

## Next steps

[`demo.md`](demo.md) lists the control-design work this model is set up for.
None of it is implemented yet:

- find a trim point
- linearize the model and produce Bode and root-locus plots
- tune the cascaded controller with `DiscreteAutoTuningProblem`
- check the tuned loop's disk margins
