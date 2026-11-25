# Tests for the VehicleComponents module and the sedan model.
#
# The sedan maneuvers are regressed against reference trajectories generated
# by running the original vehicle model this one was ported from (see
# validation/sedan_chrono/README.md) with the same TMeasy tire model and
# parameters. Statics match to a fraction of a percent and dynamic responses
# to a few percent; remaining differences come from the reference's
# fixed-step (0.1 ms) integration, its discrete-time bristle low-speed model,
# and minor contact-geometry differences.
using ModelingToolkit, MultibodyComponents, SedanDemo
using OrdinaryDiffEq
using DyadInterface: simplify_model
using ModelingToolkit: t_nounits as t
using DelimitedFiles
using LinearAlgebra
using Test
using ADTypes
using SciMLBase: successful_retcode, ReturnCode
import RotationalComponents

testrender = get(ENV, "TEST_RENDERING", "false") == "true"
testrender && import GLMakie

const VD = SedanDemo.VehicleComponents

read_reference(name) = readdlm(joinpath(@__DIR__, "references", "sedan", name), ',', Float64; skipstart = 1)
# reference CSV columns (see validation/sedan_chrono/sedan_common.py)
const REF = (t = 1, x = 2, y = 3, z = 4, roll = 5, pitch = 6, yaw = 7, speed = 8,
    gear = 9, rpm = 10, fz_FL = 15, fz_FR = 16, fz_RL = 17, fz_RR = 18)
ref_at(data, time, col) = data[argmin(abs.(data[:, REF.t] .- time)), col]

@testset "TMeasy tire characteristic" begin
    # exact anchor points of the piecewise slip curve (passenger-car pattern
    # at the sedan's nominal load)
    pn = 3580.65
    df0, sm, fm, ss, fs = 18.3741 * pn, 0.13913, 1.1292 * pn, 0.66667, 0.80149 * pn
    fx(s) = SedanDemo.VehicleComponents.tmeasy_force(s, df0, sm, fm, ss, fs)
    @test fx(0.0) == 0
    @test fx(sm) ≈ fm rtol = 1e-12          # adhesion maximum
    @test fx(ss) ≈ fs rtol = 1e-9           # start of full sliding
    @test fx(1.0) ≈ fs rtol = 1e-12         # full sliding
    @test fx(1e-6) / 1e-6 ≈ df0 rtol = 1e-3 # initial slope
    @test all(diff(fx.(range(0, sm; length = 200))) .> 0)    # monotone up to the peak
    @test all(diff(fx.(range(sm, ss; length = 200))) .<= 0)  # falling to full sliding
    # sine_step endpoints and midpoint
    @test SedanDemo.VehicleComponents.sine_step(0.5, 1, 0, 3, 1) == 0
    @test SedanDemo.VehicleComponents.sine_step(2.0, 1, 0, 3, 1) ≈ 0.5
    @test SedanDemo.VehicleComponents.sine_step(3.5, 1, 0, 3, 1) == 1
end

@testset "EngineCVTMap" begin
    @named eng = VD.EngineCVTMap()
    @named source = RotationalComponents.Sources.VelocitySource(ref_type = RotationalComponents.Sources.ReferenceType.Exact())
    @named fixed = RotationalComponents.Components.Fixed()
    conns = [
        ModelingToolkit.connect(source.spline, eng.driveshaft)
        ModelingToolkit.connect(source.support, fixed.spline)
        ModelingToolkit.connect(eng.support, fixed.spline)
        source.w_ref ~ 40.0 + 60.0 * t
        eng.throttle ~ 1.0
    ]
    @named rig = ModelingToolkit.System(conns, t; systems = [eng, source, fixed])
    sys = mtkcompile(rig)
    @test isempty(continuous_events(sys))
    @test isempty(discrete_events(sys))
    sol = solve(ODEProblem(sys, [sys.source.phi => 0.0], (0.0, 10.0)),
        Rodas5P(autodiff = AutoFiniteDiff()))
    @test successful_retcode(sol)
    # Starts at the lowest ratio and changes smoothly as driveshaft speed rises.
    @test sol(0.0, idxs = sys.eng.ratio) ≈ 0.265 atol = 1e-6
    ratios = [sol(tt, idxs = sys.eng.ratio) for tt in 0:0.1:10]
    @test ratios[end] > ratios[1]
    @test all(0.26 .< ratios .< 1.51)
    @test maximum(abs.(diff(ratios))) < 0.05
    # Away from both ratio limits, the CVT holds engine speed at its target.
    @test sol(5.0, idxs = sys.eng.engine_rpm) ≈ 4000 rtol = 1e-4
    # At the upper-ratio regime the command approaches the configured maximum.
    @test sol(10.0, idxs = sys.eng.ratio_command) ≈ 1.499 rtol = 1e-4
    # Ideal kinematic torque multiplication is preserved continuously.
    @test sol(5.0, idxs = sys.eng.tau_ds) ≈
        sol(5.0, idxs = sys.eng.engine_torque) / sol(5.0, idxs = sys.eng.ratio) rtol = 1e-9
end

@testset "Differential1D" begin
    @named diff = VD.Differential1D()
    @named left = RotationalComponents.Sources.VelocitySource(ref_type = RotationalComponents.Sources.ReferenceType.Exact())
    @named right = RotationalComponents.Sources.VelocitySource(ref_type = RotationalComponents.Sources.ReferenceType.Exact())
    @named drive = RotationalComponents.Components.Inertia(J = 1.0)
    @named ground = RotationalComponents.Components.Fixed()
    conns = [
        ModelingToolkit.connect(left.spline, diff.flange_left)
        ModelingToolkit.connect(right.spline, diff.flange_right)
        ModelingToolkit.connect(drive.spline_a, diff.flange_drive)
        ModelingToolkit.connect(left.support, ground.spline)
        ModelingToolkit.connect(right.support, ground.spline)
        left.w_ref ~ 1.0
        right.w_ref ~ 3.0
    ]
    @named rig = ModelingToolkit.System(conns, t; systems = [diff, left, right, drive, ground])
    sys = mtkcompile(rig)
    sol = solve(ODEProblem(sys, [sys.drive.phi => 0.0, sys.right.phi => 0.0], (0.0, 1.0)), Rodas5P(autodiff = AutoFiniteDiff()))
    @test successful_retcode(sol)
    # drive turns at the mean of the two outputs
    @test sol(1.0, idxs = sys.drive.w) ≈ 2.0 rtol = 1e-6
end

@testset "Brake" begin
    @named brake = VD.Brake(tau_max = 100.0)
    @named inertia = RotationalComponents.Components.Inertia(J = 1.0)
    @named fixed = RotationalComponents.Components.Fixed()
    conns = [
        ModelingToolkit.connect(inertia.spline_a, brake.spline_a)
        ModelingToolkit.connect(fixed.spline, brake.spline_b)
        brake.braking ~ 1.0
    ]
    @named rig = ModelingToolkit.System(conns, t; systems = [brake, inertia, fixed])
    sys = mtkcompile(rig)
    sol = solve(ODEProblem(sys, [sys.inertia.w => 10.0, sys.inertia.phi => 0.0], (0.0, 0.15)),
        Rodas5P(autodiff = AutoFiniteDiff()))
    @test successful_retcode(sol)
    # full braking decelerates the inertia at ~tau_max/J until near standstill
    @test sol(0.05, idxs = sys.inertia.w) ≈ 5.0 atol = 0.2
    @test abs(sol(0.15, idxs = sys.inertia.w)) < 0.5
end

@testset "ABSBrake" begin
    # A wheel rolling at ground speed v, braked at full command with no tire
    # torque to spin it back up. The slip limiter removes the torque as the
    # braking slip reaches slip_off, so the wheel settles at (1 - slip_off) v / r
    # instead of locking; with the limiter off, or below v_off, it locks.
    r, v, slip_off = 0.3, 10.0, 0.16
    function braked_wheel(abs_enabled, v_ground)
        @named brake = VD.ABSBrake(tau_max = 100.0, r = r, slip_on = 0.08, slip_off = slip_off; abs_enabled)
        @named inertia = RotationalComponents.Components.Inertia(J = 1.0)
        @named fixed = RotationalComponents.Components.Fixed()
        conns = [
            ModelingToolkit.connect(inertia.spline_a, brake.spline_a)
            ModelingToolkit.connect(fixed.spline, brake.spline_b)
            brake.braking ~ 1.0
            brake.v ~ v_ground
        ]
        @named rig = ModelingToolkit.System(conns, t; systems = [brake, inertia, fixed])
        sys = mtkcompile(rig)
        prob = ODEProblem(sys, [sys.inertia.w => v / r, sys.inertia.phi => 0.0], (0.0, 1.0))
        return sys, solve(prob, Rodas5P(autodiff = AutoFiniteDiff()))
    end
    slip(w) = 1 - abs(w) * r / v
    sys, sol = braked_wheel(true, v)
    @test successful_retcode(sol)
    @test maximum(slip, sol(0:0.005:1.0, idxs = sys.inertia.w).u) <= slip_off + 1e-6
    @test slip(sol(1.0, idxs = sys.inertia.w)) ≈ slip_off atol = 1e-3
    sys_off, sol_off = braked_wheel(false, v)
    @test abs(sol_off(1.0, idxs = sys_off.inertia.w)) < 0.5
    sys_slow, sol_slow = braked_wheel(true, 0.5)
    @test abs(sol_slow(1.0, idxs = sys_slow.inertia.w)) < 0.5
end

@testset "AEBController with IdealRangeSensor" begin
    # A point mass that decelerates at a_max per unit brake command approaches a
    # stationary target from v0 (REQ-AEB-1, REQ-AEB-4). The AEB stops it with
    # about d_stop = 1 m left and cuts the throttle while it brakes. With a
    # request threshold beyond what the brakes deliver, the mass reaches the
    # target; with the target clear of the vehicle's width, the AEB never brakes.
    # Under yaw, the part of the turned bumper inside the target's lateral span sets
    # the gap and the overlap.
    a_max, v0, x_target = 9.0, 20.0, 60.0
    function approach(; a_on = 5.0, target_z = 0.0, yaw = 0.0)
        @named target = VD.StationaryTarget(x = x_target, z = target_z)
        @named sensor = VD.IdealRangeSensor(l_front = 0.0)
        @named aeb = VD.AEBController(a_on = a_on, a_full = a_on + 3)
        @variables x(t) v(t)
        D = Differential(t)
        eqs = [D(x) ~ v
               D(v) ~ -a_max * aeb.braking * tanh(v / 0.05)
               sensor.x ~ x
               sensor.z ~ 0
               sensor.yaw ~ yaw
               sensor.v ~ v
               aeb.throttle_in ~ 1.0
               ModelingToolkit.connect(target.x_rear, sensor.target_x)
               ModelingToolkit.connect(target.z_center, sensor.target_z)
               ModelingToolkit.connect(target.width, sensor.target_width)
               ModelingToolkit.connect(sensor.gap, aeb.gap)
               ModelingToolkit.connect(sensor.closing_speed, aeb.closing_speed)
               ModelingToolkit.connect(sensor.in_path, aeb.in_path)]
        @named rig = ModelingToolkit.System(eqs, t; systems = [target, sensor, aeb])
        sys = mtkcompile(rig)
        prob = ODEProblem(sys, [sys.x => 0.0, sys.v => v0], (0.0, 8.0))
        sol = solve(prob, Rodas5P(autodiff = AutoFiniteDiff()); saveat = 0.01)
        @test successful_retcode(sol)
        return sys, sol
    end
    sys, sol = approach()
    gap, braking, throttle = sol[sys.sensor.gap], sol[sys.aeb.braking], sol[sys.aeb.throttle]
    @test minimum(gap) > 0
    @test gap[end] ≈ 1.0 atol = 0.1
    @test abs(sol[sys.v][end]) < 0.05
    @test all(throttle[braking .>= 0.02] .== 0)
    @test maximum(braking) < 1    # the request stays below saturation
    sys_late, sol_late = approach(a_on = 12.0)
    @test minimum(sol_late[sys_late.sensor.gap]) < 0
    sys_miss, sol_miss = approach(target_z = 2.0)
    @test maximum(sol_miss[sys_miss.aeb.braking]) == 0
    # Yaw 30°: the rotation about +y maps the body (x, z) axes to the columns of R.
    # The gap runs from the farthest-forward bumper point inside the target's span,
    # with the target centered and with only the bumper's trailing end facing it.
    w, w_target = sol.ps[sys.sensor.w], sol.ps[sys.target.w]
    θ = deg2rad(30)
    R = [cos(θ) sin(θ); -sin(θ) cos(θ)]
    bumper = [R * [0, s] for s in range(-w / 2, w / 2; length = 20001)]
    for target_z in (0.0, -1.5)
        sys_yaw, sol_yaw = approach(target_z = target_z, yaw = θ)
        facing = filter(p -> abs(last(p) - target_z) <= w_target / 2, bumper)
        expected = x_target .- sol_yaw[sys_yaw.x] .- maximum(first, facing)
        @test maximum(abs, sol_yaw[sys_yaw.sensor.gap] .- expected) < 1e-4
    end
    # A target 5 cm clear of the turned bumper's span, inside the straight bumper's span
    z_clear = maximum(p -> abs(last(p)), bumper) + w_target / 2 + 0.05
    @test z_clear < (w + w_target) / 2
    sys_clear, sol_clear = approach(target_z = z_clear, yaw = θ)
    @test maximum(sol_clear[sys_clear.aeb.braking]) == 0
end

@testset "DoubleWishboneSuspension corner" begin
    # one corner hanging off a fixed chassis settles at a slight droop
    # closed_form = false keeps the position-constraint loop (Newton-closed)
    for closed_form in (true, false), mirror in (false, true)
        @named world = MultibodyComponents.World()
        @named corner = VD.DoubleWishboneSuspension(mirror = mirror, closed_form = closed_form)
        conns = [ModelingToolkit.connect(world.frame_b, corner.chassis_frame)]
        @named model = ModelingToolkit.System(conns, t; systems = [world, corner])
        ssys = simplify_model(model)
        # 1 travel DOF (phi, w); the loop form adds 4 position-level loop coordinates
        @test length(unknowns(ssys)) == (closed_form ? 2 : 6)
        prob = ODEProblem(ssys, [ssys.corner.lca_rev.phi => 0.0, ssys.corner.lca_rev.w => 0.0],
            (0.0, 3.0); optimize = :basic)
        sol = solve(prob, Rodas5P(autodiff = AutoFiniteDiff()))
        @test successful_retcode(sol)
        dir = mirror ? -1.0 : 1.0
        # starts exactly at the hardpoint geometry
        @test sol(0.0, idxs = ssys.corner.upright_to_spindle.frame_b.r_0) ≈ [0, -0.1199, dir * 0.7979] atol = 1e-6
        # settles against the spring at a small droop, mirrored exactly
        @test sol(3.0, idxs = ssys.corner.lca_rev.phi) ≈ -dir * 0.008076 atol = 2e-4
        @test sol(3.0, idxs = ssys.corner.springdamper.s) ≈ 0.5101 atol = 5e-4
    end
end

@testset "Sedan settle" begin
    ref = read_reference("settle.csv")
    @named model = SedanDemo.SedanSettle()
    ssys = simplify_model(model)
    prob = ODEProblem(ssys, [], (0.0, 4.0); optimize = :basic)
    sol = solve(prob, Rodas5P(autodiff = AutoFiniteDiff()))
    @test successful_retcode(sol)
    V = ssys.sedan.vehicle
    fns = [sol(4.0, idxs = getproperty(getproperty(V, c).wheel.wheeljoint, :f_n))
           for c in (:corner_fl, :corner_fr, :corner_rl, :corner_rr)]
    ref_fns = [ref_at(ref, 3.99, c) for c in (REF.fz_FL, REF.fz_FR, REF.fz_RL, REF.fz_RR)]
    # per-corner static loads within 1 %, total equals the vehicle weight
    @test all(abs.(fns .- ref_fns) ./ ref_fns .< 0.01)
    m_total = 1550 + 1.889 + 4 * (1.103 + 1.397 + 1.032 + 1.611 + 13.2 + 11.5)
    @test sum(fns) ≈ m_total * 9.80665 rtol = 5e-3
    # ride height and pitch (reference z-up height = world y; both nose-down)
    @test sol(4.0, idxs = V.chassis.r_0[2]) ≈ ref_at(ref, 3.99, REF.z) atol = 2e-3
    @test sol(4.0, idxs = V.chassis.phi[3]) ≈ -ref_at(ref, 3.99, REF.pitch) atol = 2e-3
    # perfect left/right symmetry
    @test abs(sol(4.0, idxs = V.chassis.phi[1])) < 1e-6
    testrender && render(model, sol, 0.0)[1]
end

@testset "Sedan acceleration" begin
    ref = read_reference("accel.csv")
    @time "instantiate" @named model = SedanDemo.SedanAcceleration()
    @time "simplify_model" ssys = simplify_model(model)
    @time "ODEProblem" prob = ODEProblem(ssys, [], (0.0, 17.0); optimize = :basic)
    @time "simulation" sol = solve(prob, Rodas5P(autodiff = AutoFiniteDiff()))
    @test successful_retcode(sol)
    S = ssys.sedan
    # The CVT changes the engine operating path relative to the six-speed Chrono
    # reference, but the acceleration remains in the same magnitude class.
    for tt in 8:1.0:17
        vref = ref_at(ref, tt, REF.speed)
        @test abs(sol(tt, idxs = S.v) - vref) / vref < 0.15
    end
    @test abs(sol(16.0, idxs = S.v) - ref_at(ref, 16.0, REF.speed)) / ref_at(ref, 16.0, REF.speed) < 0.06
    speeds = [sol(tt, idxs = S.v) for tt in 1:0.1:17]
    @test all(diff(speeds) .> 0)
    # The CVT ratio remains bounded and varies continuously without shift events.
    ratios = [sol(tt, idxs = S.engine.ratio) for tt in 1:0.1:17]
    @test all(0.2649 .< ratios .< 1.5001)
    @test maximum(abs.(diff(ratios))) < 0.15
    @test isempty(continuous_events(ssys))
    @test isempty(discrete_events(ssys))
    # lateral drift: the transient driveline spin-up roll unloads one rear
    # wheel, which breaks loose first through the open differential; the
    # asymmetric thrust yaws the car to the right in both simulators. Same
    # direction and magnitude class (several meters over the ~450 m run).
    zdrift = sol(12.0, idxs = S.z)
    ydrift_ref = ref_at(ref, 12.0, REF.y)
    @test sign(zdrift) == -sign(ydrift_ref)
    @test abs(ydrift_ref) / 3 < abs(zdrift) < 3 * abs(ydrift_ref)
end

@testset "Sedan step steer" begin
    ref = read_reference("step_steer.csv")
    @named model = SedanDemo.SedanStepSteer()
    ssys = simplify_model(model)
    prob = ODEProblem(ssys, [], (0.0, 16.0); optimize = :basic)
    sol = solve(prob, Rodas5P(autodiff = AutoFiniteDiff()))
    @test successful_retcode(sol)
    S = ssys.sedan
    # cruise speed held within 3 % before and during the turn
    @test sol(11.9, idxs = S.v) ≈ ref_at(ref, 11.9, REF.speed) rtol = 0.03
    @test sol(15.0, idxs = S.v) ≈ ref_at(ref, 15.0, REF.speed) rtol = 0.03
    # positive steering step turns left (positive yaw) in both
    @test sol(14.0, idxs = S.yaw) > 0.3
    @test ref_at(ref, 14.0, REF.yaw) > 0.3
    # steady-state yaw rate within 5 % (mean over the window where yaw < 60 deg)
    yawrate(s, t1, t2) = (s(t2, idxs = S.yaw) - s(t1, idxs = S.yaw)) / (t2 - t1)
    yr = yawrate(sol, 13.0, 15.0)
    yr_ref = (ref_at(ref, 15.0, REF.yaw) - ref_at(ref, 13.0, REF.yaw)) / 2
    @test abs(yr - yr_ref) / yr_ref < 0.05
end

@testset "Sedan double lane change" begin
    ref = read_reference("dlc.csv")
    @named model = SedanDemo.SedanDoubleLaneChange()
    ssys = simplify_model(model)
    prob = ODEProblem(ssys, [], (0.0, 16.0); optimize = :basic)
    sol = solve(prob, Rodas5P(autodiff = AutoFiniteDiff()))
    @test successful_retcode(sol)
    S = ssys.sedan
    # course completed: swings ~4 m left and returns to center
    zmin = minimum(sol(tt, idxs = S.z) for tt in 9:0.1:13)
    @test -4.7 < zmin < -3.3
    @test abs(sol(15.0, idxs = S.z)) < 0.5
    # the reference peak offset (its y-left is our -z), in the same window,
    # relative to its own start position
    y0 = ref_at(ref, 0.0, REF.y)
    ypeak = maximum(ref_at(ref, tt, REF.y) - y0 for tt in 9:0.1:13)
    @test abs(-zmin - ypeak) < 0.5
    # speed held within 5 % of the reference cruise speed
    @test sol(8.0, idxs = S.v) ≈ ref_at(ref, 8.0, REF.speed) rtol = 0.05
end
