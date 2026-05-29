using QuarterTruckSciML
using Test
using ModelingToolkit
using OrdinaryDiffEqDefault
using CSV, DataFrames

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
        weights_csv = joinpath(@__DIR__, "..", "data", "nn_weights_full_sin_lbfgs.csv")
        @test isfile(weights_csv)
        weights_flat = Vector{Float64}(collect(CSV.read(weights_csv, DataFrame)[1, :]))
        @test length(weights_flat) == 68    # matches the QuarterTruckFullNN architecture

        # Simulate truth + NN with trained weights at low resolution.
        sys_gt = mtkcompile(QuarterTruckSciML.TestQuarterTruckNonlinearISOA(; name=:h))
        sys_nn = mtkcompile(QuarterTruckSciML.TestQuarterTruckFullNNISOA(; name=:h))

        prob_gt   = ODEProblem(sys_gt, [], (0.0, 2.0); fully_determined=true)
        prob_nn   = ODEProblem(sys_nn, [sys_nn.model.nn.p => weights_flat],
                               (0.0, 2.0); fully_determined=true)
        prob_zero = ODEProblem(sys_nn, [sys_nn.model.nn.p => zeros(length(weights_flat))],
                               (0.0, 2.0); fully_determined=true)

        sol_gt   = solve(prob_gt;   saveat=0.01)
        sol_nn   = solve(prob_nn;   saveat=0.01)
        sol_zero = solve(prob_zero; saveat=0.01)

        rms_trained = sqrt(sum((sol_nn[sys_nn.model.tire.s]   .- sol_gt[sys_gt.model.tire.s]).^2))
        rms_zero    = sqrt(sum((sol_zero[sys_nn.model.tire.s] .- sol_gt[sys_gt.model.tire.s]).^2))
        @test rms_trained < rms_zero
    end

end
