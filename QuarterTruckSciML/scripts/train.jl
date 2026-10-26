# Run the declared 5000 Adam / 200 LBFGS schedule. Results go to ARGS[1]
# (or a fresh temporary directory), preserving the shipped pretrained weights.
# Runtime depends on the AD backend, solver and machine; see followup-validation.md.
using QuarterTruckSciML
using DyadInterface
using Logging
include("result_checks.jl")

# Keep iteration and loss evidence visible even in a redirected headless run.
mutable struct TrainingLogger <: Logging.AbstractLogger
    last_percent::Int
    started::Float64
end
Logging.min_enabled_level(::TrainingLogger) = Logging.LogLevel(-1)
Logging.shouldlog(::TrainingLogger, args...) = true
Logging.catch_exceptions(::TrainingLogger) = false
function Logging.handle_message(logger::TrainingLogger, level, message, mod, group, id, file, line; kwargs...)
    if level == Logging.LogLevel(-1) && hasproperty(message, :fraction)
        fraction = message.fraction
        if fraction !== nothing
            percent = floor(Int, 100 * fraction)
            if percent > logger.last_percent
                logger.last_percent = percent
                println("PROGRESS elapsed_s=", time()-logger.started, " ", message.name)
                flush(stdout)
            end
        end
    elseif level >= Logging.Info
        Logging.handle_message(Logging.ConsoleLogger(stderr), level, message, mod, group, id, file, line; kwargs...)
    end
end

const OUTPUT = mkpath(isempty(ARGS) ? mktempdir(; cleanup=false) : abspath(only(ARGS)))
const SHIPPED = realpath(joinpath(@__DIR__, "..", "assets", "data"))
realpath(OUTPUT) == SHIPPED && error("Choose a training output directory outside assets/data")
const ADAM_PATH = joinpath(OUTPUT, "adam_weights.csv")
const LBFGS_PATH = joinpath(OUTPUT, "lbfgs_weights.csv")
any(ispath, (ADAM_PATH, LBFGS_PATH)) && error("Output files already exist; choose a new directory")

function report_stage(label, result, elapsed)
    r = result.r
    @info label elapsed_s=elapsed retcode=r.retcode objective=r.original.objective stats=r.original.stats
    open(joinpath(OUTPUT, "training-results.txt"), "a") do io
        println(io, label, " elapsed_s=", elapsed, " retcode=", r.retcode,
            " objective=", r.original.objective, " stats=", r.original.stats,
            " likely_wrong=", r.likely_wrong)
        report_optimizer(io, r)
    end
    report_optimizer(stdout, r)
    check_finite_fit(r)
end

@info "Stage 1: Adam (5000 iterations, lr=1e-3)" output=OUTPUT
started = time()
adam = with_logger(TrainingLogger(-1, started)) do
    QuarterTruckSciML.TruckFullNNTrainingAnalysis(; name=:adam, results_path=ADAM_PATH)
end
report_stage("Adam", adam, time()-started)
# Adam's library adapter can return Default at the iteration limit. Preserve and
# report that status; a completed budget supplies a checkpoint for refinement,
# and is not a convergence claim. Other premature failures must stop the run.
if !DyadInterface.SciMLBase.successful_retcode(adam.r.retcode)
    string(adam.r.retcode) == "Default" && adam.r.original.stats.iterations == adam.spec.optimizer_maxiters ||
        error("Adam failed before completing its budget: $(adam.r.retcode)")
    @warn "Adam completed its budget without a success return code" retcode=adam.r.retcode
end
artifacts(adam, :ResultsExport)

@info "Stage 2: LBFGS refinement (up to 200 iterations)"
started = time()
lbfgs = with_logger(TrainingLogger(-1, started)) do
    QuarterTruckSciML.TruckFullNNTrainingAnalysisLBFGS(; name=:lbfgs,
        initial_values_path=ADAM_PATH, results_path=LBFGS_PATH)
end
report_stage("LBFGS", lbfgs, time()-started)
check_lbfgs_optimality(lbfgs.r)
artifacts(lbfgs, :ResultsExport)
@info "LBFGS met the gradient criterion; validate these new weights on the held-out road" weights=LBFGS_PATH
