using DyadInterface: symbolic_container

@testset "Declared multibody analyses" begin
    for (analysis, stop) in ((PendulumTransient, 3.0),
                             (SpringDamperSystemTestAnalysis, 10.0),
                             (DyadBalans2DAnalysis, 10.0),
                             (TwoTrackModelTestAnalysis, 10.0))
        @testset "$(nameof(analysis))" begin
            result = analysis()
            sol = result.sol
            model = symbolic_container(result)
            @test string(sol.retcode) == "Success"
            @test first(sol.t) == 0.0
            @test last(sol.t) == stop
            @test all(u -> all(isfinite, u), sol.u)
            if analysis === PendulumTransient
                angle = sol[model.revolute.phi]
                @test first(angle) ≈ 0.0 atol=1e-8
                @test minimum(angle) < -0.5
                x, y = sol[model.body.r[1]], sol[model.body.r[2]]
                @test maximum(abs.(x .^ 2 .+ y .^ 2 .- 1)) < 1e-5
            elseif analysis === SpringDamperSystemTestAnalysis
                x, y = sol[model.body.r[1]], sol[model.body.r[2]]
                @test first(x) ≈ 1.0 atol=1e-8
                @test first(y) ≈ 1.0 atol=1e-8
                @test last(x) ≈ -1.0 atol=0.02
                # Static vertical deflection is m*g/c = 0.5*9.81/5.
                @test last(y) ≈ -0.981 atol=0.02
            elseif analysis === DyadBalans2DAnalysis
                tilt = sol[model.body_mass.body.phi]
                @test first(tilt) ≈ 0.1 atol=1e-8
                @test maximum(abs, tilt) < 0.5
            else
                x, y = sol[model.body1.r[1]], sol[model.body1.r[2]]
                @test first(x) ≈ 1.0 atol=1e-8
                @test first(y) ≈ 1.0 atol=1e-8
                @test hypot(last(x) - first(x), last(y) - first(y)) > 0.1
            end
            println(nameof(analysis), ": ", sol.retcode, ", final time = ", last(sol.t))
        end
    end
end
