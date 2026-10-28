using DyadInterface: symbolic_container

@testset "Coffee cooling analyses" begin
    for analysis in (EspressoCoolingModular, EspressoCoolingWithSpoon)
        result = analysis()
        sol = result.sol
        model = symbolic_container(result)
        temperature = sol[model.coffeeMug.espressoTemp_degC]
        @test string(sol.retcode) == "Success"
        @test last(sol.t) == 6000.0
        @test first(temperature) ≈ 90.0 atol=1e-6
        @test 20.0 < last(temperature) < first(temperature)
        @test all(isfinite, temperature)
        println(nameof(analysis), " final espresso temperature (degC): ", last(temperature))
    end
end
