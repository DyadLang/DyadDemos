steering(t) = ifelse(t < 0.2, 0.0, 0.04 + 0.01 * sin(2pi * (t - 0.2)))

@testset "Stateless C function and both derivative bridges" begin
    angles = range(-0.2, 0.2; length=41)
    f(a) = C.mf_fy(a, 4000., 10., 1.3, 1., .97)
    df(a) = C.mf_dfy_dalpha(a, 4000., 10., 1.3, 1., .97)
    reference(a) = C.julia_mf(a, 4000.)
    value_error = maximum(abs(f(a) - reference(a)) for a in angles)
    derivative_error = maximum(abs(df(a) - ForwardDiff.derivative(reference, a)) for a in angles)
    fd_error = maximum(abs(df(a) - (f(a+1e-6)-f(a-1e-6))/2e-6) for a in angles)
    @test value_error < 1e-11
    @test derivative_error < 1e-9
    @test fd_error < 1e-4
    @test ForwardDiff.derivative(f, .05) ≈ df(.05)

    @named axle = C.SlidingAxle()
    sys = mtkcompile(axle)
    @test occursin("mf_dfy_dalpha", string(ModelingToolkit.calculate_jacobian(sys)))
    # jac=false leaves Rodas5P's numerical ForwardDiff Jacobian enabled.
    prob = ODEProblem(sys, [], (0., 2.); jac=false)
    sol = solve(prob, Rodas5P(); abstol=1e-11, reltol=1e-11, tstops=[.2])
    @variables v(t)
    @named ref = System([Dt(v) ~ C.julia_mf(steering(t)-atan(v/20), 4000.)/400], t)
    refsol = solve(ODEProblem(mtkcompile(ref), [v=>0.], (0., 2.)), Tsit5();
        abstol=1e-12, reltol=1e-12, tstops=[.2])
    grid = 0.:.005:2.
    simulation_error = maximum(abs.(sol(grid; idxs=axle.vy).u .- refsol(grid; idxs=v).u))
    @test ModelingToolkit.SciMLBase.successful_retcode(sol)
    @test ModelingToolkit.SciMLBase.successful_retcode(refsol)
    @test simulation_error < 1e-8
    @info "Stateless reference errors" value_error derivative_error fd_error simulation_error
end
