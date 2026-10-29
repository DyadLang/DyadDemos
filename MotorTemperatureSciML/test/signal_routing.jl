@testset "Mux/demux preserve channel ordering" begin
    result = MotorTemperatureSciML.Models.Tests.TestTNNProfileAnalysis(stop = 10.0)
    @test successful_retcode(result.sol)
    sys = symbolic_container(result)
    # Check every channel against its source, not just the first temperature.
    # Sampling away from t=0 exercises interpolation as well as the wiring.
    times = [0.0, 0.25, 3.75, 10.0]
    values(v) = result.sol(times; idxs = v).u
    inputs = (:u_q, :coolant, :u_d, :motor_speed, :i_d, :i_q,
              :ambient, :torque, :i_s, :u_s)
    for (i, input) in enumerate(inputs)
        @test values(getproperty(sys.model, Symbol(input, :_raw))) ≈
              values(sys.interp_inputs.y[i])
    end
    for (i, measured) in enumerate((sys.T_pm_meas, sys.T_sy_meas,
                                    sys.T_st_meas, sys.T_sw_meas))
        @test values(measured) ≈ values(sys.interp_meas.y[i])
    end
    for net in (sys.model.cond_net, sys.model.ploss_net)
        for i in 1:10
            @test values(net.nn.inputs[i]) ≈ values(sys.model.normalizer.out[i])
        end
        for i in 1:4
            @test values(net.nn.inputs[10 + i]) ≈ values(sys.model.thermal.T[i])
        end
    end
end
