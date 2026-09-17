# Shared setup for the demo scripts (train / validate / animate). The problem
# setup itself (system, experiment, search space, inverse problem, shooting
# algorithm, calibration I/O) lives in the package (src/story_analyses.jl and
# src/profiles.jl) and is shared with the Dyad analyses; this file only adds
# the constants the scripts agree on and a DataFrame adapter. Everything here
# is independent of the optimizer budget.

using MotorTemperatureSciML
using MotorTemperatureSciML: TRAIN_PROFILE, TEST_PROFILES, STORY_MAX_TEMP,
                             load_profile, read_parquet, build_system,
                             build_search_space, build_invprob, make_sms,
                             temperature_states, save_calibration, load_calibration
using DyadModelOptimizer
using DyadModelOptimizer: search_space_names
using CSV, DataFrames

include("output_paths.jl")

const RUNS_DIR = normpath(joinpath(@__DIR__, "..", "runs"))

const ASSETS_DIR = normpath(joinpath(@__DIR__, "..", "assets"))
const DATA_DIR   = joinpath(ASSETS_DIR, "data")

# `TNNModel.MAX_TEMP`: the model's temperature states are T / MAX_TEMP ∈ [0, 1].
const MAX_TEMP = STORY_MAX_TEMP

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
# 0.2 °C is under the measurement noise of the winding channel.
const CONTINUITY_TOL_C = 0.2

const TARGET_COLS   = (:pm, :stator_yoke, :stator_tooth, :stator_winding)
const TARGET_LABELS = ("T_pm", "T_stator_yoke", "T_stator_tooth", "T_stator_winding")

const CALIBRATED_CSV = joinpath(DATA_DIR, "calibrated_params.csv")

"""
    build_experiment(sys; name, tspan = (0.0, min(TRAIN_HORIZON_S, <profile end>)))

`MotorTemperatureSciML.build_experiment` with the scripts' default training
horizon. The harness already carries its measurements, so there is no data
argument and no way for the fitted data to disagree with the model driving it.
"""
function build_experiment(sys; name, tspan = nothing)
    (; t) = MotorTemperatureSciML.profile_data(sys)
    span = something(tspan, (0.0, min(TRAIN_HORIZON_S, t[end])))
    return MotorTemperatureSciML.build_experiment(sys; tspan = span, name)
end
