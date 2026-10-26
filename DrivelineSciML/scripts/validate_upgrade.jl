# Run every concrete Dyad analysis at its declared budget. Training writes only
# into the requested output directory; shipped calibration files stay reusable.
# JULIA_NUM_THREADS=2 julia +dyad-3.5.0-rc2 --project scripts/validate_upgrade.jl
# DYAD_UPGRADE_OUTPUT selects the output directory; DYAD_UPGRADE_ONLY is a
# comma-separated subset for retrying analyses after a failure.
using DrivelineSciML
using DyadInterface
using ModelingToolkit
using DyadModelOptimizer: search_space_names
include("workflow_checks.jl")

const OUTPUT = mkpath(abspath(get(ENV, "DYAD_UPGRADE_OUTPUT", mktempdir(; cleanup = false))))
const ONLY = Set(filter(!isempty, split(get(ENV, "DYAD_UPGRADE_ONLY", ""), ',')))
const FAILURES = String[]
const EXECUTED = Set{String}()
println("Validation output: ", OUTPUT, "; Julia ", VERSION, "; threads ", Threads.nthreads())

function validate_analysis(f, name)
    isempty(ONLY) || name in ONLY || return nothing
    push!(EXECUTED, name)
    println("START ", name); flush(stdout)
    started = time()
    try
        result = f()
        open(joinpath(OUTPUT, name * ".txt"), "w") do io
            println(io, "analysis=", name, " elapsed_s=", time() - started)
            raw = if hasproperty(result, :sol)
                result.sol
            elseif hasproperty(result, :r)
                nothing # Calibration exposes its optimizer result instead.
            else
                artifacts(result, :RawSolution)
            end
            if raw !== nothing
                println(io, "retcode=", raw.retcode, " samples=", length(raw.t), " end_s=", last(raw.t))
                require_simulation_success(raw, result.spec.stop, name)
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
        calibration === nothing || require_calibration_success(calibration, name)
        if calibration !== nothing && hasproperty(result.spec, :results_path) && !isempty(result.spec.results_path)
            artifacts(result, :ResultsExport)
        end
        println("PASS ", name, " elapsed_s=", time() - started)
        print(read(joinpath(OUTPUT, name * ".txt"), String)); flush(stdout)
        return result
    catch err
        push!(FAILURES, name)
        println("FAIL ", name, ": ", sprint(showerror, err, catch_backtrace())); flush(stdout)
        return nothing
    end
end

validate_analysis("TestTipInTorqueTransient") do
    DrivelineSciML.TestTipInTorqueTransient(; )
end

validate_analysis("TestDrivelineChirpTransient") do
    DrivelineSciML.TestDrivelineChirpTransient(; )
end

validate_analysis("TestDrivelineChirpMaxwellOnlyTransient") do
    DrivelineSciML.TestDrivelineChirpMaxwellOnlyTransient(; )
end

validate_analysis("TestDrivelineSlowCycleTransient") do
    DrivelineSciML.TestDrivelineSlowCycleTransient(; )
end

validate_analysis("TestDrivelineTipInTransient") do
    DrivelineSciML.TestDrivelineTipInTransient(; )
end

validate_analysis("DrivelineStage1CalibrationAnalysis") do
    DrivelineSciML.DrivelineStage1CalibrationAnalysis(; )
end

validate_analysis("DrivelineStage2CalibrationAnalysis") do
    println("INTERPRETATION: standalone Stage 2 fixes the nominal Maxwell branch; optimizer success does not establish parameter recovery. Use run_calibration.jl for the chained fit.")
    DrivelineSciML.DrivelineStage2CalibrationAnalysis(; )
end

isempty(FAILURES) || error("Failed analyses: $(join(FAILURES, ", "))")
isempty(setdiff(ONLY, EXECUTED)) || error("Unknown analyses requested: $(join(setdiff(ONLY, EXECUTED), ", "))")
