@testset "Training schedule rejects ill-defined shooting problems" begin
    M = MotorTemperatureSciML
    spec(; kwargs...) = M.TNNTrainingAnalysisSpec(; model = nothing, kwargs...)
    @test M.check_schedule(spec()) == 96
    for kwargs in ((; train_horizon = 0.0), (; window = -1.0),
                   (; train_horizon = Inf), (; learning_rate = NaN),
                   (; continuity_tol = 0.0), (; batch_size = 0),
                   (; block_size = 0), (; inner_epochs = 0),
                   (; outer_maxiters = 0), (; window = 74.0),
                   (; batch_size = 31), (; block_size = 3),
                   (; train_horizon = 75.0))
        @test_throws ErrorException M.check_schedule(spec(; kwargs...))
    end
end
