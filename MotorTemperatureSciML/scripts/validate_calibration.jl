# Free-running validation of the calibrated Thermal Neural Network.
#
# Runs the calibrated model as a plain ODE (no per-segment initial states)
# over the full training profile and over the three held-out profiles, and
# compares against the measurements and, where the files are present, against
# the reference PyTorch TNN trained on the same profile.
#
# Run standalone (reads assets/data/calibrated_params.csv):
#
#   julia +dyad-3.5.0 --project scripts/validate_calibration.jl
#
# or `include` it in the session that just ran train_stochastic_ms.jl, in which
# case it reuses `calres` and the problem objects from there.
#
# Output (runs/validation/ by default; override with --out-dir):
#   validation_training_profile.png — predicted vs measured, 4 channels
#   validation_residuals.png        — prediction error over time, 4 channels
#   validation_continuity.png       — segment-junction residuals of the SMS fit
#   validation_test_profiles.png    — 3 × 4 grid over the held-out profiles

include("common.jl")
using CairoMakie
using SciMLBase: successful_retcode
using Statistics: mean
using LinearAlgebra: norm
using Printf
using DyadModelOptimizer: compute_residual, calibration_parameters

validation_paths = output_paths(ARGS; default_dir = joinpath(RUNS_DIR, "validation"),
    default_calibration = CALIBRATED_CSV)
mkpath(validation_paths.out_dir)

# ── Calibrated parameters ────────────────────────────────────────────────────
if @isdefined(calres) && !("--calibration" in ARGS)
    x, x_full = collect(calres.u), collect(calres.original.u)
    @info "Using `calres` from the current session"
else
    isfile(validation_paths.calibration) || error("Calibration not found: $(validation_paths.calibration). Pass --calibration pointing to a saved fit.")
    (; x, x_full) = load_calibration(validation_paths.calibration)
    @info "Loaded calibrated parameters" path = validation_paths.calibration n_params = length(x)
end

# ── Training problem (reused from the training session when available) ──────
if !(@isdefined(invprob))
    df         = load_profile(TRAIN_PROFILE)
    sys        = build_system(TRAIN_PROFILE)
    experiment = training_experiment(sys; name = "profile_$(TRAIN_PROFILE)")
    invprob    = build_invprob(experiment, build_search_space(sys))
    # Only the segmentation matters here (it fixes the layout of `x_full`).
    alg = make_sms(; n_segments = N_SEGMENTS, batch_size = BATCH_SIZE,
        block_size = BLOCK_SIZE, learning_rate = 1e-3, inner_epochs = 1, outer_maxiters = 1)
end

# ── Helpers ──────────────────────────────────────────────────────────────────
"""Free-running simulation of `sys` over the whole of `df`, sampled on the data grid, in °C."""
function free_running(sys, experiment, invprob, x, df)
    T = temperature_states(sys)
    sol = simulate(experiment, invprob, x; tspan = (0.0, df.time[end]), saveat = df.time)
    successful_retcode(sol) || error("Free-running solve failed: $(sol.retcode)")
    return [sol(df.time; idxs = T[i]).u .* MAX_TEMP for i in 1:4]
end

measured(df) = [df[!, c] for c in TARGET_COLS]

"""Reference PyTorch predictions for `profile_id` (°C, on the same 0.5 s grid), or `nothing`."""
function pytorch_predictions(profile_id)
    path = joinpath(DATA_DIR, "pytorch_profile_$(profile_id).parquet")
    isfile(path) || return nothing
    pt = read_parquet(path)
    return [pt[!, c] for c in (:pm_pred, :stator_yoke_pred, :stator_tooth_pred, :stator_winding_pred)]
end

rms(r) = sqrt(mean(abs2, r))

# CairoMakie is also the Builder artifact backend. It renders headlessly and
# avoids Plots' optional GR backend, which is absent from the Dyad runtime.
function channel_plot!(slot, t, meas, pred, pt; title, first_legend)
    ax = Axis(slot; title, xlabel = "t [s]", ylabel = "T [°C]")
    lines!(ax, t, meas; color = :black, linewidth = 1, label = "measured")
    lines!(ax, t, pred; color = :red, linewidth = 1, label = "Dyad (SMS + AugLag)")
    if !isnothing(pt)
        n = min(length(t), length(pt))
        lines!(ax, t[1:n], pt[1:n]; color = :blue, linewidth = 1, label = "PyTorch reference")
    end
    # Keep the fitted model readable when the reference diverges; its full
    # RMS errors are still printed in the summary.
    lo, hi = min(minimum(meas), minimum(pred)), max(maximum(meas), maximum(pred))
    pad = max(hi - lo, 1.0)
    ylims!(ax, lo - 0.1pad, hi + 0.25pad)
    xlims!(ax, 0, t[end])
    first_legend && axislegend(ax; position = :rb, labelsize = 10)
    return ax
end

# ── Training profile, free-running over its full length ─────────────────────
pred = free_running(sys, experiment, invprob, x, df)
meas = measured(df)
pt   = pytorch_predictions(TRAIN_PROFILE)
t    = df.time
in_train = t .<= TRAIN_HORIZON_S

p1 = Figure(size = (1100, 700))
for i in 1:4
    ax = channel_plot!(p1[(i - 1) ÷ 2 + 1, (i - 1) % 2 + 1], t, meas[i], pred[i],
        isnothing(pt) ? nothing : pt[i]; title = TARGET_LABELS[i], first_legend = i == 1)
    vlines!(ax, [TRAIN_HORIZON_S]; color = :gray, linestyle = :dash)
end
save(joinpath(validation_paths.out_dir, "validation_training_profile.png"), p1)

p2 = Figure(size = (1100, 700))
for i in 1:4
    r = pred[i] .- meas[i]
    ax = Axis(p2[(i - 1) ÷ 2 + 1, (i - 1) % 2 + 1]; xlabel = "t [s]", ylabel = "error [°C]",
        title = @sprintf("%s   RMS %.2f °C", TARGET_LABELS[i], rms(r)))
    lines!(ax, t, r; linewidth = 0.7, color = :steelblue)
    hlines!(ax, [0]; color = :black, linestyle = :dash)
    vlines!(ax, [TRAIN_HORIZON_S]; color = :gray, linestyle = :dash)
end
save(joinpath(validation_paths.out_dir, "validation_residuals.png"), p2)

# ── Segment-continuity residuals of the shooting fit ─────────────────────────
# g_k = (end of segment k) − (initial state of segment k+1), per state, in °C.
# The augmented Lagrangian drives these to zero; a *systematic* sign here is
# the tell-tale of an under-converged fit: each segment would end slightly off
# and the next one restart on the data, and a free-running simulation
# integrates those offsets into a bias.
n_junctions = N_SEGMENTS - 1
g = zeros(4 * n_junctions)
compute_residual(alg)(g, x_full, calibration_parameters(alg, invprob))
G = MotorTemperatureSciML.temperature_channel_order(sys, reshape(g, 4, n_junctions)) .* MAX_TEMP

p3 = Figure(size = (1000, 550))
ax3 = Axis(p3[1, 1]; xlabel = "junction k", ylabel = "T_end[k] − T_0[k+1] [°C]",
    title = "Segment-continuity residuals after calibration ($(N_SEGMENTS) × $(Int(WINDOW_S)) s segments)")
for i in 1:4
    scatterlines!(ax3, 1:n_junctions, G[i, :]; markersize = 5, linewidth = 1,
        label = TARGET_LABELS[i])
end
hlines!(ax3, [0]; color = :black, linestyle = :dash)
axislegend(ax3; position = :rt)
save(joinpath(validation_paths.out_dir, "validation_continuity.png"), p3)

# ── Held-out profiles ────────────────────────────────────────────────────────
# Same harness, different profile: `TestTNNProfile(data_file = ...)` rebuilds the
# interpolators from the new profile; the search-space layout is unchanged so
# the calibrated `x` plugs straight in. Each simulation starts from that
# profile's first measured sample, as the reference does.
test_runs = map(TEST_PROFILES) do pid
    df_p  = load_profile(pid)
    sys_p = build_system(pid)
    exp_p = build_experiment(sys_p; name = "profile_$(pid)", tspan = (0.0, df_p.time[end]))
    inv_p = build_invprob(exp_p, build_search_space(sys_p))
    (; pid, df = df_p, pred = free_running(sys_p, exp_p, inv_p, x, df_p),
        meas = measured(df_p), pt = pytorch_predictions(pid))
end

p4 = Figure(size = (1500, 800))
for (row, r) in enumerate(test_runs), col in 1:4
    channel_plot!(p4[row, col], r.df.time, r.meas[col], r.pred[col],
        isnothing(r.pt) ? nothing : r.pt[col];
        title = "Profile $(r.pid): $(TARGET_LABELS[col])", first_legend = row == col == 1)
end
save(joinpath(validation_paths.out_dir, "validation_test_profiles.png"), p4)

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
println("Plots written to $(validation_paths.out_dir)/validation_*.png")
