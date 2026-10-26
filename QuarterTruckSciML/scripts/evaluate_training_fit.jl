# Independently replay exported weights against every committed training sample.
# Usage: julia --project scripts/evaluate_training_fit.jl /path/to/weights.csv
using QuarterTruckSciML
using DyadInterface
using ModelingToolkit: SymbolicT, toggle_namespacing
using CSV, DataFrames, Statistics, Printf

length(ARGS) == 1 || error("Pass one exported weights CSV filename")
weights_table = CSV.read(only(ARGS), DataFrame)
size(weights_table) == (1, 68) || error("Expected one row of 68 NN weights")
weights = Float64.(collect(weights_table[1, :]))
all(isfinite, weights) || error("Nonfinite NN weights")
data = CSV.read(joinpath(@__DIR__, "..", "assets", "data", "truck_sin_full_train.csv"), DataFrame)

harness = QuarterTruckSciML.TestQuarterTruckFullNNSin(; name=:h)
overrides = Dict{SymbolicT, SymbolicT}(
    toggle_namespacing(harness, false).model.scaled_nn.nn.p => weights)
started = time()
result = TransientAnalysis(; model=harness, overrides, alg=ODEAlg.Tsit5(),
    start=0.0, stop=5.0, saveat=0.01, abstol=1e-8, reltol=1e-8)
sol = artifacts(result, :RawSolution)
DyadInterface.SciMLBase.successful_retcode(sol) || error("Training replay failed: $(sol.retcode)")
all(u -> all(isfinite, u), sol.u) || error("Nonfinite training replay states")
length(sol.t) == nrow(data) && isapprox(sol.t, data.timestamp; rtol=0, atol=1e-12) ||
    error("Training sample times differ from replay times")
@printf("REPLAY retcode=%s samples=%d elapsed_s=%.17g weights=%s\n",
    string(sol.retcode), length(sol.t), time()-started, abspath(only(ARGS)))

squared_residuals = 0.0
for path in ["model.tire.s(t)", "model.driver.s(t)", "model.driver.a(t)"]
    measured = data[!, path]
    predicted = sol[getproperty(result, path)]
    all(isfinite, measured) && all(isfinite, predicted) || error("Nonfinite $path")
    residual = predicted .- measured
    global squared_residuals += sum(abs2, residual)
    rmse = sqrt(mean(abs2, residual))
    data_std = std(measured)
    @printf("%s data_std=%.17g rmse=%.17g max_abs=%.17g normalized_rmse=%.17g\n",
        path, data_std, rmse, maximum(abs, residual), rmse/data_std)
end
@printf("RECOMPUTED_L2_OBJECTIVE %.17g\n", sqrt(squared_residuals))
