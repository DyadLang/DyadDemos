@testset "Shooting states start on the measured training trajectory" begin
    M = MotorTemperatureSciML
    D = M.DyadModelOptimizer
    sys = M.simplify_model(M.Models.Tests.TestTNNProfile(; name = :training_profile))
    experiment = M.build_experiment(sys; tspan = (0.0, 7200.0), name = "initialization_test")
    invprob = M.build_invprob(experiment, M.build_search_space(sys))
    alg = M.make_sms(; n_segments = 96, batch_size = 32, block_size = 4,
        learning_rate = 1e-3, inner_epochs = 12, outer_maxiters = 30)
    x0 = D.initial_state(alg, invprob)
    n_params = length(D.search_space_names(invprob))
    starts = reshape(x0[(n_params + 1):end], 4, :)
    (; t, meas) = M.profile_data(sys)
    depvars = M.temperature_depvars(sys)
    # Each ODE state can be a connector alias, in an arbitrary order. The
    # measured value paired with it must survive initialization at all 95
    # junctions, including the hot plateau (far from the initial temperature).
    for (i, (_, key)) in enumerate(depvars)
        channel = only(findall(==(key), M.CHANNEL_KEYS))
        expected = [meas[channel, only(findall(==(75.0 * k), t))] / 200 for k in 1:95]
        @test starts[i, :] ≈ expected rtol = 1e-12 atol = 1e-12
    end
    @test maximum(starts) > 0.3  # Catches the library's constant-u0 fallback.
    @test M.temperature_channel_order(sys, starts) ≈ meas[:, 151:150:14251] ./ 200
end
