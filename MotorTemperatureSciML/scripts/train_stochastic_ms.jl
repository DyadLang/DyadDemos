# Thermal Neural Network calibration with stochastic mini-batch multiple
# shooting under an augmented Lagrangian (DyadModelOptimizer's
# `StochasticMultipleShooting`).
#
# Run from the package root (segments in a batch solve in parallel across
# Julia threads; more threads is not always faster, see the README):
#
#   JULIA_NUM_THREADS=8 julia +dyad-3.3.0 --project scripts/train_stochastic_ms.jl
#
# Budget presets (TNN_BUDGET=quick|short|full, default full; see the README
# for what each buys):
#
#   TNN_BUDGET=short JULIA_NUM_THREADS=8 julia +dyad-3.3.0 --project scripts/train_stochastic_ms.jl
#
# Writes assets/data/calibrated_params.csv, consumed by validate_calibration.jl
# (which can also be `include`d right after this script in the same session).

include("common.jl")
using Printf
using Base.Threads: nthreads
using ADTypes, ForwardDiff

# ── Optimizer budget ─────────────────────────────────────────────────────────
# One "epoch" is a pass over all N_SEGMENTS segments, i.e. N_SEGMENTS ÷
# BATCH_SIZE Adam steps (3 at the defaults). The reference PyTorch run does
# 100 epochs of truncated BPTT over 512-sample chunks on the same profile
# (3200 cheap updates); 5 × 100 epochs here is 1500 much larger steps, each
# integrating 32 segments and differentiating through them.
#
# INNER_LR       — Adam step size. AugLag's penalty ρ grows over outer
#                  iterations, so a step size that is fine at ρ = 1 can
#                  diverge later; 1e-3 is safe.
# INNER_EPOCHS   — Adam epochs per outer iteration (per multiplier update).
# OUTER_MAXITERS — AugLag outer iterations (upper bound; the loop stops as
#                  soon as the junction gaps are below CONTINUITY_TOL_C). Each
#                  one tightens the continuity constraints; too few leaves a
#                  systematic gap at the junctions that a free-running
#                  simulation integrates into a large bias.
#
# Measured at 8 threads (free-running RMS on the training horizon, °C):
#   quick  1 ×   2 epochs,    6 steps, ~1 min incl. compile — pipeline check only
#   short 10 ×  12 epochs,  360 steps, ~5 min  — 4.1 / 0.8 / 0.9 / 3.1
#   full   5 × 100 epochs, 1500 steps, ~21 min — 0.42 / 0.42 / 0.37 / 0.60
# At the short budget, many cheap multiplier updates beat few long inner
# solves (3 × 38 epochs: 5.4 / 1.2 / 1.9 / 5.9 with a biased junction gap).
const BUDGET   = get(ENV, "TNN_BUDGET", "full")
const INNER_LR = 1e-3
const (INNER_EPOCHS, OUTER_MAXITERS) =
    BUDGET == "quick" ? (2, 1) :
    BUDGET == "short" ? (12, 10) :
    BUDGET == "full"  ? (100, 5) :
    error("TNN_BUDGET must be quick, short or full; got \"$BUDGET\"")

# ── Problem ──────────────────────────────────────────────────────────────────
df  = load_profile(TRAIN_PROFILE)
@info "Loaded training profile" profile_id = TRAIN_PROFILE rows = nrow(df) span_s = (df.time[1], df.time[end])

sys        = build_system(TRAIN_PROFILE)
experiment = build_experiment(sys, df; name = "profile_$(TRAIN_PROFILE)")
invprob    = build_invprob(experiment, build_search_space(sys))
alg        = make_sms(; n_segments = N_SEGMENTS, batch_size = BATCH_SIZE,
    block_size = BLOCK_SIZE, inner_lr = INNER_LR, inner_epochs = INNER_EPOCHS,
    outer_maxiters = OUTER_MAXITERS)

n_params = length(search_space_names(invprob))
steps_per_epoch = N_SEGMENTS ÷ BATCH_SIZE
@info "Training schedule" n_params N_SEGMENTS WINDOW_S BATCH_SIZE BLOCK_SIZE INNER_LR INNER_EPOCHS OUTER_MAXITERS total_adam_steps = OUTER_MAXITERS * INNER_EPOCHS * steps_per_epoch julia_threads = nthreads()

# ── Calibrate ────────────────────────────────────────────────────────────────
@info "Calibrating…"
calres = calibrate(invprob, alg; adtype = AutoForwardDiff())

# `Success` means every segment junction closed to within CONTINUITY_TOL_C
# before OUTER_MAXITERS ran out; `ConvergenceFailure` means it did not.
println()
@info "Calibration finished" elapsed_s = round(calres.elapsed; digits = 1) retcode = calres.retcode
@printf("  final AugLag objective = %.6e\n", calres.original.objective)
@printf("  outer iterations       = %d\n",   calres.original.stats.iterations)
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
save_calibration(CALIBRATED_CSV, calres, invprob)
@info "Saved calibrated parameters" path = CALIBRATED_CSV
@info "Next: include(\"scripts/validate_calibration.jl\") (or run it standalone)"
