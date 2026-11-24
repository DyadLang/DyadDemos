"""
    SedanDemo

A full-vehicle sedan model built on `MultibodyComponents`, together with the
reusable [`SedanDemo.VehicleComponents`](@ref) component library it is
assembled from.

The vehicle is [`Sedan`](@ref): a rear-wheel-drive sedan with four
double-wishbone corners, TMeasy tires, rack-and-pinion steering, a map-based
engine with a continuously variable transmission, an open differential, and
friction brakes. It takes normalized `steering`, `throttle`, and `braking` commands and
reports the chassis pose (`x`, `z`, `yaw`) and longitudinal speed (`v`).

[`SedanSettle`](@ref), [`SedanAcceleration`](@ref), [`SedanStepSteer`](@ref),
and [`SedanDoubleLaneChange`](@ref) are closed-loop maneuvers built from it.

Simplify a model for simulation with `MultibodyComponents.multibody`.
"""
module SedanDemo

include("../generated/module.jl")

end # module SedanDemo
