# Let's now move on to plotting the result of a simulation of a Dyad model.
# We'll use models from different parts of the library to show how to do this!

using ModelingToolkit, DyadInterface
using MakieWebinar

using GLMakie, Makie

# Let's instantiate the model and run a simulation:
@named model = MakieWebinar.Hello()
result = TransientAnalysis(; model = model, stop = 10.0)

fig, ax, plt = plot(result)