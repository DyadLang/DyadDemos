using ModelingToolkit: getdefault
using StaticArrays: SVector

# Summing the evaluations keeps the calls live: with the result unused the
# compiler can delete them, and a function that does allocate would measure 0.
function sum_evaluations(itp, ts)
    s = itp(first(ts))
    for x in ts
        s = s .+ itp(x)
    end
    return s
end

# Measured inside a function, and after a warm-up call, so neither compilation
# nor an untyped global ends up in the count.
function bytes_per_call(itp, ts)
    sum_evaluations(itp, ts)
    return @allocated(sum_evaluations(itp, ts)) / length(ts)
end

@testset "FastVectorInterpolation evaluates without allocating" begin
    # Measured signals enter the model through `FastVectorInterpolation`
    # (dyad/definitions.jl), which stores `u` as one `SVector` per time sample
    # so each evaluation returns an `SVector` and touches nothing on the heap.
    # The earlier (n_channels, n_times) matrix layout allocated the result
    # vector, and the slope vector too, on every RHS call: 288 B/call for the
    # 4-channel interpolator and 433 B/call for the 10-channel one.
    result = MotorTemperatureSciML.Models.Tests.TestTNNProfileAnalysis(stop = 10.0)
    @test successful_retcode(result.sol)
    sys = symbolic_container(result)

    # Well inside the profile, so this is interpolation rather than extrapolation.
    ts = collect(range(1.0, 1000.0; length = 200))
    for name in (:interp_meas, :interp_inputs)
        itp = getdefault(getproperty(sys, name).interpolator)
        @test eltype(itp.u) <: SVector
        @test bytes_per_call(itp, ts) == 0
    end
end
