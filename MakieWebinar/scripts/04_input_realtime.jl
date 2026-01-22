using ModelingToolkit, ModelingToolkitInputs, DyadInterface
using GLMakie, Makie
using MakieWebinar

@named model = MakieWebinar.ControlledOscillator()
sys = mtkcompile(InputSystem(model; inputs=[model.pid_k, model.pid_Td]))

# TODO coming soon!