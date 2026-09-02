# Shared setup for the demo scripts (train / validate / animate). Including this
# file only defines constants and builder functions; the scripts decide what to
# build. Everything here is independent of the optimizer budget.

using MotorTemperatureSciML
using DyadInterface: symbolic_container
using DyadModelOptimizer
using DyadModelOptimizer: search_space_names
using OrdinaryDiffEqTsit5: Tsit5
using OptimizationOptimisers: Adam
using CSV, DataFrames
using Logging

const ASSETS_DIR = normpath(joinpath(@__DIR__, "..", "assets"))
const DATA_DIR   = joinpath(ASSETS_DIR, "data")

# Paderborn PMSM dataset profiles shipped in assets/data/ (see prepare_data.jl).
# 17 is the training profile; 60/62/74 are the held-out profiles the upstream
# TNN notebook evaluates on.
const TRAIN_PROFILE = 17
const TEST_PROFILES = (60, 62, 74)

# `TNNModel.MAX_TEMP`: the model's temperature states are T / MAX_TEMP ∈ [0, 1].
const MAX_TEMP = 200.0

# Training horizon. Profile 17 is ~2.2 h long; we train on the first 2 h and
# keep the tail as a small held-out stretch of the same profile.
const TRAIN_HORIZON_S = 7200.0

# ── Multiple-shooting segmentation ──────────────────────────────────────────
# WINDOW_S   — segment length. Shorter windows are cheaper per gradient but add
#              junction constraints; longer ones make each segment stiffer to
#              fit. 75 s (96 segments over 2 h) was the sweet spot of a
#              (window × batch) wall-clock sweep.
# BATCH_SIZE — segments per Adam step, solved in parallel across Julia threads
#              (must divide N_SEGMENTS). Keep it at 32 regardless of thread
#              count: the per-step cost is dominated by the full-batch
#              constraint Jacobian, so smaller batches cost nearly as much per
#              step and need more steps per epoch. On an 8P+16E-core desktop
#              8 threads is the fastest setting; see the README.
# BLOCK_SIZE — segments are sampled in contiguous blocks so every batch carries
#              coordinated junction terms; must divide BATCH_SIZE.
const WINDOW_S   = 75.0
const N_SEGMENTS = round(Int, TRAIN_HORIZON_S / WINDOW_S)   # 96
const BATCH_SIZE = 32
const BLOCK_SIZE = 4

# Stopping test of the augmented Lagrangian: the largest segment-junction gap
# must fall below this (in °C; the constraint itself is in normalized units).
# 0.2 °C is under the measurement noise of the winding channel. The
# OptimizationAuglag default (1e-8 normalized, i.e. 2 µK) sits below the ODE
# solver tolerance and can never be met.
const CONTINUITY_TOL_C = 0.2

const TARGET_COLS   = (:pm, :stator_yoke, :stator_tooth, :stator_winding)
const TARGET_LABELS = ("T_pm", "T_stator_yoke", "T_stator_tooth", "T_stator_winding")

profile_csv(id) = joinpath(DATA_DIR, "profile_$(id).csv")
profile_uri(id) = "dyad://MotorTemperatureSciML/data/profile_$(id).csv"
load_profile(id) = CSV.read(profile_csv(id), DataFrame)

"""
    build_system(profile_id = TRAIN_PROFILE)

Compiled `TestTNNProfile` system driven by `assets/data/profile_<id>.csv`.
The harness is instantiated with `data_file` overridden and pushed through its
`TransientAnalysis` so it is compiled exactly the way the Dyad pipeline does it
(the 1 s solve the analysis performs is discarded).
"""
function build_system(profile_id = TRAIN_PROFILE)
    harness = MotorTemperatureSciML.Models.Tests.TestTNNProfile(;
        name = :TestTNNProfile, data_file = profile_uri(profile_id))
    result = MotorTemperatureSciML.Models.Tests.TestTNNProfileAnalysis(;
        model = harness, stop = 1.0)
    return symbolic_container(result)
end

"""The four estimated (normalized) temperature states of the model."""
temperature_states(sys) = ntuple(i -> sys.model.thermal.T[i], 4)

"""Measured temperatures in the model's normalized state units, keyed like `depvars`."""
function normalized_targets(df)
    DataFrame(
        "timestamp" => df.time,
        "T_pm"      => df.pm             ./ MAX_TEMP,
        "T_sy"      => df.stator_yoke    ./ MAX_TEMP,
        "T_st"      => df.stator_tooth   ./ MAX_TEMP,
        "T_sw"      => df.stator_winding ./ MAX_TEMP,
    )
end

"""
    build_experiment(sys, df; name, tspan)

DMO `Experiment` fitting the model's normalized temperature states to the
measurements in `df` over `tspan` (default: the training horizon). The initial
state is warm-started from the measured t = 0 sample, as the PyTorch reference
does; the model default `T_init = 0.15` (30 °C) is 5–12 °C off the data, a bias
the networks would otherwise have to absorb.
"""
function build_experiment(sys, df; name,
        tspan = (0.0, min(TRAIN_HORIZON_S, df.time[end])))
    df_h = df[df.time .<= tspan[2], :]
    data = normalized_targets(df_h)
    T = temperature_states(sys)
    T0 = [df_h[1, c] / MAX_TEMP for c in TARGET_COLS]
    Experiment(data, sys;
        tspan, alg = Tsit5(), abstol = 1e-6, reltol = 1e-6, name,
        depvars = [T[1] => :T_pm, T[2] => :T_sy, T[3] => :T_st, T[4] => :T_sw],
        # Mean (not sum) of squares: keeps the loss O(1), matches nn.MSELoss,
        # and doesn't scramble AugLag's penalty schedule.
        loss = meansquaredl2loss,
        overrides = [sys.model.thermal.T_init[i] => T0[i] for i in 1:4],
        # `optimize = :aggressive` enables the DyadCompilerPasses codegen
        # rewrites (static arrays for the small NN input literals, fused
        # matmuls) — roughly 2× faster gradients on this model.
        prob_kwargs = (; fully_determined = true, optimize = :aggressive))
end

"""
    build_search_space(sys)

What the calibration tunes: the two network weight vectors (225 + 308) and
the four log-capacitances of `CapacitanceBlock`, 537 scalars in total. The
network vectors are already marked tunable by `NeuralNetworkBlock`, but DMO
ignores model-declared tunables as soon as a search space is given, so they
are listed explicitly next to `caps`. Bounds are open; the entry for `caps`
carries its starting value because Dyad stores parameter defaults as initial
conditions, which DMO does not read as defaults.
"""
function build_search_space(sys)
    open_bounds(p) = (fill(-Inf, length(p)), fill(Inf, length(p)))
    caps = sys.model.cap_block.caps
    return [
        sys.model.cond_net.nn.p  => open_bounds(sys.model.cond_net.nn.p),
        sys.model.ploss_net.nn.p => open_bounds(sys.model.ploss_net.nn.p),
        caps => (fill(-5.0, length(caps)), open_bounds(caps)...),
    ]
end

"""
    build_invprob(experiment, search_space)

`optimize_tunables = true` restricts the differentiated parameter buffer to the
search space (everything else stays a Float64 constant). `init_optimization =
true` strips the ODEProblem's initialization data: without it every per-segment
`remake` re-runs the initialization, which fights the shooting algorithm's own
segment initial states and stalls convergence ~8× at the same step budget.
"""
function build_invprob(experiment, search_space)
    # DMO warns that the model's own tunables are ignored once a search space
    # is given. The network vectors are re-listed in the search space, so
    # nothing is actually dropped — silence that one message.
    with_logger(DropMessage(current_logger(), "explicit tunables")) do
        InverseProblem(experiment, search_space;
            optimize_tunables = true, init_optimization = true)
    end
end

struct DropMessage{L <: AbstractLogger} <: AbstractLogger
    parent::L
    pattern::String
end
Logging.min_enabled_level(l::DropMessage) = Logging.min_enabled_level(l.parent)
Logging.shouldlog(l::DropMessage, args...) = Logging.shouldlog(l.parent, args...)
Logging.catch_exceptions(l::DropMessage) = Logging.catch_exceptions(l.parent)
function Logging.handle_message(l::DropMessage, level, message, args...; kwargs...)
    occursin(l.pattern, string(message)) && return nothing
    Logging.handle_message(l.parent, level, message, args...; kwargs...)
end

"""
    make_sms(; n_segments, batch_size, block_size, inner_lr, inner_epochs,
               outer_maxiters, inner_kwargs = (;), kwargs...)

`StochasticMultipleShooting`: the horizon is split into `n_segments` windows
with free initial states; each Adam step samples `batch_size` segments in
contiguous blocks of `block_size` and solves them in parallel on a pooled set
of integrators; segment-boundary continuity is enforced by the augmented
Lagrangian outer loop (at most `outer_maxiters` multiplier updates, `inner_epochs`
passes over the segments each; stops early once every junction gap is below
`CONTINUITY_TOL_C`).
"""
function make_sms(; n_segments, batch_size, block_size, inner_lr, inner_epochs,
        outer_maxiters, inner_kwargs = (;), auglag_kwargs = (;), kwargs...)
    StochasticMultipleShooting(;
        trajectories  = n_segments,
        batch_size, block_size,
        sampling      = :stratified_pairs,
        inner         = Adam(inner_lr),
        inner_kwargs  = merge((; epochs = inner_epochs), inner_kwargs),
        maxiters      = outer_maxiters,
        auglag_kwargs = merge((; ϵ_primal = CONTINUITY_TOL_C / MAX_TEMP), auglag_kwargs),
        ensemblealg   = DyadModelOptimizer.EnsemblePooled(),
        kwargs...)
end

# ── Persisting a calibration ────────────────────────────────────────────────
# The SMS optimization vector is [search-space values; per-segment initial
# states of segments 2..N]. Both parts are saved so the validation script can
# run standalone: the search-space part drives free-running simulations, the
# full vector reproduces the segment-continuity residuals.

const CALIBRATED_CSV = joinpath(DATA_DIR, "calibrated_params.csv")

function save_calibration(path, calres, invprob)
    names = string.(search_space_names(invprob))
    x_full = collect(calres.original.u)
    n_p = length(names)
    length(x_full) >= n_p || error("SMS state shorter than the search space?")
    isapprox(x_full[1:n_p], collect(calres.u)) ||
        @warn "search-space part of the SMS state differs from calres.u"
    stripe_names = ["u0_stripe_$(i)" for i in 1:(length(x_full) - n_p)]
    CSV.write(path, DataFrame(name = vcat(names, stripe_names), value = x_full))
    return path
end

function load_calibration(path)
    df = CSV.read(path, DataFrame)
    is_stripe = startswith.(df.name, "u0_stripe")
    return (; x = df.value[.!is_stripe], x_full = df.value, names = df.name[.!is_stripe])
end
