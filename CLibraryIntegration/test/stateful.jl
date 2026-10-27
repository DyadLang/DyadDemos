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
        fy[i+1] = julia_mf(lag, 4000.)
    end
    times, vy, fy
end

@testset "Stateful ownership and rollback" begin
    h1, h2 = C.TireHandle(), C.TireHandle()
    p = Ref(C.TireParams(C.MFParams(10., 1.3, 1., .97), .5, 4000.))
    for h in (h1, h2)
        h.ptr = @ccall C.libtiremodel.tm_tire_new(p::Ref{C.TireParams})::Ptr{Cvoid}
        C.check_status(@ccall C.libtiremodel.tm_tire_reset(h::Ptr{Cvoid}, 0.0::Cdouble, 0.0::Cdouble)::Cint)
    end
    snapshot = C.tire_state(h1)
    C.check_status(@ccall C.libtiremodel.tm_tire_step(h1::Ptr{Cvoid}, 0.0::Cdouble,
        0.01::Cdouble, 0.05::Cdouble, 20.0::Cdouble, 4000.0::Cdouble)::Cint)
    @test C.get_fy(h1) > 0 && C.get_fy(h2) == 0
    C.set_tire_state!(h1, snapshot)
    @test C.tire_state(h1) == snapshot
    close(h1)
    finalize(h2) # Exercise the finalizer backstop, not just the normal close path.
    @test h1.ptr == h2.ptr == C_NULL
end

@testset "Stateful Dyad simulation and continuous limit" begin
    @named axle = C.SampledSlidingAxle()
    sys = mtkcompile(axle; additional_passes=[SynchToolkit.compile_lustre])
    prob = ODEProblem(sys, [], (0., 2.))
    sol = solve(prob, Tsit5(); abstol=1e-12, reltol=1e-12, tstops=[.2])
    times, vy, fy = discrete_reference(.005)
    vy_error = maximum(abs.(sol(times; idxs=axle.vy, continuity=:right).u .- vy))
    # Query the recorded clock times: a rounded decimal can be one float before
    # a communication point and correctly return the previous held force.
    clock_times = only(filter(c -> length(c.t) > 1, sol.discretes.collection)).t
    @test clock_times ≈ times[1:end-1]
    fy_error = maximum(abs.(sol(clock_times; idxs=axle.hold.y, continuity=:right).u .- fy[1:end-1]))
    @test ModelingToolkit.SciMLBase.successful_retcode(sol)
    @test vy_error < 1e-10
    @test fy_error < 1e-10
    # PeriodicCallback does not tick at the end of tspan.
    @test sol(2.; idxs=axle.hold.y) ≈ fy[end-1] atol=1e-10
    again = solve(ModelingToolkit.SciMLBase.remake(prob), Tsit5(); abstol=1e-12, reltol=1e-12, tstops=[.2])
    @test sol(times; idxs=axle.vy).u == again(times; idxs=axle.vy).u
    h = prob.ps[sys.tire.handle]
    @test h.ptr == C_NULL

    @variables v(t) lag(t)
    @named continuous = System([
        Dt(v) ~ julia_mf(lag, 4000.)/400,
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

@testset "Periodic output supports a period-aware consumer" begin
    @named tire = C.RelaxationTire(dt=.013, alpha0=.02)
    @named accumulator = DiscreteComponents.DiscreteIntegrator(
        method=DiscreteComponents.DiscretizationMethod.Forward())
    @named hold = DiscreteComponents.ZeroOrderHold()
    @variables x(t)
    @named model = System([tire.alpha ~ .02, connect(tire.Fy, accumulator.u),
        connect(accumulator.y, hold.u), Dt(x) ~ hold.y], t;
        systems=[tire, accumulator, hold], initial_conditions=[x=>0.])
    sys = mtkcompile(model; additional_passes=[SynchToolkit.compile_lustre])
    sol = solve(ODEProblem(sys, [], (0., .04)), Tsit5())
    ticks = only(filter(c -> length(c.t) > 1, sol.discretes.collection)).t
    @test ModelingToolkit.SciMLBase.successful_retcode(sol)
    @test ticks ≈ [0., .013, .026, .039]
    @test sol(ticks; idxs=hold.y, continuity=:right).u ≈ julia_mf(.02, 4000.) .* ticks atol=1e-10 rtol=0
end
