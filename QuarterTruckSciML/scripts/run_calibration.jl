"""
Run the parameter-calibration analysis and report recovered vs. true values.

Reads `data/calibration_measurements.csv` (produced by
`generate_calibration_data.jl`), invokes `QuarterTruckCalibrationAnalysis`,
and prints a side-by-side comparison of the nominal harness defaults, the
ground-truth perturbed values, and what the optimizer recovered.

Run from the package root:
    JULIAUP_SERVER="https://juliahub.com/juliabin" \\
    JULIAUP_DEPOT_PATH="\$HOME/.julia/juliaup-depots/juliahub.com" \\
    julia +dyad-3.0.0 --project scripts/run_calibration.jl
"""

using QuarterTruckSciML
using DyadInterface
using Printf

# Truth values are the same perturbations baked into
# `generate_calibration_data.jl` — keep these in sync if you change either.
const NOMINAL = (var"body.m" = 300.0,         var"tire_to_body.c" = 20e3,
                 var"tire_to_body.d" = 1500.0, var"friction_tb.F_c" = 500.0)
const TRUTH   = (var"body.m" = 315.0,         var"tire_to_body.c" = 22e3,
                 var"tire_to_body.d" = 1800.0, var"friction_tb.F_c" = 750.0)
const PARAMS  = ["model.body.m", "model.tire_to_body.c",
                 "model.tire_to_body.d", "model.friction_tb.F_c"]

@info "Running QuarterTruckCalibrationAnalysis (LBFGS, ≤100 iters)"
# The generated `QuarterTruckCalibrationAnalysis(; kwargs...)` shorthand already
# calls `run_analysis(QuarterTruckCalibrationAnalysisSpec(; kwargs...))`, so we
# get the solution back directly.
result = QuarterTruckSciML.QuarterTruckCalibrationAnalysis(; name=:cal)

# `CalibrationAnalysisSolution` wraps `(spec, r::CalibrationResult)`; the
# recovered parameter vector is `result.r.u`, in the order of
# `search_space_names`.
recovered_vec = collect(result.r.u)

println()
println("═════════════════════════════════════════════════════════════════════")
println("   Calibration result — recovered vs. truth")
println("═════════════════════════════════════════════════════════════════════")
@printf "  %-22s  %-12s  %-12s  %-12s  %-10s\n" "parameter" "nominal" "truth" "recovered" "Δ%"
@printf "  %s\n" repeat("─", 73)
for (i, name) in enumerate(PARAMS)
    key = Symbol(replace(name, "model." => ""))
    nom = NOMINAL[key]
    tru = TRUTH[key]
    rec = recovered_vec[i]
    pct = 100 * (rec - tru) / tru
    @printf "  %-24s  %-12.4g  %-12.4g  %-12.4g  %-+10.2f\n" name nom tru rec pct
end
println("═════════════════════════════════════════════════════════════════════")
