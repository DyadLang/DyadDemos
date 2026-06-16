using DrivelineSciML
using Test
using ModelingToolkit
using OrdinaryDiffEqDefault
using CSV, DataFrames

# Generated test-component smoke tests (mtkcompile + initial-condition checks)
include("../generated/tests.jl")

const TRUTH = (k1 = 300.0, c1 = 1.0, alpha = 50.0, A_bw = 1.0, beta_bw = 5.0, gamma_bw = 0.5)

# Demo-specific end-to-end smoke tests.
@testset "DrivelineSciML demo smoke tests" begin

    @testset "All harnesses simulate" begin
        for (name, harness, stop) in [
                ("chirp",        DrivelineSciML.TestDrivelineChirp(; name = :h),            1.0),
                ("maxwell-only", DrivelineSciML.TestDrivelineChirpMaxwellOnly(; name = :h), 1.0),
                ("slow-cycle",   DrivelineSciML.TestDrivelineSlowCycle(; name = :h),        1.0),
                ("tip-in",       DrivelineSciML.TestDrivelineTipIn(; name = :h),            1.0),
            ]
            sys = mtkcompile(harness)
            prob = ODEProblem(sys, [], (0.0, stop); fully_determined = true)
            sol = solve(prob; saveat = 0.01)
            @test sol.retcode == ReturnCode.Success
        end
    end

    @testset "delta_w observable matches J_eng.w - J_load.w" begin
        sys = mtkcompile(DrivelineSciML.TestDrivelineSlowCycle(; name = :h))
        prob = ODEProblem(sys, [], (0.0, 1.0); fully_determined = true)
        sol = solve(prob; saveat = 0.01)
        @test sol[sys.model.delta_w] ≈ sol[sys.model.J_eng.w] .- sol[sys.model.J_load.w] atol = 1e-10
    end

    @testset "Bouc-Wen state active in truth model, inert in Maxwell-only harness" begin
        sys = mtkcompile(DrivelineSciML.TestDrivelineSlowCycle(; name = :h))
        prob = ODEProblem(sys,
            [sys.k1 => TRUTH.k1, sys.c1 => TRUTH.c1,
             sys.model.alpha => TRUTH.alpha, sys.model.A_bw => TRUTH.A_bw,
             sys.model.beta_bw => TRUTH.beta_bw, sys.model.gamma_bw => TRUTH.gamma_bw],
            (0.0, 2.0); fully_determined = true)
        sol = solve(prob; saveat = 0.01)
        @test maximum(abs, sol[sys.model.isolator.z]) > 0.01

        sys_mx = mtkcompile(DrivelineSciML.TestDrivelineChirpMaxwellOnly(; name = :h))
        prob_mx = ODEProblem(sys_mx, [], (0.0, 2.0); fully_determined = true)
        sol_mx = solve(prob_mx; saveat = 0.01)
        @test maximum(abs, sol_mx[sys_mx.model.isolator.z]) < 1e-4
    end

    @testset "Measurement CSVs present with expected shape" begin
        for (file, rows) in [("chirp_measurements.csv", 5001), ("slow_cycle_measurements.csv", 1001)]
            path = joinpath(@__DIR__, "..", "assets", "data", file)
            @test isfile(path)
            df = CSV.read(path, DataFrame)
            @test names(df) == ["timestamp", "omega_eng(t)", "omega_load(t)", "delta_w(t)"]
            @test nrow(df) == rows
        end
    end

end
