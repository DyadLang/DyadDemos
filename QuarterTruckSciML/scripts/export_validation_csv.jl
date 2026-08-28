#=
Export the ISO 8608 Class A validation data as a CSV.

Mirrors the simulation logic in `validate.jl`, but instead of rendering the
3-panel overlay plot, it dumps a single tidy CSV containing the road input
plus all three observables (tire.s, driver.s, driver.a) for the linear model,
the nonlinear ground truth, and the NN-augmented gray-box.
=#

using QuarterTruckSciML
using DyadInterface: TransientAnalysis, artifacts, ODEAlg
using ModelingToolkit: toggle_namespacing, SymbolicT
using CSV, DataFrames

const DATA_DIR = joinpath(@__DIR__, "..", "assets", "data")
const OUT_DIR  = joinpath(@__DIR__, "..", "assets")
const WEIGHTS_CSV = joinpath(DATA_DIR, "nn_weights_full_sin_lbfgs.csv")

# (observable path, output column stem) for each compared signal.
const OBS = [
    ("model.tire.s(t)",   "tire_s"),
    ("model.driver.s(t)", "driver_s"),
    ("model.driver.a(t)", "driver_a"),
]

weights_flat = Vector{Float64}(collect(CSV.read(WEIGHTS_CSV, DataFrame)[1, :]))
@info "Loaded $(length(weights_flat)) NN weights from $(basename(WEIGHTS_CSV))"

# Run a TransientAnalysis over `harness` and return (result, raw_solution). When
# `nn_weights` is given, the trained weights are injected as an operating-point
# override on the NN parameter vector; `toggle_namespacing` strips the harness's
# own namespace so the key matches the flattened system's `model.scaled_nn.nn.p`.
function run_transient(harness; nn_weights=nothing, tspan=(0.0, 10.0), saveat=0.01)
    overrides = isnothing(nn_weights) ? Dict{SymbolicT, SymbolicT}() :
        Dict{SymbolicT, SymbolicT}(toggle_namespacing(harness, false).model.scaled_nn.nn.p => nn_weights)
    result = TransientAnalysis(; model=harness, overrides, alg=ODEAlg.Auto(),
                               start=tspan[1], stop=tspan[2], saveat)
    return result, artifacts(result, :RawSolution)
end

@info "Simulating linear baseline on ISO 8608 Class A"
res_lin, sol_lin = run_transient(QuarterTruckSciML.TestQuarterTruckLinearISOA(; name=:h))

@info "Simulating nonlinear ground truth on ISO 8608 Class A"
res_gt, sol_gt   = run_transient(QuarterTruckSciML.TestQuarterTruckNonlinearISOA(; name=:h))

@info "Simulating full-NN gray-box on ISO 8608 Class A"
res_nn, sol_nn   = run_transient(QuarterTruckSciML.TestQuarterTruckFullNNISOA(; name=:h);
                                 nn_weights=weights_flat)

# All three harnesses share the same ISO 8608 road, so pull the road trace
# from the ground-truth solution.
df = DataFrame(timestamp = sol_gt.t)
df.road_s = sol_gt[getproperty(res_gt, "iso_road.y(t)")]

for (path, col) in OBS
    df[!, col * "_truth"]  = sol_gt[getproperty(res_gt, path)]
    df[!, col * "_linear"] = sol_lin[getproperty(res_lin, path)]
    df[!, col * "_nn"]     = sol_nn[getproperty(res_nn, path)]
end

outpath = joinpath(OUT_DIR, "validation_iso_a.csv")
CSV.write(outpath, df)
@info "Wrote $(nrow(df)) rows × $(ncol(df)) cols → $outpath"
