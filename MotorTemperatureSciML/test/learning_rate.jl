@testset "Adam callback refines physical shooting-state steps" begin
    M = MotorTemperatureSciML
    O = M.Optimisers
    callbacks = Ref(0)
    alg = M.make_sms(; n_segments = 96, batch_size = 32, block_size = 4,
        learning_rate = 1e-3, inner_epochs = 12, outer_maxiters = 30,
        inner_kwargs = (; callback = (args...) -> (callbacks[] += 1; false)))
    θ = [0.35]
    optstate = O.setup(M.Adam(1e-3), θ)
    cb = alg.inner_kwargs.callback
    previous_step = 0
    # Check the applied Optimisers update, not only a computed schedule value.
    # A constant gradient makes Adam's bias-corrected normalized update one.
    for (step, expected_step_C) in ((1, 0.2), (300, 0.05), (3000, 0.02))
        for _ in (previous_step + 1):step
            cb((; original = optstate), 0.0)
        end
        before = θ[1]
        optstate, θ = O.update(optstate, θ, [1.0])
        @test (before - θ[1]) * M.STORY_MAX_TEMP ≈ expected_step_C rtol = 1e-6
        previous_step = step
    end
    @test callbacks[] == 3000
end
