using DyadInterface

@testset "Undamped oscillator analytical solution" begin
    # Save on the comparison grid before reconstructing the serialized solution.
    result = MakieWebinar.NoDampingAnalysis(saveat=0.1)
    sol = DyadInterface.rebuild_sol(result)
    model = result.sys
    times = collect(range(0.0, 10.0; length=101))
    position = vec(Array(sol(times; idxs=model.system.mass.s)))
    velocity = vec(Array(sol(times; idxs=model.system.mass.v)))
    position_error = maximum(abs.(position .- 0.5 .* cos.(10 .* times)))
    velocity_error = maximum(abs.(velocity .+ 5 .* sin.(10 .* times)))
    energy = 0.5 .* velocity.^2 .+ 50 .* position.^2
    relative_energy_error = maximum(abs.(energy .- 12.5)) / 12.5
    @info "Undamped oscillator error" position_error velocity_error relative_energy_error
    @test position_error < 2e-4
    @test velocity_error < 2e-3
    @test relative_energy_error < 1e-3
end
