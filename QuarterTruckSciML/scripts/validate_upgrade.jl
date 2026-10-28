# Run every concrete Dyad analysis at its declared budget. Training writes only
# into the requested output directory; shipped calibration files stay reusable.
# JULIA_NUM_THREADS=2 julia +dyad-3.5.0 --project scripts/validate_upgrade.jl
# DYAD_UPGRADE_OUTPUT selects the output directory; DYAD_UPGRADE_ONLY is a
# comma-separated subset for retrying analyses after a failure.
# DYAD_UPGRADE_ADAM_MAXITERS / DYAD_UPGRADE_LBFGS_MAXITERS optionally select
# smaller training budgets; their defaults retain the declared 5000 / 200.
using QuarterTruckSciML
using DyadInterface
using ModelingToolkit
using DyadModelOptimizer: search_space_names

const OUTPUT = mkpath(abspath(get(ENV, "DYAD_UPGRADE_OUTPUT", mktempdir(; cleanup = false))))
const ONLY = Set(filter(!isempty, split(get(ENV, "DYAD_UPGRADE_ONLY", ""), ',')))
const FAILURES = String[]
println("Validation output: ", OUTPUT, "; Julia ", VERSION, "; threads ", Threads.nthreads())

function validate_analysis(f, name)
    isempty(ONLY) || name in ONLY || return nothing
    println("START ", name); flush(stdout)
    started = time()
    try
        result = f()
        if hasproperty(result, :r) && hasproperty(result.spec, :results_path) && !isempty(result.spec.results_path)
            artifacts(result, :ResultsExport)
        end
        open(joinpath(OUTPUT, name * ".txt"), "w") do io
            println(io, "analysis=", name, " elapsed_s=", time() - started)
            raw = if hasproperty(result, :sol)
                result.sol
            else
                try artifacts(result, :RawSolution) catch; nothing end
            end
            if raw !== nothing
                println(io, "retcode=", raw.retcode, " samples=", length(raw.t), " end_s=", last(raw.t))
                DyadInterface.SciMLBase.successful_retcode(raw) || error("ODE failed: $(raw.retcode)")
                sys = symbolic_container(result)
                states = ModelingToolkit.unknowns(sys)
                # Pure signal/network harnesses have no integrated states.
                isempty(states) && (states = vcat([ModelingToolkit.Symbolics.scalarize(eq.lhs) for eq in ModelingToolkit.observed(sys)]...))
                trajectories = [raw[state] for state in states]
                for (state, values) in zip(states, trajectories)
                    all(isfinite, values) || error("Nonfinite trajectory for $state")
                    println(io, state, " min=", minimum(values), " max=", maximum(values),
                        " rms=", sqrt(sum(abs2, values) / length(values)), " final=", last(values))
                end
                open(joinpath(OUTPUT, name * "-states.tsv"), "w") do table
                    println(table, join(["time"; string.(states)], '\t'))
                    for (i, t) in enumerate(raw.t)
                        println(table, join([t; [values[i] for values in trajectories]], '\t'))
                    end
                end
            end
            calibration = hasproperty(result, :r) ? result.r :
                          hasproperty(result, :result) ? result.result : nothing
            if calibration !== nothing
                all(isfinite, calibration.u) || error("Nonfinite fitted parameters")
                println(io, "optimization_retcode=", calibration.retcode,
                    " parameters=", collect(calibration.u))
                println(io, "parameter_names=", search_space_names(calibration.prob))
                hasproperty(calibration.original, :stats) && println(io, "optimization_stats=", calibration.original.stats)
                hasproperty(calibration, :likely_wrong) && println(io, "likely_wrong=", calibration.likely_wrong)
                if hasproperty(calibration.original, :objective)
                    println(io, "objective=", calibration.original.objective)
                end
            end
            if hasproperty(result, :predicted)
                errors = sqrt.(sum(abs2, result.predicted .- result.measured; dims=2) ./ size(result.measured, 2))
                println(io, "temperature_RMSE_C=", vec(errors))
            end
        end
        calibration = hasproperty(result, :r) ? result.r :
                      hasproperty(result, :result) ? result.result : nothing
        status = calibration !== nothing && !DyadInterface.SciMLBase.successful_retcode(calibration.retcode) ? "COMPLETED_NONCONVERGED" : "PASS"
        println(status, " ", name, " elapsed_s=", time() - started)
        print(read(joinpath(OUTPUT, name * ".txt"), String)); flush(stdout)
        return result
    catch err
        push!(FAILURES, name)
        println("FAIL ", name, ": ", sprint(showerror, err, catch_backtrace())); flush(stdout)
        return nothing
    end
end

validate_analysis("TestHalfSineBumpTransient") do
    QuarterTruckSciML.TestHalfSineBumpTransient(; )
end

validate_analysis("TestISO8608RoadTransient") do
    QuarterTruckSciML.TestISO8608RoadTransient(; )
end

validate_analysis("TestDenseISO8608RoadTransient") do
    QuarterTruckSciML.TestDenseISO8608RoadTransient(; )
end

validate_analysis("QuarterTruckReferenceTransient") do
    QuarterTruckSciML.QuarterTruckReferenceTransient(; )
end

validate_analysis("AnalysisFullNNSin") do
    QuarterTruckSciML.AnalysisFullNNSin(; )
end

validate_analysis("QuarterTruckCalibrationAnalysis") do
    QuarterTruckSciML.QuarterTruckCalibrationAnalysis(; )
end

validate_analysis("TruckFullNNTrainingAnalysis") do
    QuarterTruckSciML.TruckFullNNTrainingAnalysis(; optimizer_maxiters = parse(Int, get(ENV, "DYAD_UPGRADE_ADAM_MAXITERS", "5000")), results_path = joinpath(OUTPUT, "adam_weights.csv"))
end

validate_analysis("TruckFullNNTrainingAnalysisLBFGS") do
    QuarterTruckSciML.TruckFullNNTrainingAnalysisLBFGS(; optimizer_maxiters = parse(Int, get(ENV, "DYAD_UPGRADE_LBFGS_MAXITERS", "200")), initial_values_path = joinpath(OUTPUT, "adam_weights.csv"), results_path = joinpath(OUTPUT, "lbfgs_weights.csv"))
end

isempty(FAILURES) || error("Failed analyses: $(join(FAILURES, ", "))")
