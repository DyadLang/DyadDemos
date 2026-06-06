#=
Generate the sin-driven training set for the full-NN gray-box truck.

Simulates the *nonlinear* ground truth (`TestQuarterTruckConfigurableFullSin`)
on a 2 Hz / 30 mm sine road, sampling tire.s, driver.s and driver.a at 100 Hz
over 5 s. Output is written in DyadData format (timestamp + `<path>(t)`
columns) to `assets/data/truck_sin_full_train.csv` — this is the file consumed by
`TruckFullNNTrainingAnalysis` and `TruckFullNNTrainingAnalysisLBFGS`.
=#

using QuarterTruckSciML
using DyadInterface: artifacts
using CSV, DataFrames

const OUTDIR = joinpath(@__DIR__, "..", "assets", "data")
isdir(OUTDIR) || mkpath(OUTDIR)

const OBS = [
    "model.tire.s(t)",
    "model.driver.s(t)",
    "model.driver.a(t)",
]

@info "Generating training set: sin-input nonlinear truck (all 3 nonlinearities active)"
result = QuarterTruckReferenceTransient()
sol = artifacts(result, :RawSolution)

df = DataFrame(timestamp = sol.t)
for o in OBS
    df[!, o] = sol[getproperty(result, o)]
end

outpath = joinpath(OUTDIR, "truck_sin_full_train.csv")
CSV.write(outpath, df)
@info "Wrote $(nrow(df)) rows × $(ncol(df)) cols → $outpath"
