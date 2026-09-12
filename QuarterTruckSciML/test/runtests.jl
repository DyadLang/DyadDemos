using QuarterTruckSciML
using Test
using ModelingToolkit
using OrdinaryDiffEqDefault
using CSV, DataFrames
using CairoMakie
using DyadInterface

# Generated test-component smoke tests (mtkcompile + initial-condition checks)
include("../generated/tests.jl")

# Demo-specific end-to-end smoke tests.
@testset "QuarterTruckSciML demo smoke tests" begin

    @testset "ISO 8608 helpers" begin
        amps = QuarterTruckSciML.iso8608_amplitudes(50, 0.3, 30.0, 1e-6)
        @test length(amps) == 50
        @test all(>(0), amps)
        @test issorted(amps; rev=true)  # log-spaced PSD → larger amp at lower freq
    end

    @testset "Linear/Nonlinear/FullNN ISOA harnesses simulate" begin
        for (name, harness) in [
                ("linear",    QuarterTruckSciML.TestQuarterTruckLinearISOA(;    name=:h)),
                ("nonlinear", QuarterTruckSciML.TestQuarterTruckNonlinearISOA(; name=:h)),
                ("nn",        QuarterTruckSciML.TestQuarterTruckFullNNISOA(;    name=:h)),
            ]
            sys = mtkcompile(harness)
            prob = ODEProblem(sys, [], (0.0, 1.0); fully_determined=true)
            sol = solve(prob; saveat=0.1)
            @test sol.retcode == ReturnCode.Success
            # Tire mass should stay near its initial 0.178908 m
            @test abs(sol[sys.model.tire.s][end] - 0.178908) < 0.05
        end
    end

    @testset "Pre-trained NN weights load and produce a smaller error than random" begin
        weights_csv = joinpath(@__DIR__, "..", "assets", "data", "nn_weights_full_sin_lbfgs.csv")
        @test isfile(weights_csv)
        weights_flat = Vector{Float64}(collect(CSV.read(weights_csv, DataFrame)[1, :]))
        @test length(weights_flat) == 68    # matches the QuarterTruckFullNN architecture

        # Simulate truth + NN with trained weights at low resolution.
        sys_gt = mtkcompile(QuarterTruckSciML.TestQuarterTruckNonlinearISOA(; name=:h))
        sys_nn = mtkcompile(QuarterTruckSciML.TestQuarterTruckFullNNISOA(; name=:h))

        prob_gt   = ODEProblem(sys_gt, [], (0.0, 2.0); fully_determined=true)
        prob_nn   = ODEProblem(sys_nn, [sys_nn.model.scaled_nn.nn.p => weights_flat],
                               (0.0, 2.0); fully_determined=true)
        prob_zero = ODEProblem(sys_nn, [sys_nn.model.scaled_nn.nn.p => zeros(length(weights_flat))],
                               (0.0, 2.0); fully_determined=true)

        sol_gt   = solve(prob_gt;   saveat=0.01)
        sol_nn   = solve(prob_nn;   saveat=0.01)
        sol_zero = solve(prob_zero; saveat=0.01)

        rms_trained = sqrt(sum((sol_nn[sys_nn.model.tire.s]   .- sol_gt[sys_gt.model.tire.s]).^2))
        rms_zero    = sqrt(sum((sol_zero[sys_nn.model.tire.s] .- sol_gt[sys_gt.model.tire.s]).^2))
        @test rms_trained < rms_zero
    end

    @testset "Story analysis contract" begin
        story = QuarterTruckSciML.Story
        package_root = normpath(joinpath(@__DIR__, ".."))
        @test story._story_path("assets/data/nn_weights_full_sin_lbfgs.csv") ==
              joinpath(package_root, "assets", "data", "nn_weights_full_sin_lbfgs.csv")
        absolute = joinpath(package_root, "story_output")
        @test story._story_path(absolute) == absolute

        # Julia execution alone does not catch the GUI's restriction on partial analyses.
        story_source = read(joinpath(package_root, "dyad", "Story", "story.dyad"), String)
        partial_source = read(joinpath(package_root, "dyad", "Story", "Partials", "analyses.dyad"), String)
        @test !occursin(r"(?m)^partial analysis", story_source)
        for name in (:A1Problem, :A2Gap, :A3Training, :A4Performance,
                :A5SineValidation, :A6OutOfDomain)
            spec = getproperty(story, Symbol(name, :Spec))()
            @test occursin(Regex("^analysis " * string(name) * "\$", "m"), story_source)
            @test occursin(Regex("^partial analysis " * string(name) * "Analysis\$", "m"), partial_source)
            @test spec isa getproperty(story.Partials, Symbol(:Abstract, name, :AnalysisSpec))
            @test spec.name == name
            @test spec.model isa ModelingToolkit.System
        end

        @test story.A3TrainingSpec().optimizer_maxtime == 60.0
        @test story.A3TrainingSpec().optimizer_maxiters == 5000
        @test story.A3TrainingSpec().stop == 0.5
        @test story.A4PerformanceSpec().weights_path ==
              "assets/data/nn_weights_full_sin_lbfgs.csv"
        @test story.A1ProblemSpec().road_profile == "rough"
        @test story.A1ProblemSpec().stop == 2.0
        @test !hasproperty(story.A1ProblemSpec(), :scene)
        @test !hasproperty(story.A1ProblemSpec(), :optimizer_maxtime)
        @test hasproperty(story.A1ProblemSpec(), :automatic_discontinuity_detection)
        @test story.A5SineValidationSpec().frequency == 2.0
        @test story.A6OutOfDomainSpec().frequency == 4.0
        for seconds in (-1.0, Inf, NaN)
            @test_throws ArgumentError story.A3Training(optimizer_maxtime=seconds)
        end

        t = collect(range(0.0, 1.0; length=21))
        data = (; t, road=0.001 .* sin.(2π .* t),
            truth=0.1 .* sin.(4π .* t), linear=0.08 .* sin.(4π .* t))
        data = merge(data, (;
            residual=data.truth .- data.linear,
            linear_rms=sqrt(sum(abs2, data.truth .- data.linear) / length(t)),
            signal_rms=sqrt(sum(abs2, data.truth) / length(t)),
            road_label="test road"))
        plot_solution = story.StoryAnalysisSolution(
            story.Partials.A1ProblemAnalysisSpec(; name=:plot_smoke, model=nothing), :problem, data)
        @test DyadInterface.artifacts(plot_solution) == [:SimulationSolutionPlot]
        @test DyadInterface.artifacts(plot_solution, :SimulationSolutionPlot) isa CairoMakie.Figure

        sine = story.A5SineValidation()
        saved = CSV.read(joinpath(package_root, "assets", "data", "truck_sin_full_train.csv"), DataFrame)
        @test sine.data.reference_source == "saved training CSV (synthetic reference data)"
        @test sine.data.t ≈ saved.timestamp[1:length(sine.data.t)]
        @test sine.data.truth ≈ saved[1:length(sine.data.t), "model.driver.a(t)"]
        @test last(sine.data.t) == 2.0
        @test DyadInterface.artifacts(sine, :SimulationSolutionPlot) isa CairoMakie.Figure

        performance = story.A4Performance()
        @test performance.data.learned_rms < performance.data.linear_rms
        @test all(isfinite, performance.data.learned)
        @test DyadInterface.artifacts(performance) == [:SimulationSolutionPlot]
        @test DyadInterface.artifacts(performance, :SimulationSolutionPlot) isa CairoMakie.Figure
    end

end
