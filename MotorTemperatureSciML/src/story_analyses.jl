# Custom Dyad analyses that tell the demo's story from inside Dyad Builder:
#
#   TNNFreeRunAnalysis   — run the TNN free-running over one drive profile and
#                          compare with the measurements (untrained or calibrated)
#   TNNTrainingAnalysis  — calibrate the TNN with stochastic mini-batch multiple
#                          shooting under an augmented Lagrangian and record the
#                          training curves
#
# Both are base ("partial") analyses declared in dyad/TNNAnalyses.dyad; the
# story itself is the set of derived analyses in dyad/Story/. The implementation
# mirrors scripts/common.jl so a Builder run and a script run fit the same
# problem.

using DyadInterface
using DyadInterface: AbstractAnalysisSpec, AbstractAnalysisSolution,
                     AnalysisSolutionMetadata, ArtifactMetadata, ArtifactType,
                     PlotlyVisualizationSpec, simplify_model
using DyadModelOptimizer
using DyadModelOptimizer: search_space_names, compute_residual, calibration_parameters
using ModelingToolkit: ModelingToolkit, SymbolicT
using OrdinaryDiffEqTsit5: Tsit5
using OptimizationOptimisers: Adam
using ADTypes: AutoForwardDiff
using ForwardDiff: ForwardDiff
using DataFrames: DataFrame, nrow
using CSV: CSV
using DyadData: DyadData
using Statistics: mean
using LinearAlgebra: norm
using Logging

# `TNNModel.MAX_TEMP` (structural, default 200): the thermal states are T / MAX_TEMP.
const STORY_MAX_TEMP = 200.0

const CHANNEL_KEYS   = (:T_pm, :T_sy, :T_st, :T_sw)
const CHANNEL_LABELS = ("Permanent magnet", "Stator yoke", "Stator tooth", "Stator winding")
const CHANNEL_SHORT  = ("T_pm", "T_stator_yoke", "T_stator_tooth", "T_stator_winding")

# ── Shared problem setup ─────────────────────────────────────────────────────

"""
    profile_data(sys) -> (; t, meas)

Time grid [s] and the 4 × N measured temperatures [°C] of the drive profile the
harness was built with, read from the `interp_meas` interpolator parameter, so
an analysis always fits the data its model is driven by.
"""
function profile_data(sys)
    itp = ModelingToolkit.getdefault(sys.interp_meas.interpolator)
    return (; t = collect(Float64, itp.t), meas = Matrix{Float64}(itp.u))
end

temperature_states(sys) = ntuple(i -> sys.model.thermal.T[i], 4)

function normalized_targets(t, meas)
    DataFrame("timestamp" => t,
        (string(k) => meas[i, :] ./ STORY_MAX_TEMP for (i, k) in enumerate(CHANNEL_KEYS))...)
end

function build_experiment(sys, t, meas, spec; tspan, name)
    keep = t .<= tspan[2]
    data = normalized_targets(t[keep], meas[:, keep])
    T = temperature_states(sys)
    # Warm start from the first measured sample; the model default (30 °C) is
    # 5–12 °C off the data and the networks would have to absorb that bias.
    T0 = meas[:, 1] ./ STORY_MAX_TEMP
    overrides = vcat([sys.model.thermal.T_init[i] => T0[i] for i in 1:4],
                     [k => v for (k, v) in spec.overrides])
    Experiment(data, sys;
        tspan, alg = Tsit5(), abstol = spec.abstol, reltol = spec.reltol, name,
        depvars = [T[i] => k for (i, k) in enumerate(CHANNEL_KEYS)],
        loss = meansquaredl2loss,
        overrides,
        prob_kwargs = (; fully_determined = true, optimize = :aggressive))
end

# Two network weight vectors (225 + 308) and the four log-capacitances.
function build_search_space(sys)
    open_bounds(p) = (fill(-Inf, length(p)), fill(Inf, length(p)))
    caps = sys.model.cap_block.caps
    return [
        sys.model.cond_net.nn.p  => open_bounds(sys.model.cond_net.nn.p),
        sys.model.ploss_net.nn.p => open_bounds(sys.model.ploss_net.nn.p),
        caps => (fill(-5.0, length(caps)), open_bounds(caps)...),
    ]
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

function build_invprob(experiment, search_space)
    # The network vectors are re-listed in the search space, so DMO's "explicit
    # tunables are ignored" warning is noise here.
    with_logger(DropMessage(current_logger(), "explicit tunables")) do
        InverseProblem(experiment, search_space;
            optimize_tunables = true, init_optimization = true)
    end
end

"""Free-running simulation sampled on `t`, as a 4 × N matrix in °C."""
function free_running(sys, experiment, invprob, x, t)
    T = temperature_states(sys)
    tspan = (0.0, t[end])
    sol = isnothing(x) ? simulate(experiment, invprob; tspan, saveat = t) :
                         simulate(experiment, invprob, x; tspan, saveat = t)
    pred = Matrix{Float64}(undef, 4, length(t))
    for i in 1:4
        pred[i, :] .= sol(t; idxs = T[i]).u .* STORY_MAX_TEMP
    end
    return sol, pred
end

rms(r) = sqrt(mean(abs2, r))

# ── Files ────────────────────────────────────────────────────────────────────

"""Resolve a `dyad://` URI or a path (relative to the working directory)."""
function resolve_story_path(uri::AbstractString)
    startswith(uri, "dyad://") ? DyadData.resolve_dyad_uri(uri[8:end]) : abspath(uri)
end

# The optimizer state is [search-space values; segment initial states]. Both
# parts are saved so the continuity residuals can be reproduced later.
function save_calibration(path, calres, invprob)
    names = string.(search_space_names(invprob))
    x_full = collect(calres.original.u)
    n_p = length(names)
    length(x_full) >= n_p || error("Optimizer state shorter than the search space?")
    stripe_names = ["u0_stripe_$(i)" for i in 1:(length(x_full) - n_p)]
    mkpath(dirname(path))
    CSV.write(path, DataFrame(name = vcat(names, stripe_names), value = x_full))
    return path
end

"""Search-space values from a calibration CSV, in the order `invprob` expects."""
function load_calibration(path, invprob)
    isfile(path) || error("Calibration not found: `$path`. Run a TNNTrainingAnalysis " *
                          "with `results_path` pointing here, or use the shipped " *
                          "dyad://MotorTemperatureSciML/data/calibrated_params.csv.")
    df = CSV.read(path, DataFrame)
    values = Dict(String(n) => v for (n, v) in zip(df.name, df.value))
    return [get(values, n) do
                error("Calibration `$path` has no entry for `$n`")
            end for n in string.(search_space_names(invprob))]
end

function reference_predictions(uri, n)
    isempty(uri) && return nothing
    path = resolve_story_path(uri)
    isfile(path) || error("Reference predictions not found: `$path`")
    pt = DataFrame(profile_table(path); copycols = true)
    cols = (:pm_pred, :stator_yoke_pred, :stator_tooth_pred, :stator_winding_pred)
    ref = fill(NaN, 4, n)
    m = min(n, nrow(pt))
    for (i, c) in enumerate(cols)
        ref[i, 1:m] .= pt[1:m, c]
    end
    return ref
end

# ══════════════════════════════════════════════════════════════════════════════
# TNNFreeRunAnalysis
# ══════════════════════════════════════════════════════════════════════════════

abstract type AbstractTNNFreeRunAnalysisSpec <: AbstractAnalysisSpec end

"""
    TNNFreeRunAnalysis(; model, calibration = "", reference = "", train_horizon = 7200,
                         stop = 0, abstol = 1e-6, reltol = 1e-6)

Run the Thermal Neural Network free-running (a plain ODE, no per-segment
resets) over the drive profile its `TestTNNProfile` harness is built with, and
compare with the measured temperatures.

  - `calibration`: CSV of calibrated parameters (a `dyad://` URI or path). Empty
    runs the untrained model with its initial weights.
  - `reference`: optional Parquet of PyTorch reference predictions to overlay.
  - `train_horizon`: end of the training horizon [s], marked on the plots; 0 hides it.
  - `stop`: simulation end [s]; 0 runs the full profile.
"""
@kwdef struct TNNFreeRunAnalysisSpec{M} <: AbstractTNNFreeRunAnalysisSpec
    name::Symbol = :TNNFreeRunAnalysis
    model::M
    overrides::Dict{SymbolicT, SymbolicT} = Dict{SymbolicT, SymbolicT}()
    calibration::String = ""
    reference::String = ""
    train_horizon::Float64 = 7200.0
    stop::Float64 = 0.0
    abstol::Float64 = 1e-6
    reltol::Float64 = 1e-6
end

struct TNNFreeRunAnalysisSolution{SP, S, SYS} <: AbstractAnalysisSolution
    spec::SP
    sol::S
    sys::SYS
    t::Vector{Float64}
    measured::Matrix{Float64}
    predicted::Matrix{Float64}
    reference::Union{Nothing, Matrix{Float64}}
    trained::Bool
end

function DyadInterface.run_analysis(spec::TNNFreeRunAnalysisSpec)
    sys = simplify_model(spec.model)
    (; t, meas) = profile_data(sys)
    tstop = spec.stop > 0 ? min(spec.stop, t[end]) : t[end]
    keep = t .<= tstop
    t, meas = t[keep], meas[:, keep]

    experiment = build_experiment(sys, t, meas, spec; tspan = (0.0, tstop), name = "free_run")
    invprob = build_invprob(experiment, build_search_space(sys))

    trained = !isempty(spec.calibration)
    x = trained ? load_calibration(resolve_story_path(spec.calibration), invprob) : nothing
    @info "TNNFreeRunAnalysis: simulating" trained tstop
    sol, pred = free_running(sys, experiment, invprob, x, t)
    ref = reference_predictions(spec.reference, length(t))

    return TNNFreeRunAnalysisSolution(spec, sol, sys, t, meas, pred, ref, trained)
end

TNNFreeRunAnalysis(; kwargs...) = run_analysis(TNNFreeRunAnalysisSpec(; kwargs...))

DyadInterface.symbolic_container(sol::TNNFreeRunAnalysisSolution) = sol.sys

function DyadInterface.AnalysisSolutionMetadata(sol::TNNFreeRunAnalysisSolution)
    what = sol.trained ? "calibrated" : "untrained"
    artifacts = [
        ArtifactMetadata(:SimulationSolutionPlot, ArtifactType.PlotlyPlot,
            "Prediction vs measured",
            "Free-running $(what) TNN against the measured temperatures, one panel per channel."),
        ArtifactMetadata(:ResidualPlot, ArtifactType.PlotlyPlot,
            "Prediction error",
            "Prediction minus measurement over time, one panel per channel."),
        ArtifactMetadata(:SimulationSolutionTable, ArtifactType.DataFrame,
            "Prediction table", "Time, measured and predicted temperatures [°C]."),
        ArtifactMetadata(:ErrorTable, ArtifactType.DataFrame,
            "RMS error table",
            "RMS prediction error [°C] per channel, split at the training horizon."),
        ArtifactMetadata(:RawSolution, ArtifactType.Native,
            "Raw ODE solution", "The free-running ODE solution."),
        ArtifactMetadata(:SimplifiedSystem, ArtifactType.Native,
            "Simplified system", "The structurally simplified model."),
    ]
    AnalysisSolutionMetadata(artifacts, Symbol[])
end

function prediction_table(sol)
    df = DataFrame("t" => sol.t)
    for (i, s) in enumerate(CHANNEL_SHORT)
        df[!, "$(s)_measured"] = sol.measured[i, :]
        df[!, "$(s)_predicted"] = sol.predicted[i, :]
        isnothing(sol.reference) || (df[!, "$(s)_reference"] = sol.reference[i, :])
    end
    return df
end

function error_table(sol)
    th = sol.spec.train_horizon
    split = th > 0 && sol.t[end] > th
    masks = split ? ("training horizon" => sol.t .<= th, "held-out tail" => sol.t .> th) :
                    ("full profile" => trues(length(sol.t)),)
    rows = DataFrame(window = String[], channel = String[], rms_error_C = Float64[])
    for (label, m) in masks, i in 1:4
        push!(rows, (label, CHANNEL_SHORT[i], rms(sol.predicted[i, m] .- sol.measured[i, m])))
    end
    return rows
end

function DyadInterface.artifacts(sol::TNNFreeRunAnalysisSolution, name::Symbol)
    if name == :SimulationSolutionPlot
        fit_figure(sol)
    elseif name == :ResidualPlot
        residual_figure(sol)
    elseif name == :SimulationSolutionTable
        prediction_table(sol)
    elseif name == :ErrorTable
        error_table(sol)
    elseif name == :RawSolution
        sol.sol
    elseif name == :SimplifiedSystem
        sol.sys
    else
        error("Artifact $name not recognized for TNNFreeRunAnalysis")
    end
end

DyadInterface.customizable_visualization(::TNNFreeRunAnalysisSolution, ::PlotlyVisualizationSpec) = missing

function Base.show(io::IO, sol::TNNFreeRunAnalysisSolution)
    print(io, "TNNFreeRunAnalysisSolution (", sol.trained ? "calibrated" : "untrained",
        ", ", length(sol.t), " samples over ", round(sol.t[end]; digits = 1), " s)")
end
function Base.show(io::IO, ::MIME"text/plain", sol::TNNFreeRunAnalysisSolution)
    show(io, sol); println(io)
    show(io, MIME"text/plain"(), error_table(sol))
end

# ══════════════════════════════════════════════════════════════════════════════
# TNNTrainingAnalysis
# ══════════════════════════════════════════════════════════════════════════════

abstract type AbstractTNNTrainingAnalysisSpec <: AbstractAnalysisSpec end

"""
    TNNTrainingAnalysis(; model, train_horizon = 7200, window = 75, batch_size = 32,
                          block_size = 4, learning_rate = 1e-3, inner_epochs = 2,
                          outer_maxiters = 1, continuity_tol = 0.2, results_path = "",
                          abstol = 1e-6, reltol = 1e-6)

Calibrate the Thermal Neural Network on the profile its harness is built with,
using `StochasticMultipleShooting`: the horizon `[0, train_horizon]` is cut into
segments of `window` seconds with free initial states, every Adam step samples
`batch_size` segments in contiguous blocks of `block_size`, and continuity at
the segment junctions is enforced by an augmented Lagrangian outer loop (at
most `outer_maxiters` multiplier updates of `inner_epochs` Adam epochs each,
stopping once every junction gap is below `continuity_tol` °C).

Adam steps run segments in parallel across Julia threads. The training curves
are recorded per Adam step and per outer iteration. If `results_path` is set
the calibrated parameters are written there (CSV), ready for a
`TNNFreeRunAnalysis` with `calibration = results_path`.
"""
@kwdef struct TNNTrainingAnalysisSpec{M} <: AbstractTNNTrainingAnalysisSpec
    name::Symbol = :TNNTrainingAnalysis
    model::M
    overrides::Dict{SymbolicT, SymbolicT} = Dict{SymbolicT, SymbolicT}()
    train_horizon::Float64 = 7200.0
    window::Float64 = 75.0
    batch_size::Int = 32
    block_size::Int = 4
    learning_rate::Float64 = 1e-3
    inner_epochs::Int = 2
    outer_maxiters::Int = 1
    continuity_tol::Float64 = 0.2
    results_path::String = ""
    abstol::Float64 = 1e-6
    reltol::Float64 = 1e-6
end

struct TNNTrainingAnalysisSolution{SP, R, SYS, S} <: AbstractAnalysisSolution
    spec::SP
    sys::SYS
    result::R
    steps::DataFrame          # one row per Adam step
    outer::DataFrame          # one row per augmented-Lagrangian outer iteration
    continuity::Matrix{Float64}   # 4 × (n_segments − 1) junction gaps [°C]
    sol::S
    t::Vector{Float64}
    measured::Matrix{Float64}
    predicted::Matrix{Float64}
    n_segments::Int
    elapsed::Float64
    results_path::String
end

n_segments(spec::TNNTrainingAnalysisSpec) = round(Int, spec.train_horizon / spec.window)

function check_schedule(spec::TNNTrainingAnalysisSpec)
    n = n_segments(spec)
    n >= 2 || error("train_horizon / window must give at least 2 segments, got $n")
    n % spec.batch_size == 0 ||
        error("batch_size ($(spec.batch_size)) must divide the number of segments ($n)")
    spec.batch_size % spec.block_size == 0 ||
        error("block_size ($(spec.block_size)) must divide batch_size ($(spec.batch_size))")
    return n
end

function DyadInterface.run_analysis(spec::TNNTrainingAnalysisSpec)
    n_seg = check_schedule(spec)
    sys = simplify_model(spec.model)
    (; t, meas) = profile_data(sys)
    horizon = min(spec.train_horizon, t[end])

    experiment = build_experiment(sys, t, meas, spec; tspan = (0.0, horizon), name = "training")
    invprob = build_invprob(experiment, build_search_space(sys))

    # Per-Adam-step and per-outer-iteration records.
    steps = DataFrame(step = Int[], outer = Int[], loss = Float64[], grad_norm = Float64[])
    outer = DataFrame(outer = Int[], loss = Float64[], r_primal = Float64[],
        r_dual = Float64[], rho = Float64[], lambda_norm = Float64[])
    outer_idx = Ref(1)
    function inner_cb(state, loss)
        gnorm = try norm(state.grad) catch; NaN end
        push!(steps, (nrow(steps) + 1, outer_idx[], float(loss), float(gnorm)))
        return false
    end
    function outer_cb(state, loss, args...)
        s = state.original
        field(nm) = try float(getproperty(s, nm)) catch; NaN end
        λ = try norm(s.λ) catch; NaN end
        push!(outer, (outer_idx[], float(loss), field(:r_primal), field(:r_dual), field(:ρ), λ))
        @info "TNNTrainingAnalysis: outer iteration $(outer_idx[]) done" loss max_gap_C = field(:r_primal) * STORY_MAX_TEMP
        outer_idx[] += 1
        return false
    end

    alg = StochasticMultipleShooting(;
        trajectories  = n_seg,
        batch_size    = spec.batch_size,
        block_size    = spec.block_size,
        sampling      = :stratified_pairs,
        inner         = Adam(spec.learning_rate),
        inner_kwargs  = (; epochs = spec.inner_epochs, callback = inner_cb),
        maxiters      = spec.outer_maxiters,
        auglag_kwargs = (; ϵ_primal = spec.continuity_tol / STORY_MAX_TEMP),
        ensemblealg   = DyadModelOptimizer.EnsemblePooled(),
        callback      = outer_cb)

    steps_per_epoch = n_seg ÷ spec.batch_size
    @info "TNNTrainingAnalysis: calibrating" n_params = length(search_space_names(invprob)) n_segments = n_seg window_s = spec.window batch_size = spec.batch_size total_adam_steps = spec.outer_maxiters * spec.inner_epochs * steps_per_epoch threads = Threads.nthreads()
    calres = calibrate(invprob, alg; adtype = AutoForwardDiff())
    @info "TNNTrainingAnalysis: finished" retcode = calres.retcode elapsed_s = round(calres.elapsed; digits = 1)

    # Junction gaps g_k = T_end[k] − T_0[k+1] of the shooting fit, in °C.
    g = zeros(4 * (n_seg - 1))
    compute_residual(alg)(g, collect(calres.original.u), calibration_parameters(alg, invprob))
    continuity = reshape(g, 4, n_seg - 1) .* STORY_MAX_TEMP

    # Free-running check over the whole profile with the calibrated parameters.
    sol, pred = free_running(sys, experiment, invprob, collect(calres.u), t)

    results_path = isempty(spec.results_path) ? "" : resolve_story_path(spec.results_path)
    if !isempty(results_path)
        save_calibration(results_path, calres, invprob)
        @info "TNNTrainingAnalysis: saved calibrated parameters" path = results_path
    end

    return TNNTrainingAnalysisSolution(spec, sys, calres, steps, outer, continuity,
        sol, t, meas, pred, n_seg, float(calres.elapsed), results_path)
end

TNNTrainingAnalysis(; kwargs...) = run_analysis(TNNTrainingAnalysisSpec(; kwargs...))

DyadInterface.symbolic_container(sol::TNNTrainingAnalysisSolution) = sol.sys

function DyadInterface.AnalysisSolutionMetadata(sol::TNNTrainingAnalysisSolution)
    artifacts = [
        ArtifactMetadata(:SimulationSolutionPlot, ArtifactType.PlotlyPlot,
            "Training curves",
            "Augmented-Lagrangian objective per Adam step, junction-gap residual and penalty per outer iteration."),
        ArtifactMetadata(:FitPlot, ArtifactType.PlotlyPlot,
            "Fit after training",
            "Free-running prediction of the calibrated TNN against the measured temperatures."),
        ArtifactMetadata(:ContinuityPlot, ArtifactType.PlotlyPlot,
            "Segment continuity",
            "Junction gaps between consecutive shooting segments after calibration [°C]."),
        ArtifactMetadata(:LossTable, ArtifactType.DataFrame,
            "Loss per Adam step", "Objective and gradient norm at every Adam step."),
        ArtifactMetadata(:OuterIterationTable, ArtifactType.DataFrame,
            "Outer iterations",
            "Objective, primal/dual residuals, penalty and multiplier norm per outer iteration."),
        ArtifactMetadata(:ErrorTable, ArtifactType.DataFrame,
            "RMS error table",
            "Free-running RMS error [°C] per channel, split at the training horizon."),
        ArtifactMetadata(:CalibrationResult, ArtifactType.Native,
            "Calibration result", "The DyadModelOptimizer `CalibrationResult`."),
    ]
    if !isempty(sol.results_path)
        push!(artifacts, ArtifactMetadata(:ResultsExport, ArtifactType.Download,
            "Calibrated parameters (CSV)", "Path of the exported calibrated parameters."))
    end
    AnalysisSolutionMetadata(artifacts, Symbol[])
end

function DyadInterface.artifacts(sol::TNNTrainingAnalysisSolution, name::Symbol)
    if name == :SimulationSolutionPlot
        training_figure(sol)
    elseif name == :FitPlot
        fit_figure(sol)
    elseif name == :ContinuityPlot
        continuity_figure(sol)
    elseif name == :LossTable
        sol.steps
    elseif name == :OuterIterationTable
        sol.outer
    elseif name == :ErrorTable
        error_table(sol)
    elseif name == :CalibrationResult
        sol.result
    elseif name == :ResultsExport
        isempty(sol.results_path) && error("No results_path was set for this analysis")
        isfile(sol.results_path) || save_calibration(sol.results_path, sol.result, sol.result.prob)
        sol.results_path
    else
        error("Artifact $name not recognized for TNNTrainingAnalysis")
    end
end

DyadInterface.customizable_visualization(::TNNTrainingAnalysisSolution, ::PlotlyVisualizationSpec) = missing

function Base.show(io::IO, sol::TNNTrainingAnalysisSolution)
    print(io, "TNNTrainingAnalysisSolution (", nrow(sol.steps), " Adam steps, ",
        nrow(sol.outer), " outer iterations, ", round(sol.elapsed; digits = 1), " s, retcode ",
        sol.result.retcode, ", max junction gap ", round(maximum(abs, sol.continuity); digits = 3), " °C)")
end
function Base.show(io::IO, ::MIME"text/plain", sol::TNNTrainingAnalysisSolution)
    show(io, sol); println(io)
    show(io, MIME"text/plain"(), error_table(sol))
end

export TNNFreeRunAnalysis, TNNFreeRunAnalysisSpec, AbstractTNNFreeRunAnalysisSpec,
       TNNFreeRunAnalysisSolution,
       TNNTrainingAnalysis, TNNTrainingAnalysisSpec, AbstractTNNTrainingAnalysisSpec,
       TNNTrainingAnalysisSolution
