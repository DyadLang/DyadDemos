using MotorTemperatureSciML
using Test
using DyadInterface: symbolic_container
using SciMLBase: successful_retcode

include("../generated/tests.jl")

@testset "TNN training-profile transient analysis" begin
    # Solves the first ~37 min of the training profile (Paderborn profile 17)
    # with the untrained (near-zero-init) networks; checks the model builds
    # through the Dyad pipeline and the dynamics stay physical.
    result = MotorTemperatureSciML.Models.Tests.TestTNNProfileAnalysis()
    @test successful_retcode(result.sol)

    sys = symbolic_container(result)
    for i in 1:4
        T = result.sol[sys.model.thermal.T[i]]
        # Normalized temperature states must remain in (roughly) [0, 1].
        @test all(x -> -0.05 <= x <= 1.05, T)
    end

    # The measurement interpolator must reproduce the CSV: the first measured
    # rotor temperature is in °C (positive, sub-boiling).
    T_pm_meas0 = result.sol[sys.T_pm_meas][1]
    @test 0.0 < T_pm_meas0 < 100.0
end
