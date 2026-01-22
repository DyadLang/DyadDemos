
#=
## Live parameter changes

A very fun thing to do is to show live parameter changes when you 
enter a value or move a slider.  This helps a user understand the dynamics
of the model and how parameter choices affect its behavior.

### The slow but simple way

The simple way to do this is to create an analysis that is parameterized
on what you want to change, and then re-run that analysis.

This is really slow though, and doesn't scale.  So don't use it in real life -
but it's a great way to understand how this works.
=#

# First, create the figure and the control layout.
fig = Figure()
control_gl = GridLayout(fig[2, 1])
# We'll make a textbox that you can type any value into.
tb = Textbox(
    control_gl[1, 1]; 
    placeholder = "320", 
    validator = Float64
)
# Note that at this point, the axis is squeezed to the width of the textbox.
# This is the "tellwidth" thing that we talked about in part 1.
# We can fix this by setting `tellwidth = false` on the textbox.
tb.tellwidth = false

# Now, we'll create an observable that will hold the result of the analysis.
result_obs = Observable{TransientAnalysisSolution}(result);

# Whenever the textbox is updated,
# we'll parse the string into a float and re-run the analysis
# with that value.
on(tb.stored_string) do str
    val = parse(Float64, str)
    result_obs[] = World(; model = model, stop = 10, T_inf = val)
end

# Now, we can plot the result of the analysis.
ax, plt = plot(fig[1, 1], result_obs)
# And add a legend to the axis.
leg = axislegend(ax; position = :rt)

#=
### The fast way

The fast way to do this is to use the `remake` function to update the parameters
of the analysis.  This is much faster than re-running the analysis,
and it scales to multiple parameters.  But it is a little more complex to set up.

First, we'll create the model, and then simplify it using `mtkcompile`.
Then, we create a problem object - which is what we can use to modify the parameters
and re-solve the problem.
=#

@named model = MakieWebinar.Hello()
simplified_model = ModelingToolkit.mtkcompile(model)
prob = ODEProblem(simplified_model, [], (0., 10.))
sol = solve(prob)

# This takes the place of `result_obs` from the slow path above.
sol_obs = Observable{ModelingToolkit.SciMLBase.AbstractODESolution}(sol);

# Now, we'll create the figure and the control layout.
fig = Figure()
control_gl = GridLayout(fig[2, 1])
# We'll make a textbox that you can type any value into.
tb = Textbox(fig[2, 1]; placeholder = "320", validator = Float64)
tb.tellwidth = false

on(tb.stored_string) do str
    val = parse(Float64, str)
    global prob
    # ModelingToolkit's `remake` function is used to update the parameters of the problem.
    prob = ModelingToolkit.remake(prob; p = [simplified_model.T_inf => val])
    sol = solve(prob)
    sol_obs[] = sol
end

ax, plt = plot(fig[1, 1], sol_obs)
leg = axislegend(ax; position = :rt)

#=
### The fast way - with sliders!

Since this is fast enough, you can also create a grid of sliders to control the parameters.
This is a lot more user friendly since you have a visual indication of a reasonable range of values.

Keep in mind that the `values` of the slider just has to be an array, so you can e.g. 
scale exponentially or logarithmically if you want.
=#

@named model = MakieWebinar.Hello()
simplified_model = ModelingToolkit.mtkcompile(model)
prob = ODEProblem(simplified_model, [], (0., 10.))
sol = solve(prob)

sol_obs = Observable{ModelingToolkit.SciMLBase.AbstractODESolution}(sol);

fig = Figure()
tb = SliderGrid(
    fig[2, 1], 
    (; label = "T_inf", range = 200:1:400, startvalue = 300),
    (; label = "T0", range = 200:1:400, startvalue = 320)
);

onany(tb.sliders[1].value, tb.sliders[2].value) do T_inf, T0
    global prob
    prob = ModelingToolkit.remake(
        prob; 
        p = [simplified_model.T_inf => T_inf, simplified_model.T0 => T0]
    )
    sol = solve(prob)
    sol_obs[] = sol
end

ax, plt = plot(fig[1, 1], sol_obs)
leg = axislegend(ax; position = :rt)

#=
## Parameter sweep using a ComputeGraph

The ComputeGraph is a way to create a graph of operations that can be executed in order.
It's a more structured way of doing observables.

This is what Makie uses internally now as well - it's a lot more hygienic and 
easier to trace through and debug :)
=#

using MakieWebinar
using DyadInterface, ModelingToolkit
using GLMakie, Makie

@named model = MakieWebinar.Hello()

result = TransientAnalysis(; model = model, stop = 10.0)

fig, ax, plt = plot(result)

# Now we'll have to go to the MTK level.
simplified_model = DyadInterface.artifacts(result, :SimplifiedSystem)
problem = ODEProblem(simplified_model, [], (0., 10.))

# Let's create our control layout with two textboxes.
fig = Figure()
control_gl = GridLayout(fig[2, 1])
control_gl.tellwidth = false
control_gl.tellheight = true
# Let's say we want to control the initial and final temperatures, as parameters.
label_T0 = Label(control_gl[1, 1], "T0"; tellwidth = true, tellheight = false)
textbox_T0 = Textbox(control_gl[1, 2], placeholder = "320", validator = Float64)
textbox_T0.stored_string = "320"

label_Tinf = Label(control_gl[1, 3], "Tinf"; tellwidth = true, tellheight = false)
textbox_Tinf = Textbox(control_gl[1, 4], placeholder = "300", validator = Float64)
textbox_Tinf.stored_string = "300"

# Now, we'll create the graph and add the inputs.
# In this case the "inputs" are the observables from the textboxes.
using Makie.ComputePipeline
graph = ComputeGraph()
add_input!(graph, :T0_str, textbox_T0.stored_string)
add_input!(graph, :Tinf_str, textbox_Tinf.stored_string)
add_input!(graph, :prob, problem)
add_input!(graph, :model, simplified_model)

# The `map!(f, graph, inputs, outputs)` function is used to encode a computation,
# that goes from the input nodes on the graph to the output nodes (which are implicitly created).
map!(x -> parse(Float64, x), graph, :T0_str, :T0)
map!(x -> parse(Float64, x), graph, :Tinf_str, :Tinf)

# You can also take multiple inputs:
map!(graph, [:T0, :Tinf, :prob, :model], [:sol]) do T0, Tinf, prob, model
    new_prob = ModelingToolkit.remake(prob, p = [model.T0 => T0, model.T_inf => Tinf])
    new_sol = solve(new_prob)
    return (new_sol,) # when returning multiple outputs you always have to wrap them in a tuple
end

# Now we can plot accessing the graph's output node:
ax, plt = plot(fig[1, 1], graph.sol)

