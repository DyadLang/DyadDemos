```@cardmeta
Title = "Black-box derivatives for dynamic optimization"
Description = "Exact gradients and Hessians of an opaque Julia function, for every AD backend and optimizer a dynamic-optimization problem may use."
Tags = ["optimization", "automatic-differentiation", "optimal-control"]
Cover = "assets/icon.svg"
```

# Black-box derivatives

`TireCar` is a `Car` driven by a `Tire` whose force `F(slip, load)` comes from a black box: a
Float64-only Julia function that no AD tool can see into. A minimum-time problem on this model
shows what happens with no derivatives (finite differences), with AD but no derivative
definitions (errors), and with one short file per backend (exact Hessians from Symbolics,
ForwardDiff, Enzyme, sparse AD and JuMP). The project README has the details and results.
