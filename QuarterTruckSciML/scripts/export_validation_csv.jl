"""
Export the ISO 8608 Class A validation data as a CSV.

Mirrors the simulation logic in `validate.jl`, but instead of rendering the
3-panel overlay plot, it dumps a single tidy CSV containing the road input
plus all three observables (tire.s, driver.s, driver.a) for the linear model,
the nonlinear ground truth, and the NN-augmented gray-box.

Run from the package root:
    JULIAUP_SERVER="https://juliahub.com/juliabin" \\
    JULIAUP_DEPOT_PATH="\$HOME/.julia/juliaup-depots/juliahub.com" \\
    julia +dyad-3.0.0 --project scripts/export_validation_csv.jl
"""

using QuarterTruckSciML
using ModelingToolkit
using OrdinaryDiffEqDefault
using CSV, DataFrames

const DATA_DIR = joinpath(@__DIR__, "..", "data")
const OUT_DIR  = joinpath(@__DIR__, "..")
const WEIGHTS_CSV = joinpath(DATA_DIR, "nn_weights_full_sin_lbfgs.csv")

const OBS = [
    (sys -> sys.model.tire.s,   "tire_s"),
    (sys -> sys.model.driver.s, "driver_s"),
    (sys -> sys.model.driver.a, "driver_a"),
]

weights_flat = Vector{Float64}(collect(CSV.read(WEIGHTS_CSV, DataFrame)[1, :]))
@info "Loaded $(length(weights_flat)) NN weights from $(basename(WEIGHTS_CSV))"

function simulate(harness; tspan=(0.0, 10.0), saveat=0.01, set_nn_weights=false)
    sys = mtkcompile(harness)
    overrides = set_nn_weights ? [sys.model.nn.p => weights_flat] : Pair[]
    prob = ODEProblem(sys, overrides, tspan; fully_determined=true)
    sol = solve(prob; saveat)
    return sys, sol
end

@info "Simulating linear baseline on ISO 8608 Class A"
sys_lin, sol_lin = simulate(QuarterTruckSciML.TestQuarterTruckLinearISOA(; name=:h))

@info "Simulating nonlinear ground truth on ISO 8608 Class A"
sys_gt, sol_gt   = simulate(QuarterTruckSciML.TestQuarterTruckNonlinearISOA(; name=:h))

@info "Simulating full-NN gray-box on ISO 8608 Class A"
sys_nn, sol_nn   = simulate(QuarterTruckSciML.TestQuarterTruckFullNNISOA(; name=:h);
                            set_nn_weights=true)

# All three harnesses share the same ISO 8608 road, so pull the road trace
# from the ground-truth solution.
df = DataFrame(timestamp = sol_gt.t)
df.road_s = sol_gt[sys_gt.iso_road.y]

for (getvar, col) in OBS
    df[!, col * "_truth"]  = sol_gt[getvar(sys_gt)]
    df[!, col * "_linear"] = sol_lin[getvar(sys_lin)]
    df[!, col * "_nn"]     = sol_nn[getvar(sys_nn)]
end

outpath = joinpath(OUT_DIR, "validation_iso_a.csv")
CSV.write(outpath, df)
@info "Wrote $(nrow(df)) rows × $(ncol(df)) cols → $outpath"
