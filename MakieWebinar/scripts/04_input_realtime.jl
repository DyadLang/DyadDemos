using ModelingToolkit, DyadInterface
using GLMakie, Makie
using MakieWebinar

@named model = MakieWebinar.ControlledOscillator()
sys = mtkcompile(model)
prob = ODEProblem(sys, [], (0.0, 10.0))

# TODO coming soon!
