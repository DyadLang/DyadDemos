# Interactive Turkey Cooking Simulation Dashboard
# Visualizes temperature over time and allows parameter adjustment
using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using TurkeyDemo
using ModelingToolkit, DyadInterface
using GLMakie
import Roots

@named model = TurkeySphereTest()
res = @time TransientAnalysis(; model, stop = 14400)  # 4 hours in seconds

res_obs = Observable{ModelingToolkit.SciMLBase.ODESolution}(rebuild_sol(res))

fig = Figure()

ax = Axis(fig[1, 1];
    xlabel = "Cooking Time (minutes)",
    ylabel = "Temperature (°F)",
    xscale = Makie.ReversibleScale(x -> x / 60, x -> x * 60)
)

# Temperature plots
hlines!(ax, 350; label = "Oven", color = Makie.Cycled(3), linestyle = :dash)
lines!(ax, res_obs; idxs = (ModelingToolkit.t_nounits / 60, model.turkey.T_degF[end]), label = "Edge", color = Makie.Cycled(2))
lines!(ax, res_obs; idxs = (ModelingToolkit.t_nounits / 60, model.turkey.T_degF[1]), label = "Center", color = Makie.Cycled(1))

# Mark when turkey reaches 165°F (safe internal temp)
point_of_cooking = lift(res_obs) do sol
    center_temp = sol(sol.t[end]; idxs = model.turkey.T_degF[1])
    if center_temp < 165
        return [Point2f(0.0, 0.0)]  # Not yet cooked
    else
        time_cooked = Roots.find_zero(
            t -> sol(t; idxs = model.turkey.T_degF[1]) - 165,
            extrema(sol.t)
        )
        return [Point2f(time_cooked / 60, sol(time_cooked; idxs = model.turkey.T_degF[1]))]
    end
end

scatter!(ax, point_of_cooking; color = Makie.Cycled(4), markersize = 10, label = "Fully Cooked!")
axislegend(ax; orientation = :horizontal)

param_grid = GridLayout(fig[2, 1])

# Default parameter values
default_T_oven = 450.0
default_M_turkey = 5.0
default_rho_turkey = 1050.0
default_N = 10
default_R_turkey = (3 * default_M_turkey / (4 * π * default_rho_turkey))^(1/3)

function validate_float(str)
    try
        val = parse(Float64, str)
        return !isnan(val) && !isinf(val)
    catch
        return false
    end
end

# Create parameter input textboxes
labels = ["T_oven (K)", "M_turkey (kg)", "ρ_turkey (kg/m³)", "R_turkey (m)"]
defaults = [default_T_oven, default_M_turkey, default_rho_turkey, default_R_turkey]
textboxes = Textbox[]

for (i, (label, default)) in enumerate(zip(labels, defaults))
    Label(param_grid[1, i], label; halign = :center)
    tb = Textbox(param_grid[2, i];
        stored_string = string(round(default; sigdigits = 6)),
        validator = validate_float,
        width = 100
    )
    push!(textboxes, tb)
end

textboxes_values = [lift(x -> parse(Float64, x), tb.stored_string) for tb in textboxes]

@mtkcompile model = TurkeySphereTest(
    T_oven = default_T_oven,
    M_turkey = default_M_turkey,
    rho_turkey = default_rho_turkey,
    R_turkey = default_R_turkey,
)

prob = ODEProblem(model, [], (0.0, 14400))

# Loading overlay (shown during re-simulation)
running_label = textlabel!(ax, Point2f(0.5, 0.5); text = "Simulating...", space = :relative, fontsize = 16)
running_overlay = poly!([Rect2f(0.0, 0.0, 1.0, 1.0)]; color = (:gray, 0.5), space = :relative)
translate!(running_overlay, 0, 0, 0)

running_label.visible[] = false
running_overlay.visible[] = false

# Re-run simulation when any parameter changes
Makie.Observables.onany(textboxes_values...) do vals...
    running_label.visible[] = true
    running_overlay.visible[] = true
    yield()
    sleep(0.01)

    sol = @time begin
        newprob = ModelingToolkit.remake(prob; p = [
            model.T_oven => vals[1],
            model.M_turkey => vals[2],
            model.rho_turkey => vals[3],
            model.R_turkey => vals[4]
        ])
        solve(newprob)
    end

    running_label.visible[] = false
    running_overlay.visible[] = false

    res_obs[] = sol
end

display(fig)
