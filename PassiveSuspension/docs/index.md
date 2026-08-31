```@cardmeta
Title = "Passive Suspension — tuning dampers for rider comfort"
Description = "A quarter-car suspension on an ISO 8608 Class C road, tuned against the ISO 2631-1 comfort bands."
Tags = ["automotive", "vehicle-dynamics", "control"]
Cover = "assets/icon.svg"
```

# Passive Suspension Demo

A quarter-car suspension driven by an ISO 8608 Class C road profile — an
average-to-poor quality paved road, synthesized as a sum of 30 sinusoids between
0.5 and 30 Hz with amplitudes scaled by vehicle speed. Three stacked masses carry
the wheel, the car body, and the seated rider. Comfort is scored by the ISO 2631-1
frequency-weighted RMS vertical acceleration at the seat, and as shipped the model
does not reach the standard's top band: finding damper values that do is the point
of the demo. An actively controlled variant ships alongside as a reference.

## The model

`MyPassiveSuspension` stacks three `MassSpringDamper` components — wheel, car and
suspension, human and seat — on the Class C road source:

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

The actively controlled reference is `ActiveSuspensionTransient()`. Note that the
two are not a like-for-like pair — the active model uses the example library's
raised-cosine bump and mass values rather than the Class C profile. See the demo's
`README.md` for the comfort metric, the ISO 2631-1 comfort bands, and the
differences between the two models.
