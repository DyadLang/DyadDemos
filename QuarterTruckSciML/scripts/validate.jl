#=
Validation: 3-way comparison on ISO 8608 Class A road excitation.

Simulates three models side-by-side against the nonlinear ground truth:
  • Linear baseline  (all 3 nonlinearities disabled)
  • Nonlinear truth  (tire cubic + friction + viscoelastic seat)
  • Full-NN gray-box (trained to jointly recover all 3 nonlinearities)

Each run is a `TransientAnalysis` over the harness, with the trained NN weights
supplied through the analysis `overrides` (the operating point) instead of a
hand-built `ODEProblem`. Reports per-observable RMS errors for linear-vs-truth
and NN-vs-truth, and renders overlay plots showing all three predictions.
=#

using QuarterTruckSciML
using DyadInterface: TransientAnalysis, artifacts, ODEAlg
using ModelingToolkit: toggle_namespacing, SymbolicT
using CSV, DataFrames, Statistics, Printf
using Plots

const DATA_DIR = joinpath(@__DIR__, "..", "assets", "data")
const OUT_DIR  = joinpath(@__DIR__, "..", "assets")
const WEIGHTS_CSV = joinpath(DATA_DIR, "nn_weights_full_sin_lbfgs.csv")

# (path, axis label, unit) for each compared observable. The path doubles as the
# DataFrame column name and the symbolic lookup key into the analysis solution.
const OBS = [
    ("model.tire.s(t)",   "tire position [m]",          "m"),
    ("model.driver.s(t)", "driver position [m]",        "m"),
    ("model.driver.a(t)", "driver acceleration [m/s²]", "m/s²"),
]

weights_flat = Vector{Float64}(collect(CSV.read(WEIGHTS_CSV, DataFrame)[1, :]))
@info "Loaded $(length(weights_flat)) NN weights from $(basename(WEIGHTS_CSV))"

# Run a TransientAnalysis over `harness` and collect the OBS observables.
# When `nn_weights` is given, the trained weights are injected as an
# operating-point override on the NN parameter vector. `toggle_namespacing`
# strips the harness's own namespace so the key matches the flattened system's
# `model.nn.p` — the one bit of plumbing the NN gray-box needs.
function run_transient(harness; nn_weights=nothing, tspan=(0.0, 10.0), saveat=0.01)
    overrides = isnothing(nn_weights) ? Dict{SymbolicT, SymbolicT}() :
        Dict{SymbolicT, SymbolicT}(toggle_namespacing(harness, false).model.nn.p => nn_weights)
    result = TransientAnalysis(; model=harness, overrides, alg=ODEAlg.Auto(),
                               start=tspan[1], stop=tspan[2], saveat)
    sol = artifacts(result, :RawSolution)
    df = DataFrame(timestamp = sol.t)
    for (path, _, _) in OBS
        df[!, path] = sol[getproperty(result, path)]
    end
    return df
end

signal_rms(x) = sqrt(mean(abs2, x .- mean(x)))
error_rms(a, b) = sqrt(mean(abs2, a .- b))

@info "Simulating linear baseline on ISO 8608 Class A"
df_lin = run_transient(QuarterTruckSciML.TestQuarterTruckLinearISOA(; name=:h))

@info "Simulating nonlinear ground truth on ISO 8608 Class A"
df_gt  = run_transient(QuarterTruckSciML.TestQuarterTruckNonlinearISOA(; name=:h))

@info "Simulating full-NN gray-box on ISO 8608 Class A"
df_nn  = run_transient(QuarterTruckSciML.TestQuarterTruckFullNNISOA(; name=:h);
                       nn_weights=weights_flat)

errs = Dict{String, NamedTuple}()
for (col, _, _) in OBS
    r = signal_rms(df_gt[!, col])
    e_lin = error_rms(df_lin[!, col], df_gt[!, col])
    e_nn  = error_rms(df_nn[!,  col], df_gt[!, col])
    errs[col] = (; r, e_lin, e_nn,
                   pct_lin = r > 0 ? 100 * e_lin / r : NaN,
                   pct_nn  = r > 0 ? 100 * e_nn  / r : NaN)
end

println()
println("══════════════════════════════════════════════════════════════════════")
println("   ISO 8608 Class A validation — linear vs NN vs nonlinear truth")
println("══════════════════════════════════════════════════════════════════════")
@printf "  %-28s  %-14s  %-14s  %-14s\n" "observable" "signal RMS" "linear err (%%)" "NN err (%%)"
@printf "  %s\n" repeat("─", 78)
for (col, label, _) in OBS
    e = errs[col]
    @printf "  %-28s  %-14.4g  %-14.2f  %-14.2f\n" label e.r e.pct_lin e.pct_nn
end
println("══════════════════════════════════════════════════════════════════════")

function fmt_rms(x, unit)
    if unit == "m"
        x < 1e-3 ? @sprintf("%.1f μm", x * 1e6) : @sprintf("%.2f mm", x * 1e3)
    elseif unit == "m/s²"
        @sprintf("%.3f m/s²", x)
    else
        @sprintf("%.3g %s", x, unit)
    end
end

plt = plot(layout=(3, 1), size=(1100, 1000), legend=:bottomright,
           plot_title="ISO 8608 Class A road — linear vs NN-augmented vs nonlinear model",
           left_margin=8Plots.mm, right_margin=4Plots.mm,
           top_margin=4Plots.mm, bottom_margin=4Plots.mm)
for (i, (col, label, unit)) in enumerate(OBS)
    e = errs[col]
    subtitle = "$label    — linear RMS err = $(fmt_rms(e.e_lin, unit)), NN RMS err = $(fmt_rms(e.e_nn, unit))"
    plot!(plt[i], df_gt.timestamp, df_gt[!, col],
          lw=2.5, color=:black,  label="nonlinear model")
    plot!(plt[i], df_lin.timestamp, df_lin[!, col],
          lw=1.5, color=:gray50, ls=:dot,  label="linear model")
    plot!(plt[i], df_nn.timestamp, df_nn[!, col],
          lw=2,   color=:red,    ls=:dash, label="NN augmented model")
    title!(plt[i], subtitle)
    ylabel!(plt[i], label)
end
xlabel!(plt[3], "time [s]")
outpath = joinpath(OUT_DIR, "validation_iso_a.png")
savefig(plt, outpath)
@info "3-way comparison plot → $outpath"
