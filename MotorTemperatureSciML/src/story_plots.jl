# Makie figures for the story analyses. Figures are built without a backend;
# load CairoMakie (or another backend) to display or save them.

using Makie
using Statistics: quantile

# Palette: categorical slots in fixed order (measured, Dyad, PyTorch, 4th channel),
# chart chrome from a light surface.
const STORY_SERIES = ("#2a78d6", "#eb6834", "#1baf7a", "#eda100")
const C_MEASURED, C_DYAD, C_REFERENCE = STORY_SERIES[1], STORY_SERIES[2], STORY_SERIES[3]
const C_INK, C_INK2, C_MUTED = "#0b0b0b", "#52514e", "#898781"
const C_GRID, C_AXIS, C_SURFACE = "#e1e0d9", "#c3c2b7", "#fcfcfb"

function story_theme()
    Theme(
        fontsize = 13, figure_padding = 18, backgroundcolor = C_SURFACE,
        Axis = (
            backgroundcolor = C_SURFACE,
            xgridcolor = C_GRID, ygridcolor = C_GRID, xgridwidth = 0.75, ygridwidth = 0.75,
            leftspinecolor = C_AXIS, bottomspinecolor = C_AXIS,
            rightspinevisible = false, topspinevisible = false,
            xtickcolor = C_AXIS, ytickcolor = C_AXIS,
            xticklabelcolor = C_INK2, yticklabelcolor = C_INK2,
            xlabelcolor = C_INK2, ylabelcolor = C_INK2,
            titlecolor = C_INK, titlealign = :left, titlesize = 14, titlefont = :bold,
        ),
        Legend = (framevisible = false, labelcolor = C_INK2, padding = (0, 0, 0, 0)),
        Lines = (linewidth = 1.6,),
        ScatterLines = (linewidth = 1.6, markersize = 8),
    )
end

story_title!(fig, text) = Label(fig[0, :], text; font = :bold, fontsize = 17, color = C_INK,
    halign = :left, tellwidth = false)

function horizon_line!(ax, t, th)
    th > 0 && t[end] > th || return nothing
    vlines!(ax, [th]; color = C_MUTED, linestyle = :dash, linewidth = 1)
end

# Four temperature panels: measured, Dyad prediction and optional reference.
function fit_figure(sol)
    trained = sol isa TNNTrainingAnalysisSolution || sol.trained
    ref = sol isa TNNFreeRunAnalysisSolution ? sol.reference : nothing
    dyad_label = trained ? "Dyad TNN (calibrated)" : "Dyad TNN (untrained)"
    th = sol.spec.train_horizon
    # The derived analysis name is not kept on the base spec; the harness name
    # (TestTNNProfile, TestTNNProfile60, …) identifies the profile instead.
    title = "$(trained ? "Calibrated" : "Untrained") TNN on $(nameof(sol.spec.model)), free-running over the full profile"
    with_theme(story_theme()) do
        fig = Figure(size = (1100, 760))
        story_title!(fig, title)
        axes = Axis[]
        for i in 1:4
            r, c = fldmod1(i, 2)
            err = rms(sol.predicted[i, :] .- sol.measured[i, :])
            ax = Axis(fig[r, c]; title = "$(CHANNEL_LABELS[i])  ·  RMS $(round(err; digits = 2)) °C",
                xlabel = r == 2 ? "t [s]" : "", ylabel = "T [°C]")
            lines!(ax, sol.t, sol.measured[i, :]; color = C_MEASURED, label = "measured")
            lines!(ax, sol.t, sol.predicted[i, :]; color = C_DYAD, label = dyad_label)
            isnothing(ref) || lines!(ax, sol.t, ref[i, :]; color = C_REFERENCE, label = "PyTorch reference")
            horizon_line!(ax, sol.t, th)
            # Frame the measurement and the Dyad prediction; a reference that
            # diverges leaves the frame instead of squashing the comparison.
            lo = min(minimum(sol.measured[i, :]), minimum(sol.predicted[i, :]))
            hi = max(maximum(sol.measured[i, :]), maximum(sol.predicted[i, :]))
            ylims!(ax, lo - 0.1 * (hi - lo), hi + 0.15 * (hi - lo))
            push!(axes, ax)
        end
        linkxaxes!(axes...)
        legend_entries = [LineElement(color = C_MEASURED) => "measured",
                          LineElement(color = C_DYAD) => dyad_label]
        isnothing(ref) || push!(legend_entries, LineElement(color = C_REFERENCE) => "PyTorch reference")
        th > 0 && sol.t[end] > th &&
            push!(legend_entries, LineElement(color = C_MUTED, linestyle = :dash) => "end of training horizon")
        Legend(fig[3, :], first.(legend_entries), last.(legend_entries);
            orientation = :horizontal, tellwidth = false)
        fig
    end
end

# Prediction minus measurement per channel.
function residual_figure(sol)
    th = sol.spec.train_horizon
    with_theme(story_theme()) do
        fig = Figure(size = (1100, 760))
        story_title!(fig, "Prediction error on $(nameof(sol.spec.model)) (Dyad − measured)")
        axes = Axis[]
        for i in 1:4
            r, c = fldmod1(i, 2)
            res = sol.predicted[i, :] .- sol.measured[i, :]
            ax = Axis(fig[r, c]; title = "$(CHANNEL_LABELS[i])  ·  RMS $(round(rms(res); digits = 2)) °C",
                xlabel = r == 2 ? "t [s]" : "", ylabel = "error [°C]")
            hlines!(ax, [0.0]; color = C_AXIS, linewidth = 1)
            lines!(ax, sol.t, res; color = C_DYAD)
            horizon_line!(ax, sol.t, th)
            push!(axes, ax)
        end
        linkxaxes!(axes...)
        fig
    end
end

# Log axis only for data spanning more than a decade; a narrow range on a log
# axis produces fractional-power ticks that nobody can read.
function scale_for(v)
    w = filter(x -> isfinite(x) && x > 0, v)
    !isempty(w) && maximum(w) / minimum(w) > 10 ? log10 : identity
end

# The augmented-Lagrangian objective can dip to or below zero, which a log axis
# cannot show. Then use a symmetric log axis, linear below the 10th percentile
# of the positive values, with explicit decade ticks (Makie's own ticks for
# `Symlog10` are unreadable).
function objective_axis(v)
    w = filter(isfinite, v)
    pos = filter(>(0), w)
    (isempty(pos) || maximum(pos) / minimum(pos) <= 10) && return (identity, Makie.automatic)
    all(>(0), w) && return (log10, Makie.automatic)
    lo = floor(Int, log10(quantile(pos, 0.1)))
    hi = ceil(Int, log10(maximum(pos)))
    ticks = [10.0^k for k in lo:hi]
    if minimum(w) < -10.0^lo
        ticks = vcat(-[10.0^k for k in reverse(lo:ceil(Int, log10(-minimum(w))))], ticks)
    end
    ticks = vcat(ticks[ticks .< 0], 0.0, ticks[ticks .> 0])
    return (Makie.Symlog10(10.0^lo), (ticks, [tick_label(t) for t in ticks]))
end

# "10⁻³"-style labels for decade ticks.
function tick_label(t)
    t == 0 && return "0"
    k = round(Int, log10(abs(t)))
    digits = collect("⁰¹²³⁴⁵⁶⁷⁸⁹")
    sup = map(c -> digits[c - '0' + 1], string(abs(k)))
    return (t < 0 ? "−" : "") * "10" * (k < 0 ? "⁻" : "") * join(sup)
end

# Training curves: objective per Adam step, junction gap and penalty per outer iteration.
function training_figure(sol::TNNTrainingAnalysisSolution)
    steps, outer = sol.steps, sol.outer
    with_theme(story_theme()) do
        fig = Figure(size = (1100, 760))
        story_title!(fig, "Training on $(nameof(sol.spec.model)): stochastic multiple shooting under an augmented Lagrangian")

        yscale, yticks = objective_axis(steps.loss)
        ax1 = Axis(fig[1, 1:2]; title = "Augmented-Lagrangian objective per Adam step",
            xlabel = "Adam step", ylabel = "objective", yscale, yticks)
        boundaries = [first(steps.step[steps.outer .== k]) for k in unique(steps.outer)[2:end]]
        isempty(boundaries) || vlines!(ax1, boundaries; color = C_GRID, linewidth = 1)
        lines!(ax1, steps.step, steps.loss; color = STORY_SERIES[1])

        gap = outer.r_primal .* STORY_MAX_TEMP
        ax2 = Axis(fig[2, 1]; title = "Largest junction gap after each outer iteration",
            xlabel = "outer iteration", ylabel = "gap [°C]",
            xticks = outer.outer, yscale = scale_for(gap))
        hlines!(ax2, [sol.spec.continuity_tol]; color = C_MUTED, linestyle = :dash, linewidth = 1)
        scatterlines!(ax2, outer.outer, gap; color = STORY_SERIES[2], markercolor = STORY_SERIES[2])

        ax3 = Axis(fig[2, 2]; title = "Penalty ρ per outer iteration",
            xlabel = "outer iteration", ylabel = "ρ", xticks = outer.outer,
            yscale = scale_for(outer.rho))
        scatterlines!(ax3, outer.outer, outer.rho; color = STORY_SERIES[3], markercolor = STORY_SERIES[3])

        entries = [LineElement(color = STORY_SERIES[1]) => "objective"]
        isempty(boundaries) || push!(entries, LineElement(color = C_GRID) => "outer-iteration boundary")
        append!(entries, [LineElement(color = STORY_SERIES[2]) => "largest junction gap",
                          LineElement(color = C_MUTED, linestyle = :dash) => "continuity tolerance",
                          LineElement(color = STORY_SERIES[3]) => "penalty ρ"])
        Legend(fig[3, :], first.(entries), last.(entries); orientation = :horizontal, tellwidth = false)
        fig
    end
end

# Junction gaps of the shooting fit, one series per temperature channel.
function continuity_figure(sol::TNNTrainingAnalysisSolution)
    G = sol.continuity
    k = 1:size(G, 2)
    with_theme(story_theme()) do
        fig = Figure(size = (1000, 560))
        story_title!(fig, "Segment continuity after calibration on $(nameof(sol.spec.model)) ($(sol.n_segments) segments of $(round(Int, sol.spec.window)) s)")
        ax = Axis(fig[1, 1]; xlabel = "junction k", ylabel = "T_end[k] − T_0[k+1]  [°C]")
        hlines!(ax, [0.0]; color = C_AXIS, linewidth = 1)
        for i in 1:4
            scatterlines!(ax, k, G[i, :]; color = STORY_SERIES[i], markercolor = STORY_SERIES[i],
                label = CHANNEL_LABELS[i])
        end
        Legend(fig[2, 1], ax; orientation = :horizontal, tellwidth = false)
        fig
    end
end
