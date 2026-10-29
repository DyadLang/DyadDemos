```@cardmeta
Title = "Quarter Truck SciML — neural gray-box ride model"
Description = "Quarter-truck ride-comfort model with neural-network gray-box discovery and parameter calibration."
Tags = ["sciml", "neural-network", "vehicle-dynamics"]
Cover = "assets/icon.svg"
```

# Quarter Truck SciML Demo

A quarter truck is one wheel and the mass it carries — the smallest model that
still predicts how rough a road feels to the person in the seat. Its
hand-written
equations are only approximately right, and this demo shows two ways of closing
the gap with data.

**Learn the missing physics.** A neural network sits inside the model and learns
three effects the equations leave out:

- the tire stiffening as it squashes, and going slack when the wheel lifts off
- the tire and body sticking before they slide
- the seat cushion resisting fast motion more than a plain damper would

**Recover the numbers.** From recorded road measurements, a calibrator works
backwards to the four values that produced them: body mass, suspension
stiffness,
suspension damping, and friction force.

!!! note
    This is a heavy SciML demo. The model diagram below renders from a snapshot,
    but the training and calibration runs are not executed in the documentation
    build. Run them from the `QuarterTruckSciML` project.

## The model

`QuarterTruckFullNN` assembles the tire, body, seat, and driver masses with the
suspension elements, an ISO 8608 road source, and a neural-network learning
block:

```@dyadviewer
entity = "QuarterTruckSciML.QuarterTruckFullNN"
default = "diagram"
height = "480px"
```
