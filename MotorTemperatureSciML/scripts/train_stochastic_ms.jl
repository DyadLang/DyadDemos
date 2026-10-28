# Thermal Neural Network calibration with stochastic mini-batch multiple
# shooting under an augmented Lagrangian (DyadModelOptimizer's
# `StochasticMultipleShooting`).
#
# Run from the package root (segments in a batch solve in parallel across
# Julia threads; more threads is not always faster, see the README):
#
#   JULIA_NUM_THREADS=8 julia +dyad-3.5.0 --project scripts/train_stochastic_ms.jl
#
# Budget presets (TNN_BUDGET=quick|short|full, default full; see the README
# for what each buys):
#
#   TNN_BUDGET=short JULIA_NUM_THREADS=8 julia +dyad-3.5.0 --project scripts/train_stochastic_ms.jl
#
# Writes runs/training/calibrated_params.csv by default (--out-dir overrides).
# Pass that file to validate_calibration.jl with --calibration
# (which can also be `include`d right after this script in the same session).

include("common.jl")
using Printf
using SciMLBase: successful_retcode
using DyadModelOptimizer: compute_residual, calibration_parameters
using Base.Threads: nthreads
using ADTypes, ForwardDiff

training_paths = output_paths(ARGS; default_dir = joinpath(RUNS_DIR, "training"))
mkpath(training_paths.out_dir)
training_csv = joinpath(training_paths.out_dir, "calibrated_params.csv")

# ── Optimizer budget ─────────────────────────────────────────────────────────
# One "epoch" is a pass over all N_SEGMENTS segments, i.e. N_SEGMENTS ÷
# BATCH_SIZE Adam steps (3 at the defaults). The reference PyTorch run does
# 100 epochs of truncated BPTT over 512-sample chunks on the same 7200 s horizon
# (2900 cheap updates); 10 × 100 epochs here is up to 3000 larger steps, each
# integrating 32 segments and differentiating through them.
#
# INNER_LR       — initial Adam step size. After 50 epochs, make_sms decays
#                  the rate inversely with epoch squared to refine junctions
#                  below the 0.2 °C scale of a 1e-3 normalized-state update.
# INNER_EPOCHS   — Adam epochs per outer iteration (per multiplier update).
# OUTER_MAXITERS — AugLag outer iterations (upper bound; the loop stops as
#                  soon as the junction gaps are below CONTINUITY_TOL_C). Each
#                  one tightens the continuity constraints; too few leaves a
#                  systematic gap at the junctions that a free-running
#                  simulation integrates into a large bias.
#
# Budgets are upper bounds; all presets use the same 0.2 °C continuity
# criterion. The former six-update quick preset could never support a
# convergence claim. See docs/followup-validation.md for measured results.
const BUDGET   = get(ENV, "TNN_BUDGET", "full")
const INNER_LR = 1e-3
const (INNER_EPOCHS, OUTER_MAXITERS) =
    BUDGET == "quick" ? (12, 30) :
    BUDGET == "short" ? (50, 10) :
    BUDGET == "full"  ? (100, 10) :
    error("TNN_BUDGET must be quick, short or full; got \"$BUDGET\"")

# ── Problem ──────────────────────────────────────────────────────────────────
df  = load_profile(TRAIN_PROFILE)
@info "Loaded training profile" profile_id = TRAIN_PROFILE rows = nrow(df) span_s = (df.time[1], df.time[end])

sys        = build_system(TRAIN_PROFILE)
experiment = training_experiment(sys; name = "profile_$(TRAIN_PROFILE)")
invprob    = build_invprob(experiment, build_search_space(sys))
training_steps = Ref(0)
function training_progress(state, loss)
    training_steps[] += 1
    if training_steps[] % (N_SEGMENTS ÷ BATCH_SIZE) == 0
        @info "Training epoch" epoch = training_steps[] ÷ (N_SEGMENTS ÷ BATCH_SIZE) loss learning_rate = state.original.rule.eta
        flush(stderr)
    end
    return false
end
alg        = make_sms(; n_segments = N_SEGMENTS, batch_size = BATCH_SIZE,
    block_size = BLOCK_SIZE, learning_rate = INNER_LR, inner_epochs = INNER_EPOCHS,
    outer_maxiters = OUTER_MAXITERS, continuity_tol = CONTINUITY_TOL_C,
    inner_kwargs = (; callback = training_progress))

n_params = length(search_space_names(invprob))
steps_per_epoch = N_SEGMENTS ÷ BATCH_SIZE
@info "Training schedule" n_params N_SEGMENTS WINDOW_S BATCH_SIZE BLOCK_SIZE INNER_LR INNER_EPOCHS OUTER_MAXITERS total_adam_steps = OUTER_MAXITERS * INNER_EPOCHS * steps_per_epoch julia_threads = nthreads()

# ── Calibrate ────────────────────────────────────────────────────────────────
@info "Calibrating…"
flush(stderr)
calres = calibrate(invprob, alg; adtype = AutoForwardDiff())

# `Success` means every segment junction closed to within CONTINUITY_TOL_C
# before OUTER_MAXITERS ran out; `ConvergenceFailure` means it did not.
println()
@info "Calibration finished" elapsed_s = round(calres.elapsed; digits = 1) retcode = calres.retcode
@printf("  final AugLag objective = %.6e\n", calres.original.objective)
@printf("  outer iterations       = %d\n",   calres.original.stats.iterations)
@printf("  Adam updates           = %d\n",   training_steps[])
@printf("  inner f-evals          = %d\n",   calres.original.stats.fevals)
if !isnothing(calres.loss_history) && !isempty(calres.loss_history)
    println("  AugLag objective per outer iteration:")
    for (i, l) in enumerate(calres.loss_history)
        @printf("    outer %2d   %.6e\n", i, l)
    end
end

# The AugLag objective above mixes the data misfit with the penalty and
# multiplier terms and is evaluated with segment initial states that are
# stale right after a multiplier update — it is not the model's predictive
# accuracy. validate_calibration.jl simulates the calibrated model free-running
# over the full profile and the held-out profiles, which is the number that
# matters.
g = zeros(4 * (N_SEGMENTS - 1))
compute_residual(alg)(g, collect(calres.original.u), calibration_parameters(alg, invprob))
max_gap_C = maximum(abs, g) * MAX_TEMP
@info "Independent continuity check" max_gap_C tolerance_C = CONTINUITY_TOL_C
successful_retcode(calres.retcode) || error("Training failed: $(calres.retcode); no calibration exported")
all(isfinite, calres.original.u) || error("Training produced nonfinite parameters")
max_gap_C < CONTINUITY_TOL_C || error("Independent continuity check failed; no calibration exported")
save_calibration(training_csv, calres, invprob)
@info "Saved calibrated parameters" path = training_csv
@info "Validate this fit with scripts/validate_calibration.jl --calibration <file> --out-dir <directory>" file = training_csv directory = training_paths.out_dir
