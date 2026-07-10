```@cardmeta
Title = "Quarter Truck SciML — neural gray-box ride model"
Description = "Quarter-truck ride-comfort model with neural-network gray-box discovery and parameter calibration."
Tags = ["sciml", "neural-network", "vehicle-dynamics"]
Cover = "assets/icon.svg"
```

# Quarter Truck SciML Demo

An end-to-end SciML demonstration built on a quarter-truck ride-comfort model. It
combines neural-network gray-box discovery — recovering tire cubic stiffness,
Coulomb friction, and viscoelastic seat damping from sine-excited training data —
with parameter calibration that recovers body mass and suspension stiffness,
damping, and friction from ISO 8608 road measurements.

!!! note
    This is a heavy SciML demo. The model diagram below renders from a snapshot,
    but the training and calibration runs are not executed in the documentation
    build. Run them from the `QuarterTruckSciML` project.

## The model

`QuarterTruckFullNN` assembles the tire, body, seat, and driver masses with the
suspension elements, an ISO 8608 road source, and a neural-network learning block:

```@dyadviewer
entity = "QuarterTruckSciML.QuarterTruckFullNN"
default = "diagram"
height = "480px"
```
