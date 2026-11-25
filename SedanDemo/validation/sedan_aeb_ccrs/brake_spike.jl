# Straight-line braking capability of the Sedan, with and without ABS.
#
# A P speed controller brings the car to about 80 km/h while a path follower holds
# it on z = 0; at `t_brake` the throttle drops to zero and the brake command steps
# to `b_cmd`. Cases vary the command, the rear brake torque and whether the
# brakes' slip limiters (ABS) are enabled. For each case the
# script reports the mean fully developed deceleration (MFDD, 0.8 v0 to 0.1 v0),
# the peak deceleration, the lowest wheel speed ratio omega*r/v while v > 2 m/s
# (near 0 = locked), the lateral drift, and the stop, and writes brake_spike.toml.
# Cases marked `trace` also write 200 Hz time series to brake_traces.csv, from
# 0.5 s before brake onset to 3 s after it (t_s is measured from brake onset).
#
#   julia --project=validation/sedan_aeb_ccrs validation/sedan_aeb_ccrs/brake_spike.jl
using ModelingToolkit, MultibodyComponents, SedanDemo
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, ADTypes
using OrdinaryDiffEqNonlinearSolve: ShampineCollocationInit
import LinearAlgebra

# ShampineCollocationInit corrects the algebraic variables of a mass-matrix DAE (the loop-form
# suspension); the closed-form sedan is a plain ODE (identity mass matrix) and uses the default.
init_kw(prob) = prob.f.mass_matrix isa LinearAlgebra.UniformScaling ? (;) : (; initializealg = ShampineCollocationInit())
using SciMLBase: successful_retcode
using TOML

const VD = SedanDemo.VehicleComponents
const R_WHEEL = 0.3266
const T_BRAKE = 12.0
const T_END = 18.0
const CORNERS = (:corner_fl, :corner_fr, :corner_rl, :corner_rr)

@parameters b_cmd = 1.0 t_brake = T_BRAKE v_set = 80 / 3.6

# `abs_enabled` is structural, so each setting is its own build.
function build(abs_enabled)
    @named world = MultibodyComponents.World()
    @named sedan = SedanDemo.Sedan(; abs_enabled)
    @named sc = VD.SpeedController(Kp = 0.4)
    @named driver = VD.PathFollowerDriver(npath = 2, path_x = [0.0, 1000.0], path_z = [0.0, 0.0])
    eqs = [
        sc.v_ref ~ v_set,
        sc.v ~ sedan.v,
        sedan.throttle ~ ifelse(t < t_brake, sc.throttle, 0.0),
        sedan.braking ~ ifelse(t < t_brake, sc.braking, b_cmd),
        driver.x ~ sedan.x,
        driver.z ~ sedan.z,
        driver.yaw ~ sedan.yaw,
        sedan.steering ~ driver.steering,
    ]
    @named model = System(eqs, t, [], [b_cmd, t_brake, v_set]; systems = [world, sedan, sc, driver])
    @time "multibody" ssys = multibody(model)
    @time "ODEProblem" prob0 = ODEProblem(ssys, [], (0.0, T_END); optimize = :basic)
    return ssys, prob0
end
# Commit and whether tracked files differ from it, read before any output is written.
const COMMIT = readchomp(`git -C $(@__DIR__) rev-parse --short HEAD`)
const DIRTY = !isempty(readchomp(`git -C $(@__DIR__) status --porcelain --untracked-files=no`))

const BUILDS = Dict(abs_enabled => build(abs_enabled) for abs_enabled in (false, true))

const TRACE_TS = (T_BRAKE - 0.5):0.005:(T_BRAKE + 3.0)
const TRACE_HEADER = "case,t_s,x_m,z_m,yaw_rad,v_mps," *
    join(("w_$(string(c)[end-1:end])_radps" for c in CORNERS), ",") * "," *
    join(("$(a)_$(string(c)[end-1:end])_m" for c in CORNERS for a in ("x", "z")), ",")

# Rows of brake_traces.csv: chassis position, yaw and speed, wheel spin rates, and
# the ground-plane position (x, z) of each wheel center.
function trace_rows(name, sol, S, V)
    cols = Vector{Vector{Float64}}()
    for s in (S.x, S.z, S.yaw, S.v)
        push!(cols, sol(TRACE_TS, idxs = s).u)
    end
    for c in CORNERS
        push!(cols, sol(TRACE_TS, idxs = getproperty(V, c).wheel_rotation.w).u)
    end
    for c in CORNERS, k in (1, 3)
        push!(cols, sol(TRACE_TS, idxs = getproperty(V, c).carrier.r_0[k]).u)
    end
    return [join((name, round(t - T_BRAKE; digits = 3), (round(col[i]; sigdigits = 7) for col in cols)...), ",")
            for (i, t) in enumerate(TRACE_TS)]
end

function run_case(name, b, front, rear, abs_enabled, trace)
    ssys, prob0 = BUILDS[abs_enabled]
    S = ssys.sedan
    V = S.vehicle
    prob = remake(prob0; p = Dict{Any, Any}(ssys.b_cmd => b,
        S.brake_fl.tau_max => front, S.brake_fr.tau_max => front,
        S.brake_rl.tau_max => rear, S.brake_rr.tau_max => rear))
    wall = @elapsed sol = solve(prob, Rodas5P(autodiff = AutoFiniteDiff());
        init_kw(prob)..., tstops = [T_BRAKE])
    rec = Dict{String, Any}("b_cmd" => b, "tau_max_front_Nm" => front, "tau_max_rear_Nm" => rear,
        "abs_enabled" => abs_enabled, "retcode" => string(sol.retcode), "wall_s" => round(wall; digits = 2))
    successful_retcode(sol) || return rec
    ts = T_BRAKE:0.002:T_END
    v, x, z, yaw = (sol(ts, idxs = s).u for s in (S.v, S.x, S.z, S.yaw))
    w = Dict(c => sol(ts, idxs = getproperty(V, c).wheel_rotation.w).u for c in CORNERS)
    v0 = v[1]
    a = [(v[min(i + 5, end)] - v[max(i - 5, 1)]) / (ts[min(i + 5, end)] - ts[max(i - 5, 1)]) for i in eachindex(v)]
    ib = findfirst(<=(0.8v0), v)
    ie = findfirst(<=(0.1v0), v)
    istop = findfirst(<=(0.1), v)
    moving = findall(>(2.0), v)
    ratio(c) = minimum(abs(w[c][i]) * R_WHEEL / v[i] for i in moving)
    rec["v0_kmh"] = round(3.6v0; digits = 2)
    rec["mfdd_mps2"] = ie === nothing ? NaN : round((v[ib]^2 - v[ie]^2) / (2 * (x[ie] - x[ib])); digits = 3)
    rec["peak_decel_mps2"] = round(-minimum(a); digits = 3)
    rec["min_wheel_speed_ratio"] = Dict(string(c) => round(ratio(c); digits = 3) for c in CORNERS)
    rec["max_abs_z_m"] = round(maximum(abs, z .- z[1]); digits = 3)
    rec["yaw_change_deg"] = round(rad2deg(yaw[end] - yaw[1]); digits = 2)
    rec["stop_time_s"] = istop === nothing ? NaN : round(ts[istop] - T_BRAKE; digits = 3)
    rec["stop_distance_m"] = istop === nothing ? NaN : round(x[istop] - x[1]; digits = 2)
    rec["v_end_kmh"] = round(3.6v[end]; digits = 3)
    trace && (rec["trace"] = trace_rows(name, sol, S, V))
    return rec
end

cases = [
    ("noabs_full", 1.0, 2000.0, 2000.0, false, true),
    ("abs_full", 1.0, 2000.0, 2000.0, true, true),
    ("abs_half", 0.5, 2000.0, 2000.0, true, false),
    ("abs_0.35", 0.35, 2000.0, 2000.0, true, false),
]
results = Dict{String, Any}()
trace_lines = [TRACE_HEADER]
for (name, b, front, rear, abs_enabled, trace) in cases
    @time name rec = run_case(name, b, front, rear, abs_enabled, trace)
    haskey(rec, "trace") && append!(trace_lines, pop!(rec, "trace"))
    println(name, " => ", rec)
    results[name] = rec
end
write(joinpath(@__DIR__, "brake_traces.csv"), join(trace_lines, "\n") * "\n")

out = Dict("commit" => COMMIT, "dirty" => DIRTY, "julia" => string(VERSION),
    "t_brake_s" => T_BRAKE, "t_end_s" => T_END, "cases" => results)
open(joinpath(@__DIR__, "brake_spike.toml"), "w") do io
    TOML.print(io, out; sorted = true)
end
