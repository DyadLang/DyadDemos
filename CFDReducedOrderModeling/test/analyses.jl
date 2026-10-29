using DyadInterface: symbolic_container, artifacts
using CSV, DataFrames, LinearAlgebra, Random, Statistics
const CFD = CFDReducedOrderModeling
const DEMO_ROOT = dirname(@__DIR__)

@testset "Dyad transient analyses" begin
    for (analysis, file) in ((CFDTrainingAnalysis, "cfd_training_data.csv"),
                              (CFDValidationAnalysis, "cfd_validation_data.csv"))
        reference = CSV.read(joinpath(DEMO_ROOT, "data", file), DataFrame)
        result = analysis(saveat=reference.time[2] - reference.time[1])
        sol = result.sol
        model = symbolic_container(result)
        @test string(sol.retcode) == "Success"
        @test sol.t ≈ reference.time
        temperatures = hcat([sol[model.model.T[i]] for i in 1:20]...)
        expected = Matrix(reference[:, ["T_$i" for i in 1:20]])
        @test all(isfinite, temperatures)
        @test maximum(abs.(temperatures .- expected)) < 0.02
        # At 300 K, reltol=1e-6 permits sub-millikelvin integration noise.
        @test minimum(temperatures) >= 300 - 1e-3
        @test temperatures[end, 1] > temperatures[end, 20] > 300
        println(nameof(analysis), " maximum CSV temperature difference: ", maximum(abs.(temperatures .- expected)), " K")
    end
    for (analysis, zones) in ((SVDThermalNetworkROMTransient, 4),
                              (NeuralODEThermalNetworkROMTransient, 4),
                              (PODDMDcROMTransient, 3))
        result = analysis(saveat=1.0)
        sol = result.sol
        rom = symbolic_container(result).rom
        @test string(sol.retcode) == "Success"
        @test last(sol.t) == 200
        for z in 1:zones
            theta = sol[getproperty(rom, Symbol("theta$z"))]
            @test all(isfinite, theta)
            @test abs(first(theta)) < 1e-8
            @test 0 < last(theta) < 100
        end
    end
end

@testset "ROM data and persistence" begin
    data = CFD.load_cfd_data(joinpath(DEMO_ROOT, "data", "cfd_training_data.csv"))
    @test size(data.X) == (1000, 20)
    @test data.spatial_cols == ["T_$i" for i in 1:20]
    @test data.X[1, :] == zeros(20)
    mktempdir() do dir
        for file in ("svd_network.json", "neural_ode_network.json")
            net = load_network(joinpath(DEMO_ROOT, "results", file))
            @test sort(vcat(net.zone_members...)) == collect(1:20)
            @test net.C_per_node > 0 && net.Gc > 0 && all(>(0), net.G)
            path = save_network(joinpath(dir, file), net)
            restored = load_network(path)
            @test restored.zone_members == net.zone_members
            @test restored.G == net.G
            @test restored.C_per_node == net.C_per_node
        end
    end
end

@testset "ROM construction and artifacts" begin
    Random.seed!(42)
    pod = RunDataDrivenPOD(verbose=false)
    @test pod.r.k == 2
    @test all(real.(eigvals(pod.r.A)) .< 0)
    @test pod.r.train_zone_rmse < 1
    @test pod.r.train_spatial_rmse < 1
    @test sort(vcat(pod.r.zone_members...)) == collect(1:20)
    @test artifacts(pod, :ROMParameters) isa DataFrame
    @test artifacts(pod, :RawResult) === pod.r
    @test_throws ErrorException artifacts(pod, :unknown)
    mktempdir() do dir
        path = save_pod_rom(joinpath(dir, "pod.json"), pod.r)
        restored = load_pod_rom(path)
        @test restored.A == pod.r.A
        @test restored.B == pod.r.B
        @test restored.C == pod.r.C
    end
    # Small budgets exercise each pipeline, including neural differentiation.
    # They do not establish convergence of the full default training sweep.
    svd = RunSVDThermalNetwork(N_candidates=[4], maxiter=10, verbose=false)
    @test svd.r.network.N == 4
    @test isfinite(svd.r.network.zone_rmse)
    @test artifacts(svd, :CalibratedNetwork) isa DataFrame
    @test_throws ErrorException artifacts(svd, :unknown)
    node = RunLatentNeuralODE(latent_dims=[2], hidden_enc=4, hidden_dyn=4,
        hidden_dec=4, n_epochs=1, n_seeds=1, n_shooting=2, window_len=3,
        N_candidates=[4], maxiter=10, verbose=false)
    @test node.r.best_k == 2
    @test all(isfinite, node.r.train_rmse)
    @test node.r.network.N == 4
    @test artifacts(node, :LatentDimSweep) isa DataFrame
    @test_throws ErrorException artifacts(node, :unknown)
end
