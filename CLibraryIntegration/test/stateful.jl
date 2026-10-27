# Output first, then advance the lag and the mass with this tick's inputs.
function discrete_reference(dt)
    times = collect(0.:dt:2.)
    vy, fy = zeros(length(times)), zeros(length(times))
    lag = 0.0
    for i in 1:length(times)-1
        fy[i] = julia_mf(lag, 4000.)
        alpha = steering(times[i]) - atan(vy[i]/20)
        lag += (alpha-lag) * -expm1(-20dt/.5)
        vy[i+1] = vy[i] + dt*fy[i]/400
    end
    fy[end] = fy[end-1] # No tick at the aligned final time.
    times, vy, fy
end

@testset "Stateful ownership and rollback" begin
    h1, h2 = C.TireHandle(), C.TireHandle()
    C.begin_session!(h1, 4000., 10., 1.3, 1., .97, .5, 0., 0.)
    C.begin_session!(h2, 4000., 10., 1.3, 1., .97, .5, 0., 0.)
    snapshot = C.tire_state(h1)
    C.tick_fy!(h1, .05, 0., .01, 20., 4000., 1.)
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
    h = prob.ps[sys.tire.owner]
    @test h.ptr == C_NULL
    integ = init(prob, Tsit5(); abstol=1e-12, reltol=1e-12, tstops=[.2])
    @test C.tire_state(h)[1] ≈ .005
    step!(integ, 1.999, true)
    snapshot = C.tire_state(h)
    # C rejects skipped or repeated timestamps; reaching 2 s requires 400 steps.
    @test snapshot[1] ≈ 2.
    integ.sol(.4; idxs=axle.hold.y)
    @test C.tire_state(h) == snapshot
    sol = solve!(integ)
    times, vy, fy = discrete_reference(.005)
    original_vy = copy(sol(times; idxs=axle.vy, continuity=:right).u)
    vy_error = maximum(abs.(original_vy .- vy))
    # Clock outputs have their own saved times, separate from the solver grid.
    clock_times = only(filter(c -> length(c.t) > 1, sol.discretes.collection)).t
    @test clock_times ≈ times[1:end-1]
    fy_error = maximum(abs.(sol(clock_times; idxs=axle.hold.y, continuity=:right).u .- fy[1:end-1]))
    @test ModelingToolkit.SciMLBase.successful_retcode(sol)
    @test vy_error < 1e-10
    @test fy_error < 1e-10
    @test sol(2.; idxs=axle.hold.y) ≈ fy[end-1] atol=1e-10
    again = solve(ModelingToolkit.SciMLBase.remake(prob), Tsit5(); abstol=1e-12, reltol=1e-12, tstops=[.2])
    remake_error = maximum(abs.(original_vy .- again(times; idxs=axle.vy).u))
    @test remake_error < 1e-12
    @test h.ptr == C_NULL
    reinit!(integ)
    @test C.tire_state(h)[1] ≈ .005
    replay = solve!(integ)
    reinit_error = maximum(abs.(original_vy .- replay(times; idxs=axle.vy).u))
    @test reinit_error < 1e-12
    @test h.ptr == C_NULL

    reject_once = Ref(true)
    reject(u, p, t) = if reject_once[]
        reject_once[] = false
        true
    else
        false
    end
    implicit = init(prob, Rodas5P(); dt=.1, abstol=1e-12, reltol=1e-12,
        tstops=[.2], isoutofdomain=reject)
    step!(implicit, 1.999, true)
    @test C.tire_state(h)[1] ≈ 2.
    rodas = solve!(implicit)
    @test ModelingToolkit.SciMLBase.successful_retcode(rodas) && rodas.stats.nreject > 0
    rodas_error = maximum(abs.(rodas(times; idxs=axle.vy, continuity=:right).u .- vy))
    @test rodas_error < 1e-10
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
    @info "Stateful reference errors" vy_error fy_error rodas_error continuous_error fine_error remake_error reinit_error rejected=rodas.stats.nreject
end
