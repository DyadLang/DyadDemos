# Free-running validation of the calibrated Thermal Neural Network.
#
# Runs the calibrated model as a plain ODE (no per-segment initial states)
# over the full training profile and over the three held-out profiles, and
# compares against the measurements and, where the CSVs are present, against
# the reference PyTorch TNN trained on the same profile.
#
# Run standalone (reads assets/data/calibrated_params.csv):
#
#   julia +dyad-3.3.0 --project scripts/validate_calibration.jl
#
# or `include` it in the session that just ran train_stochastic_ms.jl, in which
# case it reuses `calres` and the problem objects from there.
#
# Output (assets/):
#   validation_training_profile.png — predicted vs measured, 4 channels
#   validation_residuals.png        — prediction error over time, 4 channels
#   validation_continuity.png       — segment-junction residuals of the SMS fit
#   validation_test_profiles.png    — 3 × 4 grid over the held-out profiles

include("common.jl")
using Plots
using Statistics: mean
using LinearAlgebra: norm
using Printf
using DyadModelOptimizer: compute_residual, calibration_parameters

gr()

# ── Calibrated parameters ────────────────────────────────────────────────────
if @isdefined(calres)
    x, x_full = collect(calres.u), collect(calres.original.u)
    @info "Using `calres` from the current session"
else
    isfile(CALIBRATED_CSV) || error("$(CALIBRATED_CSV) not found — run scripts/train_stochastic_ms.jl first.")
    (; x, x_full) = load_calibration(CALIBRATED_CSV)
    @info "Loaded calibrated parameters" path = CALIBRATED_CSV n_params = length(x)
end

# ── Training problem (reused from the training session when available) ──────
if !(@isdefined(invprob))
    df         = load_profile(TRAIN_PROFILE)
    sys        = build_system(TRAIN_PROFILE)
    experiment = build_experiment(sys, df; name = "profile_$(TRAIN_PROFILE)")
    invprob    = build_invprob(experiment, build_search_space(sys))
    # Only the segmentation matters here (it fixes the layout of `x_full`).
    alg = make_sms(; n_segments = N_SEGMENTS, batch_size = BATCH_SIZE,
        block_size = BLOCK_SIZE, inner_lr = 1e-3, inner_epochs = 1, outer_maxiters = 1)
end

# ── Helpers ──────────────────────────────────────────────────────────────────
"""Free-running simulation of `sys` over the whole of `df`, sampled on the data grid, in °C."""
function free_running(sys, experiment, invprob, x, df)
    T = temperature_states(sys)
    sol = simulate(experiment, invprob, x; tspan = (0.0, df.time[end]), saveat = df.time)
    return [sol(df.time; idxs = T[i]).u .* MAX_TEMP for i in 1:4]
end

measured(df) = [df[!, c] for c in TARGET_COLS]

"""Reference PyTorch predictions for `profile_id` (°C, on the same 0.5 s grid), or `nothing`."""
function pytorch_predictions(profile_id)
    path = joinpath(DATA_DIR, "pytorch_profile_$(profile_id).csv")
    isfile(path) || return nothing
    pt = CSV.read(path, DataFrame)
    return [pt[!, c] for c in (:pm_pred, :stator_yoke_pred, :stator_tooth_pred, :stator_winding_pred)]
end

rms(r) = sqrt(mean(abs2, r))

# Overlay measured / Julia / PyTorch for one channel on a Plots subplot.
function channel_plot!(p, sub, t, meas, pred, pt; title, first_legend)
    plot!(p, t, meas; subplot = sub, color = :black, lw = 1, alpha = 0.8,
        label = first_legend ? "measured" : "")
    plot!(p, t, pred; subplot = sub, color = :red, lw = 1, alpha = 0.8,
        label = first_legend ? "Dyad (SMS + AugLag)" : "")
    if !isnothing(pt)
        n = min(length(t), length(pt))
        plot!(p, t[1:n], pt[1:n]; subplot = sub, color = :blue, lw = 1, alpha = 0.6,
            label = first_legend ? "PyTorch reference" : "")
    end
    # Axis range from the measurement and the Dyad prediction only: a reference
    # that diverges leaves the frame instead of squashing the comparison.
    lo, hi = min(minimum(meas), minimum(pred)), max(maximum(meas), maximum(pred))
    ylims!(p, lo - 0.1 * (hi - lo), hi + 0.25 * (hi - lo); subplot = sub)
    xlims!(p, 0, t[end]; subplot = sub)
    title!(p, title; subplot = sub, titlefontsize = 10)
end

# ── Training profile, free-running over its full length ─────────────────────
pred = free_running(sys, experiment, invprob, x, df)
meas = measured(df)
pt   = pytorch_predictions(TRAIN_PROFILE)
t    = df.time
in_train = t .<= TRAIN_HORIZON_S

p1 = plot(layout = (2, 2), size = (1100, 700), link = :x, legend = :bottomright,
    suptitle = "Profile $(TRAIN_PROFILE): free-running prediction vs measured")
for i in 1:4
    channel_plot!(p1, i, t, meas[i], pred[i], isnothing(pt) ? nothing : pt[i];
        title = TARGET_LABELS[i], first_legend = i == 1)
    vline!(p1, [TRAIN_HORIZON_S]; subplot = i, color = :gray, ls = :dash, lw = 1,
        label = i == 1 ? "end of training horizon" : "")
    xlabel!(p1, "t [s]"; subplot = i)
    ylabel!(p1, "T [°C]"; subplot = i)
end
savefig(p1, joinpath(ASSETS_DIR, "validation_training_profile.png"))

p2 = plot(layout = (2, 2), size = (1100, 700), link = :x, legend = false,
    suptitle = "Profile $(TRAIN_PROFILE): prediction error (Dyad − measured)")
for i in 1:4
    r = pred[i] .- meas[i]
    plot!(p2, t, r; subplot = i, lw = 0.7, color = :steelblue)
    hline!(p2, [0]; subplot = i, color = :black, ls = :dash, lw = 1)
    vline!(p2, [TRAIN_HORIZON_S]; subplot = i, color = :gray, ls = :dash, lw = 1)
    title!(p2, @sprintf("%s   RMS %.2f °C", TARGET_LABELS[i], rms(r)); subplot = i, titlefontsize = 10)
    xlabel!(p2, "t [s]"; subplot = i)
    ylabel!(p2, "error [°C]"; subplot = i)
end
savefig(p2, joinpath(ASSETS_DIR, "validation_residuals.png"))

# ── Segment-continuity residuals of the shooting fit ─────────────────────────
# g_k = (end of segment k) − (initial state of segment k+1), per state, in °C.
# The augmented Lagrangian drives these to zero; a *systematic* sign here is
# the tell-tale of an under-converged fit: each segment would end slightly off
# and the next one restart on the data, and a free-running simulation
# integrates those offsets into a bias.
n_junctions = N_SEGMENTS - 1
g = zeros(4 * n_junctions)
compute_residual(alg)(g, x_full, calibration_parameters(alg, invprob))
G = reshape(g, 4, n_junctions) .* MAX_TEMP

p3 = plot(size = (1000, 550), xlabel = "junction k", ylabel = "T_end[k] − T_0[k+1]  [°C]",
    title = "Segment-continuity residuals after calibration ($(N_SEGMENTS) × $(Int(WINDOW_S)) s segments)",
    titlefontsize = 11, legend = :topright)
for i in 1:4
    plot!(p3, 1:n_junctions, G[i, :]; marker = :circle, ms = 3, lw = 1, alpha = 0.8,
        label = TARGET_LABELS[i])
end
hline!(p3, [0]; color = :black, ls = :dash, lw = 1, label = "")
savefig(p3, joinpath(ASSETS_DIR, "validation_continuity.png"))

# ── Held-out profiles ────────────────────────────────────────────────────────
# Same harness, different CSV: `TestTNNProfile(data_file = ...)` rebuilds the
# interpolators from the new profile; the search-space layout is unchanged so
# the calibrated `x` plugs straight in. Each simulation starts from that
# profile's first measured sample, as the reference does.
test_runs = map(TEST_PROFILES) do pid
    df_p  = load_profile(pid)
    sys_p = build_system(pid)
    exp_p = build_experiment(sys_p, df_p; name = "profile_$(pid)", tspan = (0.0, df_p.time[end]))
    inv_p = build_invprob(exp_p, build_search_space(sys_p))
    (; pid, df = df_p, pred = free_running(sys_p, exp_p, inv_p, x, df_p),
        meas = measured(df_p), pt = pytorch_predictions(pid))
end

p4 = plot(layout = (length(TEST_PROFILES), 4), size = (1500, 800), legend = :topleft,
    legendfontsize = 6, xformatter = x -> string(round(Int, x)),
    suptitle = "Held-out profiles: free-running prediction vs measured")
for (row, r) in enumerate(test_runs), col in 1:4
    sub = (row - 1) * 4 + col
    channel_plot!(p4, sub, r.df.time, r.meas[col], r.pred[col],
        isnothing(r.pt) ? nothing : r.pt[col];
        title = row == 1 ? TARGET_LABELS[col] : "", first_legend = sub == 1)
    col == 1 && ylabel!(p4, "Profile $(r.pid)\nT [°C]"; subplot = sub)
    row == length(TEST_PROFILES) && xlabel!(p4, "t [s]"; subplot = sub)
end
savefig(p4, joinpath(ASSETS_DIR, "validation_test_profiles.png"))

# ── Summary ──────────────────────────────────────────────────────────────────
function report(label, t_mask, meas, pred, pt)
    @printf "  %-38s" label
    for i in 1:4
        @printf "  %6.2f" rms(pred[i][t_mask] .- meas[i][t_mask])
    end
    if !isnothing(pt)
        @printf "   |"
        for i in 1:4
            n = min(length(meas[i]), length(pt[i]))
            m = t_mask[1:n]
            @printf "  %6.2f" rms(pt[i][1:n][m] .- meas[i][1:n][m])
        end
    end
    println()
end

println()
println("RMS error [°C], channels pm / yoke / tooth / winding")
@printf "  %-38s  %6s  %6s  %6s  %6s   |  %6s  %6s  %6s  %6s\n" "" "Dyad" "" "" "" "PyTorch" "" "" ""
report("profile $(TRAIN_PROFILE), training horizon (0–$(Int(TRAIN_HORIZON_S)) s)", in_train, meas, pred, pt)
report("profile $(TRAIN_PROFILE), held-out tail", .!in_train, meas, pred, pt)
for r in test_runs
    report("profile $(r.pid) (held out)", trues(length(r.df.time)), r.meas, r.pred, r.pt)
end
println()
@printf "Segment-continuity residuals: ‖g‖₂ = %.3e °C, max |g| = %.3e °C, mean g = %+.3e °C\n" norm(G) maximum(abs, G) mean(G)
println("Plots written to $(ASSETS_DIR)/validation_*.png")
