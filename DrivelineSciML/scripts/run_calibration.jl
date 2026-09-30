#=
Run the two-stage calibration and report recovered vs. true values.

Stage 1  chirp data       → Maxwell branch (k1, c1) + Bouc-Wen scale (alpha),
                            fitting the FULL model so alpha absorbs the Bouc-Wen
                            tangent stiffness instead of biasing k1/c1
Stage 2  slow-cycle data  → Bouc-Wen (alpha, beta_bw, gamma_bw), Maxwell frozen
                            to the (de-biased) Stage 1 fit, alpha seeded from it

Reads the measurement CSVs produced by `generate_calibration_data.jl`,
invokes the generated calibration analyses, prints a side-by-side comparison
(nominal / truth / recovered / Δ%) and persists the fitted parameters to
`assets/data/calibrated_params.csv` for `validate.jl`.
=#

using DrivelineSciML
using DyadInterface
using CSV, DataFrames
using Printf

# Keep in sync with `generate_calibration_data.jl` (truth) and the component
# defaults in `dyad/driveline_model.dyad` (nominal). Order matches
# `search_space_names` of the respective analysis.
const NOMINAL = (k1 = 200.0, c1 = 2.0, alpha = 30.0, A_bw = 1.0, beta_bw = 3.0, gamma_bw = 0.3)
const TRUTH   = (k1 = 300.0, c1 = 1.0, alpha = 50.0, A_bw = 1.0, beta_bw = 5.0, gamma_bw = 0.5)

# `Tables.columnnames(r)` yields MTK-namespaced symbols (e.g. `model₊k1`) and
# the optimizer may reorder the search space, so map recovered values to bare
# parameter names instead of relying on position. (Uses the DataFrame interface
# already in scope; no extra imports.)
bare(name) = Symbol(last(split(string(name), ['.', '₊'])))
function fitdict(r)
    df = DataFrame(r)
    Dict(bare(c) => df[1, c] for c in names(df))
end

function report(title, names, recovered)
    println()
    println("═════════════════════════════════════════════════════════════════════")
    println("   $title — recovered vs. truth")
    println("═════════════════════════════════════════════════════════════════════")
    @printf "  %-18s  %-12s  %-12s  %-12s  %-10s\n" "parameter" "nominal" "truth" "recovered" "Δ%"
    @printf "  %s\n" repeat("─", 73)
    for (i, name) in enumerate(names)
        key = Symbol(replace(name, "model." => ""))
        nom = NOMINAL[key]
        tru = TRUTH[key]
        rec = recovered[i]
        pct = 100 * (rec - tru) / tru
        @printf "  %-20s  %-12.4g  %-12.4g  %-12.4g  %-+10.2f\n" name nom tru rec pct
    end
    println("═════════════════════════════════════════════════════════════════════")
end

@info "Stage 1: Maxwell branch + Bouc-Wen scale from chirp (k1, c1, alpha)"
res1 = DrivelineSciML.DrivelineStage1CalibrationAnalysis(; name = :stage1)
# `CalibrationAnalysisSolution` wraps `(spec, r::CalibrationResult)`; map the
# recovered values to parameter names (order-independent).
f1 = fitdict(res1.r)
k1_fit, c1_fit, alpha1_fit = f1[:k1], f1[:c1], f1[:alpha]
report("Stage 1", ["model.k1", "model.c1", "model.alpha"], [k1_fit, c1_fit, alpha1_fit])
@printf "  Maxwell relaxation time τ = c1/k1: fitted %.2f ms, truth %.2f ms\n" 1000c1_fit / k1_fit 1000TRUTH.c1 / TRUTH.k1

@info "Stage 2: Bouc-Wen element from slow cycling (alpha, beta_bw, gamma_bw; A_bw ≡ 1 by convention)"
# Harness parameters outside the Stage 2 search space act as fixed overrides,
# so constructing with the Stage 1 fit freezes the de-biased Maxwell branch.
# A_bw stays at 1.0: the flow rule is invariant under (A_bw → s·A_bw, alpha → alpha/s).
# alpha1_fit serves as a cross-check on the slow-cycle alpha rather than a seed,
# since alpha is a sharp start-independent minimum at full amplitude.
stage2_model = DrivelineSciML.TestDrivelineSlowCycle(;
    name = :TestDrivelineSlowCycle, k1 = k1_fit, c1 = c1_fit)
res2 = DrivelineSciML.DrivelineStage2CalibrationAnalysis(; name = :stage2, model = stage2_model)
f2 = fitdict(res2.r)
alpha_fit, beta_fit, gamma_fit = f2[:alpha], f2[:beta_bw], f2[:gamma_bw]
A_fit = 1.0
report("Stage 2", ["model.alpha", "model.beta_bw", "model.gamma_bw"],
    [alpha_fit, beta_fit, gamma_fit])
@printf "  Bouc-Wen saturation z_sat = A/β: fitted %.3f, truth %.3f\n" A_fit / beta_fit TRUTH.A_bw / TRUTH.beta_bw
@printf "  Max hysteresis torque α·z_sat: fitted %.2f Nm, truth %.2f Nm\n" alpha_fit * A_fit / beta_fit TRUTH.alpha * TRUTH.A_bw / TRUTH.beta_bw
@printf "  α cross-check: Stage 1 (chirp) %.2f vs Stage 2 (slow cycle) %.2f, truth %.2f\n" alpha1_fit alpha_fit TRUTH.alpha

outpath = joinpath(@__DIR__, "..", "assets", "data", "calibrated_params.csv")
CSV.write(outpath, DataFrame(
    k1 = k1_fit, c1 = c1_fit,
    alpha = alpha_fit, A_bw = A_fit, beta_bw = beta_fit, gamma_bw = gamma_fit))
@info "Fitted parameters written → $outpath"
