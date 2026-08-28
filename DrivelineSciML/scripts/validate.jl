#=
Validation: tip-in with motor ripple — an excitation never used in calibration.

Simulates the tip-in harness three ways and compares against the truth:
  • Linear baseline   (k0/c0 only — Maxwell and Bouc-Wen disabled)
  • Calibrated model  (two-stage fit from run_calibration.jl)
  • Truth             (hidden parameters used to generate the measurements)

Each run is a `TransientAnalysis` over the same harness with the isolator
knobs supplied through the analysis `overrides` (the operating point) instead
of a hand-built `ODEProblem`. Reports RMS errors vs. truth for the linear and
calibrated models and renders an overlay plot.
=#

using DrivelineSciML
using DyadInterface: TransientAnalysis, artifacts, ODEAlg
using ModelingToolkit: toggle_namespacing, SymbolicT
using CSV, DataFrames, Statistics, Printf
using Plots

const DATA_DIR = joinpath(@__DIR__, "..", "assets", "data")
const OUT_DIR  = joinpath(@__DIR__, "..", "assets")
const FITTED_CSV = joinpath(DATA_DIR, "calibrated_params.csv")

const TRUTH  = (k1 = 300.0, c1 = 1.0, alpha = 50.0, A_bw = 1.0, beta_bw = 5.0, gamma_bw = 0.5)
# k1 = 0 zeroes the Maxwell torque (and freezes theta_m); A_bw = alpha = 0
# keeps z inert — only the quasi-static k0/c0 baseline remains.
const LINEAR = (k1 = 0.0, c1 = 1.0, alpha = 0.0, A_bw = 0.0, beta_bw = 5.0, gamma_bw = 0.5)

# (path, axis label) for each compared observable. The path doubles as the
# DataFrame column name and the symbolic lookup key into the analysis solution.
const OBS = [
    ("model.J_eng.w(t)",            "engine speed ω_eng [rad/s]"),
    ("model.delta_w(t)",            "speed difference Δω [rad/s]"),
    ("model.isolator.phi_rel(t)",   "isolator twist φ_rel [rad]"),
]

fitted_row = CSV.read(FITTED_CSV, DataFrame)[1, :]
fitted = (; (k => fitted_row[k] for k in propertynames(fitted_row))...)
@info "Loaded calibrated parameters" fitted

# Run a TransientAnalysis over the tip-in harness with the six isolator knobs
# set through the operating-point overrides. `toggle_namespacing` strips the
# harness's own namespace so keys match the flattened system's `model.k1`, …
function run_tipin(params; stop = 2.0, saveat = 0.0005)
    harness = DrivelineSciML.TestDrivelineTipIn(; name = :h)
    m = toggle_namespacing(harness, false).model
    overrides = Dict{SymbolicT, SymbolicT}(
        m.k1 => params.k1, m.c1 => params.c1,
        m.alpha => params.alpha, m.A_bw => params.A_bw,
        m.beta_bw => params.beta_bw, m.gamma_bw => params.gamma_bw)
    result = TransientAnalysis(; model = harness, overrides, alg = ODEAlg.Tsit5(),
        abstol = 1e-8, reltol = 1e-8, start = 0.0, stop, saveat)
    sol = artifacts(result, :RawSolution)
    df = DataFrame(timestamp = sol.t)
    for (path, _) in OBS
        df[!, path] = sol[getproperty(result, path)]
    end
    return df
end

error_rms(a, b) = sqrt(mean(abs2, a .- b))

@info "Simulating truth isolator on tip-in"
df_truth = run_tipin(TRUTH)
@info "Simulating linear baseline on tip-in"
df_lin = run_tipin(LINEAR)
@info "Simulating calibrated isolator on tip-in"
df_cal = run_tipin(fitted)

println()
println("══════════════════════════════════════════════════════════════════════")
println("   Tip-in validation (unseen event) — linear vs calibrated vs truth")
println("══════════════════════════════════════════════════════════════════════")
@printf "  %-30s  %-12s  %-12s  %-12s\n" "observable" "linear RMSE" "calib RMSE" "improvement"
@printf "  %s\n" repeat("─", 72)
improvements = Float64[]
for (col, label) in OBS
    e_lin = error_rms(df_lin[!, col], df_truth[!, col])
    e_cal = error_rms(df_cal[!, col], df_truth[!, col])
    impr = 100 * (e_lin - e_cal) / e_lin
    push!(improvements, impr)
    @printf "  %-30s  %-12.4g  %-12.4g  %+10.1f%%\n" label e_lin e_cal impr
end
println("══════════════════════════════════════════════════════════════════════")

# Overlay plot: ω_eng prediction *error* (the ramp itself dwarfs the model
# differences), Δω zoomed on the tip-in transient, and the full φ_rel trace.
zoom = (0.4, 0.8)
plt = plot(layout = (3, 1), size = (1100, 1000), legend = :bottomright,
    plot_title = "Tip-in with 600 Hz ripple — linear vs calibrated vs truth",
    left_margin = 8Plots.mm, right_margin = 4Plots.mm,
    top_margin = 4Plots.mm, bottom_margin = 4Plots.mm)

w_col = OBS[1][1]
plot!(plt[1], df_lin.timestamp, df_lin[!, w_col] .- df_truth[!, w_col],
    lw = 1.5, color = :gray50, ls = :dot, label = "linear baseline")
plot!(plt[1], df_cal.timestamp, df_cal[!, w_col] .- df_truth[!, w_col],
    lw = 2, color = :red, ls = :dash, label = "calibrated")
title!(plt[1], "engine speed prediction error ω_eng − ω_eng_truth [rad/s]")
ylabel!(plt[1], "error [rad/s]")

for (i, (col, label)) in enumerate(OBS[2:end])
    in_zoom = i == 1 ? findall(t -> zoom[1] <= t <= zoom[2], df_truth.timestamp) :
                       eachindex(df_truth.timestamp)
    plot!(plt[i + 1], df_truth.timestamp[in_zoom], df_truth[in_zoom, col],
        lw = 2.5, color = :black, label = "truth")
    plot!(plt[i + 1], df_lin.timestamp[in_zoom], df_lin[in_zoom, col],
        lw = 1.5, color = :gray50, ls = :dot, label = "linear baseline")
    plot!(plt[i + 1], df_cal.timestamp[in_zoom], df_cal[in_zoom, col],
        lw = 2, color = :red, ls = :dash, label = "calibrated")
    title!(plt[i + 1], i == 1 ? "$label (zoom on tip-in)" : label)
    ylabel!(plt[i + 1], label)
end
xlabel!(plt[3], "time [s]")
outpath = joinpath(OUT_DIR, "validation_tipin.png")
savefig(plt, outpath)
@info "3-way comparison plot → $outpath"
