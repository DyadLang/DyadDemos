using DyadInterface: symbolic_container

@testset "Turkey cooking analysis" begin
    result = TurkeySphereCooking()
    sol = result.sol
    model = symbolic_container(result)
    center = sol[model.turkey.T[1]]
    surface = sol[model.turkey.surface.T]
    @test string(sol.retcode) == "Success"
    @test last(sol.t) == 14400.0
    @test first(center) ≈ 277.0 atol=1e-6
    @test 277.0 < last(center) < last(surface) < 450.0
    @test all(isfinite, center) && all(isfinite, surface)
    @test TurkeyDemo.KelvinToFahrenheit(273.15) ≈ 32.0
    println("TurkeySphereCooking final center/surface temperatures (K): ", last(center), ", ", last(surface))
end
