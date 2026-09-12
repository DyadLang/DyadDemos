using CairoMakie
using BlockComponents
using DyadData
using DyadInterface
using DyadModelDiscovery
using DyadModelOptimizer
using DyadInterface: AbstractAnalysisSpec, AbstractAnalysisSolution, AnalysisSolutionMetadata,
                     ArtifactMetadata, ArtifactType, TransientAnalysis, ODEAlg, DEVerbosity,
                     OptimizationLevel, SpecializationLevel, artifacts
using ModelingToolkit: SymbolicT, toggle_namespacing, System, connect, t_nounits

abstract type AbstractStoryTransientSpec <: AbstractAnalysisSpec end

for prefix in (:A1Problem, :A2Gap, :A4Performance)
    abstract_name = Symbol(:Abstract, prefix, :AnalysisSpec)
    spec_name = Symbol(prefix, :AnalysisSpec)
    @eval begin
        abstract type $abstract_name <: AbstractStoryTransientSpec end
        Base.@kwdef struct $spec_name{M} <: $abstract_name
            name::Symbol = $(QuoteNode(prefix))
            model::M = StoryQuarterTruck(; name=:model)
            overrides::Dict{SymbolicT, SymbolicT} = Dict{SymbolicT, SymbolicT}()
            alg::ODEAlg.Type = ODEAlg.Auto()
            start::Float64 = 0.0
            stop::Float64 = 5.0
            abstol::Float64 = 1e-6
            reltol::Float64 = 1e-6
            saveat::Float64 = 0.01
            dtmax::Float64 = 0.0
            tstops::Vector{Float64} = Float64[]
            automatic_discontinuity_detection::Bool = false
            optimize::OptimizationLevel.Type = OptimizationLevel.Aggressive()
            progress::Bool = false
            respecialize::Bool = false
            specialization::SpecializationLevel.Type = SpecializationLevel.Despecialize()
            verbose::DEVerbosity.Type = DEVerbosity.Standard()
            log_file::String = ""
            road_profile::String = "bump"
            bump_amplitude::Float64 = 0.03
            bump_duration::Float64 = 0.3
            bump_start::Float64 = 1.0
            roughness::Float64 = 16e-6
            speed::Float64 = 13.89
            weights_path::String = "assets/data/nn_weights_full_sin_lbfgs.csv"
        end
    end
end

for prefix in (:A5SineValidation, :A6OutOfDomain)
    abstract_name = Symbol(:Abstract, prefix, :AnalysisSpec)
    spec_name = Symbol(prefix, :AnalysisSpec)
    default_frequency = prefix === :A5SineValidation ? 2.0 : 4.0
    @eval begin
        abstract type $abstract_name <: AbstractStoryTransientSpec end
        Base.@kwdef struct $spec_name{M} <: $abstract_name
            name::Symbol = $(QuoteNode(prefix))
            model::M = StoryQuarterTruck(; name=:model)
            overrides::Dict{SymbolicT, SymbolicT} = Dict{SymbolicT, SymbolicT}()
            alg::ODEAlg.Type = ODEAlg.Auto()
            start::Float64 = 0.0
            stop::Float64 = 5.0
            abstol::Float64 = 1e-6
            reltol::Float64 = 1e-6
            saveat::Float64 = 0.01
            dtmax::Float64 = 0.0
            tstops::Vector{Float64} = Float64[]
            automatic_discontinuity_detection::Bool = false
            optimize::OptimizationLevel.Type = OptimizationLevel.Aggressive()
            progress::Bool = false
            respecialize::Bool = false
            specialization::SpecializationLevel.Type = SpecializationLevel.Despecialize()
            verbose::DEVerbosity.Type = DEVerbosity.Standard()
            log_file::String = ""
            amplitude::Float64 = 0.03
            frequency::Float64 = $default_frequency
            weights_path::String = "assets/data/nn_weights_full_sin_lbfgs.csv"
        end
    end
end

abstract type AbstractA3TrainingAnalysisSpec <: AbstractAnalysisSpec end

Base.@kwdef struct A3TrainingAnalysisSpec{M} <: AbstractA3TrainingAnalysisSpec
    name::Symbol = :A3Training
    model::M = StoryQuarterTruck(; name=:model)
    overrides::Dict{SymbolicT, SymbolicT} = Dict{SymbolicT, SymbolicT}()
    alg::Any = ODEAlg.Tsit5()
    start::Float64 = 0.0
    stop::Float64 = 0.5
    abstol::Float64 = 1e-6
    reltol::Float64 = 1e-6
    saveat::Float64 = 0.0
    dtmax::Float64 = 0.0
    data::Any = DyadData.DyadTimeseries(
        "dyad://QuarterTruckSciML/data/truck_sin_full_train.csv";
        independent_var="timestamp",
        dependent_vars=["model.tire.s(t)", "model.driver.s(t)", "model.driver.a(t)"])
    depvars_names::Vector{String} = ["model.tire.s", "model.driver.s", "model.driver.a"]
    loss_func::Any = DyadModelOptimizer.LossFunc.L2Loss()
    calibration_alg::Any = "SingleShooting"
    multiple_shooting_trajectories::Int = 0
    pem_gain::Float64 = 0.0
    optimizer::Any = "Adam"
    optimizer_maxiters::Int = 5000
    optimizer_maxtime::Float64 = 60.0
    optimizer_abstol::Float64 = 1e-4
    optimizer_verbose::Bool = false
    diagnostics::Any =
        DyadModelOptimizer.DiagnosticsLevel.CalibrationTracking()
    learning_rate::Float64 = 1e-3
    network_component::String = "model.scaled_nn.nn"
    min_weight::Float64 = -Inf
    max_weight::Float64 = Inf
    initial_values_path::String = ""
    results_path::String = "story_output/nn_weights_demo.csv"
end

struct StoryAnalysisSolution{S, D} <: AbstractAnalysisSolution
    spec::S
    kind::Symbol
    data::D
end

Base.nameof(sol::StoryAnalysisSolution) = sol.spec.name

const _TITLES = Dict(
    :problem => "A1 · The problem",
    :gap => "A2 · Measure the gap",
    :training => "A3 · Short training demonstration",
    :performance => "A4 · Performance on an unseen road",
    :training_sine => "A5 · At the training condition",
    :ood_sine => "A6 · Outside the training condition",
)

function DyadInterface.AnalysisSolutionMetadata(sol::StoryAnalysisSolution)
    artifact = ArtifactMetadata(:SimulationSolutionPlot, ArtifactType.Native,
        _TITLES[sol.kind], "Large-screen CairoMakie story plot for $(nameof(sol)).")
    AnalysisSolutionMetadata([artifact], Symbol[])
end

const _TRUTH = Makie.RGBf(0.08, 0.12, 0.18)
const _LINEAR = Makie.RGBf(230 / 255, 159 / 255, 0) # Wong orange
const _LEARNED = Makie.RGBf(0, 158 / 255, 115 / 255) # Wong green
const _ACCEL = "model.driver.a(t)"
const _ROAD = "iso_road.y(t)"

_story_path(path::AbstractString) = isabspath(path) ? path :
    normpath(joinpath(@__DIR__, "..", "..", path))
_rms(x) = sqrt(sum(abs2, x) / length(x))

function _resample(source_t, source_y, target_t)
    source_t == target_t && return source_y
    map(target_t) do time
        index = searchsortedlast(source_t, time)
        index <= 0 && return first(source_y)
        index >= length(source_t) && return last(source_y)
        fraction = (time - source_t[index]) / (source_t[index + 1] - source_t[index])
        source_y[index] + fraction * (source_y[index + 1] - source_y[index])
    end
end

function _read_weights(path)
    fullpath = _story_path(path)
    isfile(fullpath) || throw(ArgumentError("trained weights not found at $fullpath"))
    lines = readlines(fullpath)
    length(lines) >= 2 || throw(ArgumentError("weights file has no data row: $fullpath"))
    parse.(Float64, split(lines[2], ','))
end

function _sine_harness(story_model, amplitude, frequency; name)
    model = ModelingToolkit.Symbolics.rename(story_model, :model)
    signal = BlockComponents.Sources.Sine(;
        name=:sin_signal, amplitude, frequency, start_time=0.1)
    System([connect(signal.y, model.s_rel)], t_nounits; systems=[model, signal], name)
end

function _road_source(spec)
    if spec.road_profile == "rough"
        return QuarterTruckSciML.DenseISO8608Road(; name=:iso_road,
            roughness=spec.roughness, speed=spec.speed, start_time=spec.start)
    elseif spec.road_profile == "bump"
        return QuarterTruckSciML.HalfSineBump(; name=:iso_road,
            amplitude=spec.bump_amplitude, bump_duration=spec.bump_duration,
            start_time=spec.bump_start)
    end
    throw(ArgumentError("road_profile must be \"rough\" or \"bump\""))
end

function _road_label(spec)
    if spec.road_profile == "bump"
        return "$(spec.bump_amplitude) m half-sine bump over $(spec.bump_duration) s"
    elseif spec.road_profile == "rough"
        return "ISO 8608 road (roughness $(spec.roughness) m³, speed $(spec.speed) m/s)"
    else
        throw(ArgumentError("road_profile must be \"rough\" or \"bump\""))
    end
end

function _road_harness(story_model, spec; name)
    model = ModelingToolkit.Symbolics.rename(story_model, :model)
    road = _road_source(spec)
    System([connect(road.y, model.s_rel)], t_nounits; systems=[model, road], name)
end

function _physical_road_harness(spec; name, nonlinear)
    parameters = nonlinear ? (;
        tire_k3=1e7, tire_compression_only=1.0, friction_Fc=500.0,
        seat_driver_n=0.5) : (;)
    model = QuarterTruckSciML.QuarterTruckConfigurable(; name=:model, parameters...)
    road = _road_source(spec)
    System([connect(road.y, model.road.s_ref)], t_nounits; systems=[model, road], name)
end

function _physical_sine_harness(amplitude, frequency; name, nonlinear)
    parameters = nonlinear ? (;
        tire_k3=1e7, tire_compression_only=1.0, friction_Fc=500.0,
        seat_driver_n=0.5) : (;)
    model = QuarterTruckSciML.QuarterTruckConfigurable(; name=:model, parameters...)
    signal = BlockComponents.Sources.Sine(;
        name=:sin_signal, amplitude, frequency, start_time=0.1)
    System([connect(signal.y, model.road.s_ref)], t_nounits;
        systems=[model, signal], name)
end

function _transient(spec, harness; weights=nothing, road=false, inherit_overrides=false,
        event_times=Float64[])
    overrides = inherit_overrides ? copy(spec.overrides) : Dict{SymbolicT, SymbolicT}()
    if !isnothing(weights)
        bare = toggle_namespacing(harness, false)
        overrides[bare.model.scaled_nn.nn.p] = weights
    end
    tstops = sort!(unique!(vcat(spec.tstops, filter(t -> spec.start <= t <= spec.stop,
        event_times))))
    result = TransientAnalysis(; model=harness, overrides, alg=spec.alg,
        start=spec.start, stop=spec.stop, abstol=spec.abstol, reltol=spec.reltol,
        saveat=spec.saveat, dtmax=spec.dtmax, tstops,
        automatic_discontinuity_detection=spec.automatic_discontinuity_detection,
        optimize=spec.optimize, progress=spec.progress, respecialize=spec.respecialize,
        specialization=spec.specialization, verbose=spec.verbose, log_file=spec.log_file)
    raw = artifacts(result, :RawSolution)
    values = (t=collect(raw.t), acceleration=collect(raw[getproperty(result, _ACCEL)]))
    road ? merge(values, (road=collect(raw[getproperty(result, _ROAD)]),)) : values
end

function _road_comparison(spec; learned=false)
    weights = learned ? _read_weights(spec.weights_path) : nothing
    events = spec.road_profile == "bump" ?
        [spec.bump_start, spec.bump_start + spec.bump_duration] : Float64[]
    baseline = _transient(spec,
        _physical_road_harness(spec; name=:linear, nonlinear=false);
        road=true, event_times=events)
    truth = _transient(spec,
        _physical_road_harness(spec; name=:truth, nonlinear=true);
        road=true, event_times=events)
    t = spec.saveat == 0 ? collect(range(spec.start, spec.stop; length=1001)) : truth.t
    linear = _resample(baseline.t, baseline.acceleration, t)
    reference = _resample(truth.t, truth.acceleration, t)
    road = _resample(truth.t, truth.road, t)
    data = (; t, road, linear, road_label=_road_label(spec), truth=reference,
        residual=reference .- linear, linear_rms=_rms(linear .- reference),
        signal_rms=_rms(reference))
    learned || return data
    prediction = _transient(spec, _road_harness(spec.model, spec; name=:learned);
        weights, inherit_overrides=true, event_times=events)
    learned_values = _resample(prediction.t, prediction.acceleration, t)
    merge(data, (; learned=learned_values,
        learned_rms=_rms(learned_values .- reference)))
end

function _sine_comparison(spec)
    weights = _read_weights(spec.weights_path)
    baseline = _transient(spec, _physical_sine_harness(
        spec.amplitude, spec.frequency; name=:linear, nonlinear=false);
        event_times=[0.1])
    prediction = _transient(spec,
        _sine_harness(spec.model, spec.amplitude, spec.frequency; name=:learned);
        weights, inherit_overrides=true, event_times=[0.1])
    truth_harness = _physical_sine_harness(spec.amplitude, spec.frequency;
        name=:truth, nonlinear=true)
    truth = _transient(spec, truth_harness; event_times=[0.1])
    t = spec.saveat == 0 ? collect(range(spec.start, spec.stop; length=1001)) : truth.t
    reference = _resample(truth.t, truth.acceleration, t)
    linear = _resample(baseline.t, baseline.acceleration, t)
    learned = _resample(prediction.t, prediction.acceleration, t)
    (; t, truth=reference, linear, learned,
        amplitude=spec.amplitude, frequency=spec.frequency,
        linear_rms=_rms(linear .- reference), learned_rms=_rms(learned .- reference))
end

DyadInterface.run_analysis(spec::A1ProblemAnalysisSpec) =
    StoryAnalysisSolution(spec, :problem, _road_comparison(spec))
DyadInterface.run_analysis(spec::A2GapAnalysisSpec) =
    StoryAnalysisSolution(spec, :gap, _road_comparison(spec))
DyadInterface.run_analysis(spec::A4PerformanceAnalysisSpec) =
    StoryAnalysisSolution(spec, :performance, _road_comparison(spec; learned=true))
DyadInterface.run_analysis(spec::A5SineValidationAnalysisSpec) =
    StoryAnalysisSolution(spec, :training_sine, _sine_comparison(spec))
DyadInterface.run_analysis(spec::A6OutOfDomainAnalysisSpec) =
    StoryAnalysisSolution(spec, :ood_sine, _sine_comparison(spec))

function DyadInterface.run_analysis(spec::A3TrainingAnalysisSpec)
    isfinite(spec.optimizer_maxtime) && spec.optimizer_maxtime >= 0 ||
        throw(ArgumentError("optimizer_maxtime must be finite and nonnegative"))
    spec.optimizer_maxiters > 0 || throw(ArgumentError("optimizer_maxiters must be positive"))
    isempty(spec.results_path) && throw(ArgumentError("results_path must not be empty"))
    results_path = _story_path(spec.results_path)
    mkpath(dirname(results_path))
    initial_values_path = isempty(spec.initial_values_path) ? "" :
        _story_path(spec.initial_values_path)
    calibration_alg = spec.calibration_alg isa AbstractString ?
        convert(DyadModelOptimizer.CalibrationAlg.Type, spec.calibration_alg) :
        spec.calibration_alg
    optimizer = spec.optimizer isa AbstractString ?
        convert(DyadModelOptimizer.OptimizerAlg.Type, spec.optimizer) : spec.optimizer
    harness = _sine_harness(spec.model, 0.03, 2.0; name=:training)
    training_spec = DyadModelDiscovery.NNTrainingAnalysisSpec(;
        name=:StoryTraining, model=harness, overrides=spec.overrides, alg=spec.alg,
        start=spec.start, stop=spec.stop, abstol=spec.abstol, reltol=spec.reltol,
        saveat=spec.saveat, dtmax=spec.dtmax, data=spec.data,
        depvars_names=spec.depvars_names, loss_func=spec.loss_func,
        calibration_alg,
        multiple_shooting_trajectories=spec.multiple_shooting_trajectories,
        pem_gain=spec.pem_gain, optimizer,
        optimizer_maxiters=spec.optimizer_maxiters,
        optimizer_maxtime=spec.optimizer_maxtime,
        optimizer_abstol=spec.optimizer_abstol,
        optimizer_verbose=spec.optimizer_verbose, diagnostics=spec.diagnostics,
        learning_rate=spec.learning_rate, network_component=spec.network_component,
        min_weight=spec.min_weight, max_weight=spec.max_weight,
        initial_values_path, results_path)
    training = DyadInterface.run_analysis(training_spec)
    artifacts(training, :ResultsExport)

    transient_spec = A5SineValidationAnalysisSpec(; name=:training_plot,
        model=spec.model, overrides=spec.overrides, alg=spec.alg,
        start=spec.start, stop=spec.stop,
        abstol=spec.abstol, reltol=spec.reltol, saveat=0.01, dtmax=spec.dtmax,
        progress=false, amplitude=0.03, frequency=2.0, weights_path=results_path)
    data = merge(_sine_comparison(transient_spec),
        (; optimizer_maxtime=spec.optimizer_maxtime, results_path))
    StoryAnalysisSolution(spec, :training, data)
end

function _base_figure(title, subtitle)
    fig = Figure(size=(1600, 900), backgroundcolor=:white, fontsize=28)
    Label(fig[1, 1], title; fontsize=42, font=:bold, color=_TRUTH, tellwidth=false)
    Label(fig[2, 1], subtitle; fontsize=25, color=:gray35, tellwidth=false)
    fig
end

function _comparison_figure(d, title, subtitle; legend_below=false)
    fig = _base_figure(title, subtitle)
    ax = Axis(fig[3, 1]; xlabel="time (s)", ylabel="driver acceleration (m/s²)")
    lines!(ax, d.t, d.truth; color=_TRUTH, linewidth=2.5, linestyle=:solid,
        label="reference ride")
    lines!(ax, d.t, d.linear; color=_LINEAR, linewidth=2.5, linestyle=:solid,
        label="linear")
    lines!(ax, d.t, d.learned; color=_LEARNED, linewidth=2.5, linestyle=:solid,
        label="learned")
    if legend_below
        Legend(fig[4, 1], ax; orientation=:horizontal, framevisible=false, labelsize=24)
    else
        axislegend(ax; position=:rt, framevisible=false, labelsize=24)
    end
    fig
end

function _story_plot(sol)
    kind, d = sol.kind, sol.data
    if kind === :problem
        fig = _base_figure("A1 · Can we predict how this ride will feel?",
            "Better suspension predictions help us tune springs and design controls")
        road_ax = Axis(fig[3, 1]; ylabel="road height (mm)", height=150)
        lines!(road_ax, d.t, 1000 .* d.road; color=_LEARNED, linewidth=2.5,
            linestyle=:solid)
        hidexdecorations!(road_ax; grid=false)
        ax = Axis(fig[4, 1]; xlabel="time (s)", ylabel="driver acceleration (m/s²)")
        lines!(ax, d.t, d.truth; color=_TRUTH, linewidth=2.5, linestyle=:solid,
            label="reference ride")
        lines!(ax, d.t, d.linear; color=_LINEAR, linewidth=2.5, linestyle=:solid,
            label="linear suspension model")
        axislegend(ax; position=:rt, framevisible=false, labelsize=24)
    elseif kind === :gap
        pct = 100 * d.linear_rms / max(d.signal_rms, eps())
        fig = _base_figure("A2 · How large is the prediction gap?",
            "RMS acceleration gap = $(round(d.linear_rms; digits=3)) m/s²  ·  $(round(pct; digits=1))% of the reference signal")
        ax = Axis(fig[3, 1]; xlabel="time (s)", ylabel="reference − linear (m/s²)")
        band!(ax, d.t, zeros(length(d.t)), d.residual; color=(_LEARNED, 0.20))
        lines!(ax, d.t, d.residual; color=_LEARNED, linewidth=2.5, linestyle=:solid)
        hlines!(ax, [0.0]; color=:gray55, linewidth=2, linestyle=:solid)
    elseif kind === :training
        budget = d.optimizer_maxtime == 0 ? "no optimizer time limit" :
            "optimizer budget $(round(Int, d.optimizer_maxtime)) s"
        fig = _comparison_figure(d, "A3 · Learn the missing forces",
            "Controlled 0.03 m, 2 Hz sine data · $budget";
            legend_below=true)
    elseif kind === :performance
        fig = _comparison_figure(d, "A4 · Does the pretrained model predict the ride?",
            "$(d.road_label) · RMS error: linear $(round(d.linear_rms; digits=3)) · learned $(round(d.learned_rms; digits=3)) m/s²")
    elseif kind === :training_sine
        fig = _comparison_figure(d, "A5 · At the training condition",
            "$(d.amplitude) m at $(d.frequency) Hz · RMS error: linear $(round(d.linear_rms; digits=3)) · learned $(round(d.learned_rms; digits=3)) m/s²";
            legend_below=true)
    else
        fig = _comparison_figure(d, "A6 · Outside the training condition",
            "trained at 0.03 m, 2 Hz · tested at $(d.amplitude) m, $(d.frequency) Hz · RMS: linear $(round(d.linear_rms; digits=3)) · learned $(round(d.learned_rms; digits=3)) m/s²";
            legend_below=true)
    end
    colgap!(fig.layout, 16)
    rowgap!(fig.layout, 12)
    fig
end

function DyadInterface.artifacts(sol::StoryAnalysisSolution, name::Symbol)
    name === :SimulationSolutionPlot || throw(ArgumentError("unknown artifact $name"))
    _story_plot(sol)
end

export StoryAnalysisSolution
