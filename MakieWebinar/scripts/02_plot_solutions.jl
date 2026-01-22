# Let's now move on to plotting the result of a simulation of a Dyad model.
# We'll use models from different parts of the library to show how to do this!

using ModelingToolkit, DyadInterface
using MakieWebinar

using GLMakie, Makie

# Let's instantiate the model and run a simulation:
@named model = MakieWebinar.Hello()
result = TransientAnalysis(; model = model, stop = 10.0)
# Then we can plot the result object.
fig, ax, plt = plot(result)
# But what's this trace?  `axislegend` is a helper function that adds a legend to the axis.
leg = axislegend(ax; position = :rt)

# You can also create phase plots with Dyad, and select the variables you want to plot.
# The way you do this is by extracting the simplified system from the analysis result,
# then passing the variables you want to the `idxs` keyword argument.
result = WeakDampingAnalysis()
model = DyadInterface.artifacts(result, :SimplifiedSystem)

# `idxs = [...]` plots each trace individually against time,
# and `idxs = (model.x, model.y)` plots a phase plot in 2D of x against y.
# Similarly you can do `idxs = (model.x, model.y, model.z)` for a 3D phase plot.
plot(result; idxs = (model.system.mass.v, model.system.mass.s))