using DyadInterface: symbolic_container

@testset "Building sizing and operation analyses" begin
    for (analysis, expected) in ((HVACSizing, [4274.114114114114, 1149.8051499250374, 5165.780780780781]),
                               (ColdNightSizing, [7557.5975975975975, 1924.7676785607196, 7040.930930930931]))
        result = analysis()
        model = symbolic_container(result)
        capacities = [-result.sol[getproperty(model, Symbol("zone", i, "_setpoint")).port.Q_flow] for i in 1:3]
        @test string(result.sol.retcode) == "Success"
        @test capacities ≈ expected rtol=1e-6
        println(nameof(analysis), " zone heating capacities (W): ", capacities)
    end
    result = DiurnalOperation()
    model = symbolic_container(result)
    @test string(result.sol.retcode) == "Success"
    @test last(result.sol.t) == 86400.0
    for i in 1:3
        zone = getproperty(model.building, Symbol("z", i))
        temperature = result.sol[zone.cap.T]
        @test first(temperature) ≈ 285.15 atol=1e-6
        @test all(isfinite, temperature)
        @test 285.15 < last(temperature) <= 294.15 + 0.1
        println("DiurnalOperation zone ", i, " final temperature (K): ", last(temperature))
    end
end
