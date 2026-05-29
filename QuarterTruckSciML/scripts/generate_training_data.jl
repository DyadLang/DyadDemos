"""
Generate the sin-driven training set for the full-NN gray-box truck.

Simulates the *nonlinear* ground truth (`TestQuarterTruckConfigurableFullSin`)
on a 2 Hz / 30 mm sine road, sampling tire.s, driver.s and driver.a at 100 Hz
over 5 s. Output is written in DyadData format (timestamp + `<path>(t)`
columns) to `data/truck_sin_full_train.csv` — this is the file consumed by
`TruckFullNNTrainingAnalysis` and `TruckFullNNTrainingAnalysisLBFGS`.

Run from the package root:
    JULIAUP_SERVER="https://juliahub.com/juliabin" \\
    JULIAUP_DEPOT_PATH="\$HOME/.julia/juliaup-depots/juliahub.com" \\
    julia +dyad-3.0.0 --project scripts/generate_training_data.jl
"""

using QuarterTruckSciML
using ModelingToolkit
using OrdinaryDiffEqDefault
using CSV, DataFrames

const OUTDIR = joinpath(@__DIR__, "..", "data")
isdir(OUTDIR) || mkpath(OUTDIR)

const OBS = [
    (sys -> sys.model.tire.s,   "model.tire.s(t)"),
    (sys -> sys.model.driver.s, "model.driver.s(t)"),
    (sys -> sys.model.driver.a, "model.driver.a(t)"),
]

@info "Generating training set: sin-input nonlinear truck (all 3 nonlinearities active)"
@named h = QuarterTruckSciML.TestQuarterTruckConfigurableFullSin(
    amplitude = 0.03,
    frequency = 2.0,
    tire_k3 = 1e7,
    tire_compression_only = 1.0,
    friction_Fc = 500.0,
    seat_driver_n = 0.5,
)
sys = mtkcompile(h)
prob = ODEProblem(sys, [], (0.0, 5.0); fully_determined=true)
sol = solve(prob; saveat=0.01)

df = DataFrame(timestamp = sol.t)
for (path_fn, name) in OBS
    df[!, name] = sol[path_fn(sys)]
end

outpath = joinpath(OUTDIR, "truck_sin_full_train.csv")
CSV.write(outpath, df)
@info "Wrote $(nrow(df)) rows × $(ncol(df)) cols → $outpath"
