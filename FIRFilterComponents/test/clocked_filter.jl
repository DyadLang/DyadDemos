using DyadInterface

function check_clocked_filter(input, output)
    @testset "Clocked FIR response" begin
        @test length(input) == 26
        @test length(output) == 26
        @test all(isfinite, input) && all(isfinite, output)
        # The five taps act on the current sample and four preceding samples.
        taps = (-3/16, 31/32, 0.0, -31/32, 3/16)
        expected = [sum(taps[j] * (i >= j ? input[i-j+1] : 0.0)
                        for j in eachindex(taps)) for i in eachindex(input)]
        error = maximum(abs.(output .- expected))
        @info "Clocked FIR response" samples=length(output) max_error=error peak=maximum(abs, output)
        @test error < 1e-10
        @test maximum(abs, output) > 0.1
    end
end

function check_clocked_filter(result)
    sol = DyadInterface.rebuild_sol(result)
    # Clocked signals are stored as parameter timeseries, separate from ODE states.
    input = Float64.(sol[result."sampler.y"])
    output = Float64.(sol[result."firfilter.realoutput"])
    check_clocked_filter(input, output)
end
