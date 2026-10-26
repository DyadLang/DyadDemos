using DyadInterface: symbolic_container

@testset "House winter analyses" begin
    open_loop = TestHouseWinterDesign()
    model = symbolic_container(open_loop)
    temperature = open_loop.sol[model.house.T_interior]
    @test string(open_loop.sol.retcode) == "Success"
    @test last(open_loop.sol.t) == 7200.0
    @test first(temperature) ≈ 294.26 atol=1e-6
    @test last(temperature) > first(temperature)
    @test all(isfinite, temperature)
    println("TestHouseWinterDesign final indoor temperature (K): ", last(temperature))

    controlled = TestControlledHouseWinterDesign()
    model = symbolic_container(controlled)
    temperature = controlled.sol[model.controlled_house.T_interior]
    power = controlled.sol[model.controlled_house.Q_heater]
    @test string(controlled.sol.retcode) == "Success"
    @test last(controlled.sol.t) == 7200.0
    @test first(temperature) ≈ 288.7 atol=1e-6
    @test last(temperature) ≈ 294.26 atol=0.5
    @test all(isfinite, temperature)
    @test all(q -> -1e-6 <= q <= 10000.0 + 1e-6, power)
    println("TestControlledHouseWinterDesign final indoor temperature (K), heater power (W): ", last(temperature), ", ", last(power))
end
