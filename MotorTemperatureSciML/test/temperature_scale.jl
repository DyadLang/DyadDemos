@testset "Temperature normalization follows MAX_TEMP" begin
    # Exercise a non-default scale through the full generated model. This
    # catches normalizing boundary temperatures at 200 while converting
    # output states back to degrees at a different scale.
    for scale in (100.0, 200.0)
        harness = MotorTemperatureSciML.Models.Tests.TestTNNProfile(;
            name = :scale_test, model__MAX_TEMP = scale)
        result = MotorTemperatureSciML.Models.Tests.TestTNNProfileAnalysis(;
            model = harness, stop = 1.0)
        @test successful_retcode(result.sol)
        sys = symbolic_container(result)
        for (raw, normalized) in ((sys.model.coolant_raw, sys.model.thermal.coolant_norm),
                                 (sys.model.ambient_raw, sys.model.thermal.ambient_norm))
            @test result.sol[normalized] .* scale ≈ result.sol[raw]
        end
        for (i, output) in enumerate((sys.model.T_pm, sys.model.T_stator_yoke,
                                     sys.model.T_stator_tooth, sys.model.T_stator_winding))
            @test result.sol[sys.model.thermal.T[i]] .* scale ≈ result.sol[output]
        end
    end
end
