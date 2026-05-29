"""
Validation: 3-way comparison on ISO 8608 Class A road excitation.

Simulates three models side-by-side against the nonlinear ground truth:
  • Linear baseline  (all 3 nonlinearities disabled)
  • Nonlinear truth  (tire cubic + friction + viscoelastic seat)
  • Full-NN gray-box (trained to jointly recover all 3 nonlinearities)

Reports per-observable RMS errors for linear-vs-truth and NN-vs-truth, and
renders overlay plots showing all three predictions.

Run from the package root:
    JULIAUP_SERVER="https://juliahub.com/juliabin" \\
    JULIAUP_DEPOT_PATH="\$HOME/.julia/juliaup-depots/juliahub.com" \\
    julia +dyad-3.0.0 --project scripts/validate.jl
"""

using QuarterTruckSciML
using ModelingToolkit
using OrdinaryDiffEqDefault
using CSV, DataFrames, Statistics, Printf
using Plots

const DATA_DIR = joinpath(@__DIR__, "..", "data")
const OUT_DIR  = joinpath(@__DIR__, "..")
const WEIGHTS_CSV = joinpath(DATA_DIR, "nn_weights_full_sin_lbfgs.csv")

const OBS = [
    (sys -> sys.model.tire.s,   "model.tire.s(t)",   "tire position [m]",          "m"),
    (sys -> sys.model.driver.s, "model.driver.s(t)", "driver position [m]",        "m"),
    (sys -> sys.model.driver.a, "model.driver.a(t)", "driver acceleration [m/s²]", "m/s²"),
]

weights_flat = Vector{Float64}(collect(CSV.read(WEIGHTS_CSV, DataFrame)[1, :]))
@info "Loaded $(length(weights_flat)) NN weights from $(basename(WEIGHTS_CSV))"

function simulate(harness; tspan=(0.0, 10.0), saveat=0.01, set_nn_weights=false)
    sys = mtkcompile(harness)
    overrides = set_nn_weights ? [sys.model.nn.p => weights_flat] : Pair[]
    prob = ODEProblem(sys, overrides, tspan; fully_determined=true)
    sol = solve(prob; saveat)
    df = DataFrame(timestamp = sol.t)
    for (getvar, colname, _, _) in OBS
        df[!, colname] = sol[getvar(sys)]
    end
    return sys, sol, df
end

signal_rms(x) = sqrt(mean(abs2, x .- mean(x)))
error_rms(a, b) = sqrt(mean(abs2, a .- b))

@info "Simulating linear baseline on ISO 8608 Class A"
_, _, df_lin = simulate(QuarterTruckSciML.TestQuarterTruckLinearISOA(; name=:h); tspan=(0.0, 10.0))

@info "Simulating nonlinear ground truth on ISO 8608 Class A"
_, _, df_gt  = simulate(QuarterTruckSciML.TestQuarterTruckNonlinearISOA(; name=:h); tspan=(0.0, 10.0))

@info "Simulating full-NN gray-box on ISO 8608 Class A"
_, _, df_nn  = simulate(QuarterTruckSciML.TestQuarterTruckFullNNISOA(; name=:h);
                        tspan=(0.0, 10.0), set_nn_weights=true)

errs = Dict{String, NamedTuple}()
for (_, col, _, _) in OBS
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
for (_, col, label, _) in OBS
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
for (i, (_, col, label, unit)) in enumerate(OBS)
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
