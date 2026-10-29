```@cardmeta
Title = "Passive Suspension — tuning dampers for rider comfort"
Description = "A quarter-car suspension on an ISO 8608 Class C road, tuned against the ISO 2631-1 comfort bands."
Tags = ["automotive", "vehicle-dynamics", "control"]
Cover = "assets/icon.svg"
```

# Passive Suspension Demo

A car drives over a bumpy road, and its springs and dampers decide how much of
the shaking reaches the person in the seat. This demo lets you tune those
springs and dampers.

Three stacked masses carry the wheel, the car body, and the seated rider. They
ride on an ISO 8608 Class C road profile — the standard description of an
average-to-poor paved road. The profile is built here from 30 sine waves
between 0.5 and 30 Hz, whose height grows with vehicle speed.

Ride quality is scored with ISO 2631-1, the standard that says how much
vibration a seated person will tolerate. As shipped, the model falls short of
the standard's top band; finding damper values that reach it is the point of
the demo.

An actively controlled variant ships alongside as a reference.

## The model

`MyPassiveSuspension` stacks three `MassSpringDamper` components — wheel, car
and suspension, human and seat — on the Class C road source:

```@dyadviewer
entity = "PassiveSuspension.MyPassiveSuspension"
default = "diagram"
height = "480px"
```

## Running it

Run the 10 s passive transient and plot the seat response:

```@example passivesuspension
using PassiveSuspension, Plots

result = PassiveSuspensionTransient()
plot(result)
```

The actively controlled reference is `ActiveSuspensionTransient()`. It runs on
its own input — a single smooth 0.2 m bump from the example library, repeating
every 10 s — and on its own mass values.

The two runs therefore cover different roads and stand as separate reference
points, not as a like-for-like pair.

## Scoring comfort

The score is the ISO 2631-1 weighted RMS vertical acceleration at the seat. The
standard's top band, "not uncomfortable", sits below 0.315 m/s²; tuning the
dampers to get there is the target.
