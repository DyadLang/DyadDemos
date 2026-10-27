# The host's exact discrete reference: constant force moves the mass linearly;
# constant slip advances the C lag by an exponential over the same interval.
function discrete_reference(dt)
    times = collect(0.:dt:2.)
    vy, fy = zeros(length(times)), zeros(length(times))
    lag = 0.0
    for i in 1:length(times)-1
        alpha = steering(times[i]) - atan(vy[i]/20)
        vy[i+1] = vy[i] + dt*fy[i]/400
        lag += (alpha-lag) * -expm1(-20dt/.5)
        fy[i+1] = C.julia_mf(lag, 4000.)
    end
    times, vy, fy
end

@testset "Stateful ownership and rollback" begin
    h1, h2 = C.TireHandle(), C.TireHandle()
    inputs(h) = (; handle=h, B=10., C=1.3, D=1., E=.97, sigma=.5,
        Fz=4000., vx=20., alpha0=0., alpha=.05, t=0.)
    C.initialize_tire!((;), inputs(h1), nothing, nothing)
    C.initialize_tire!((;), inputs(h2), nothing, nothing)
    snapshot = C.tire_state(h1)
    C.step_tire!((;), merge(inputs(h1), (;t=.01)), nothing, nothing)
    @test C.get_fy(h1) > 0 && C.get_fy(h2) == 0
    C.set_tire_state!(h1, snapshot)
    @test C.tire_state(h1) == snapshot
    close(h1)
    finalize(h2) # Exercise the finalizer backstop, not just the normal close path.
    @test h1.ptr == h2.ptr == C_NULL
    @test h1.allocations == h1.frees == h2.allocations == h2.frees == 1
end

@testset "Stateful Dyad simulation and continuous limit" begin
    @named axle = C.SampledSlidingAxle()
    sys = mtkcompile(axle)
    prob = ODEProblem(sys, [], (0., 2.))
    sol = solve(prob, Tsit5(); abstol=1e-12, reltol=1e-12, tstops=[.2])
    times, vy, fy = discrete_reference(.005)
    vy_error = maximum(abs.(sol(times; idxs=axle.vy, continuity=:right).u .- vy))
    # Query the recorded clock times: a rounded decimal can be one float before
    # a communication point and correctly return the previous held force.
    clock_times = only(sol.discretes.collection).t
    @test clock_times ≈ times[1:end-1]
    fy_error = maximum(abs.(sol(clock_times; idxs=axle.tire.Fy, continuity=:right).u .- fy[1:end-1]))
    @test ModelingToolkit.SciMLBase.successful_retcode(sol)
    @test vy_error < 1e-10
    @test fy_error < 1e-10
    # PeriodicCallback does not tick at the end of tspan.
    @test sol(2.; idxs=axle.tire.Fy) ≈ fy[end-1] atol=1e-10
    again = solve(ModelingToolkit.SciMLBase.remake(prob), Tsit5(); abstol=1e-12, reltol=1e-12, tstops=[.2])
    @test sol(times; idxs=axle.vy).u == again(times; idxs=axle.vy).u
    h = prob.ps[sys.tire.handle]
    @test h.ptr == C_NULL && h.allocations == h.frees == 2

    @variables v(t) lag(t)
    @named continuous = System([
        Dt(v) ~ C.julia_mf(lag, 4000.)/400,
        Dt(lag) ~ 20/.5*(steering(t)-atan(v/20)-lag)], t)
    ref = solve(ODEProblem(mtkcompile(continuous), [v=>0., lag=>0.], (0., 2.)),
        Tsit5(); abstol=1e-12, reltol=1e-12, tstops=[.2])
    continuous_error = maximum(abs.(vy .- ref(times; idxs=v).u))
    fine_times, fine_vy, _ = discrete_reference(.0025)
    fine_error = maximum(abs.(fine_vy .- ref(fine_times; idxs=v).u))
    @test ModelingToolkit.SciMLBase.successful_retcode(ref)
    # A 5 ms step is one fifth of the 25 ms lag time. Bound velocity error
    # to 0.02 m/s (2.5% of U*delta), and require first-order refinement.
    @test continuous_error < .02
    @test fine_error < .6continuous_error
    @info "Stateful reference errors" vy_error fy_error continuous_error fine_error
end
