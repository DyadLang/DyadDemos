# Sensitivity of the SedanAcceleration maneuver to the road friction
# coefficient `sedan.mu_road`.
#
# The model is built once; each mu_road value is applied through a cached
# out-of-place setter (`setsym_oop`) and a numeric `remake(prob; u0, p)`, so the
# base problem is never mutated and the bound per-wheel `mu_road` parameters
# follow the top-level one. Speed, distance, and CVT ratio are tabulated against the
# reference trajectory, followed by yaw and lateral drift.
#
# The maneuver is open loop (zero steering, full throttle from t = 1 s), so at
# low friction the rear-axle wheelspin through the open differential can yaw
# the car around; `v` is the longitudinal speed in the chassis frame and drops
# (or turns negative) once the car is sideways or reversed.
#
# Run:  julia --project=scripts scripts/mu_road_sensitivity.jl [mu ...]
# (defaults to mu_road = 0.9 0.6 0.5)
using ModelingToolkit, SedanDemo
using DyadInterface: simplify_model
using OrdinaryDiffEqRosenbrock: Rodas5P
using SciMLBase: remake
using ADTypes, DelimitedFiles, Printf
import SymbolicIndexingInterface as SII

mus = isempty(ARGS) ? [0.9, 0.6, 0.5] : parse.(Float64, ARGS)

ref = readdlm(normpath(joinpath(@__DIR__, "..", "test", "references", "sedan", "accel.csv")), ',', Float64; skipstart = 1)
ref_at(time, col) = ref[argmin(abs.(ref[:, 1] .- time)), col]

@time "instantiate" @named model = SedanDemo.SedanAcceleration()
@time "simplify_model" ssys = simplify_model(model)
@time "ODEProblem" prob = ODEProblem(ssys, [], (0.0, 17.0); optimize = :basic)
S = ssys.sedan
top = S.mu_road
wheels = [getproperty(S.vehicle, c).wheel.mu_road for c in (:corner_fl, :corner_fr, :corner_rl, :corner_rr)]

# cached out-of-place setter: returns fresh (u0, p), never aliases prob.p
setter = SII.setsym_oop(prob, [top])
alg = Rodas5P(autodiff = AutoFiniteDiff())

sols = map(mus) do mu
    u0, p = setter(prob, [mu])
    pmu = remake(prob; u0, p)
    @printf("mu_road = %.2f   wheel mu_road = %s\n", mu, SII.getsym(pmu, wheels)(pmu))
    sol = @time "  solve" solve(pmu, alg)
    println("  retcode = ", sol.retcode)
    sol
end
@assert SII.getsym(prob, top)(prob) == 0.9 "base problem was mutated"

cols(f) = join((@sprintf("%8.2f", f(sol)) for sol in sols), "")
header = join((@sprintf("%8.2f", mu) for mu in mus), "")

println("\nlongitudinal speed v [m/s]        (reference in last column)")
println("   t |", header, " |    ref")
for tt in (2.0, 3.0, 5.0, 8.0, 12.0, 17.0)
    println(@sprintf("%4.0f |", tt), cols(s -> s(tt, idxs = S.v)), @sprintf(" | %6.2f", ref_at(tt, 8)))
end
for (name, f) in (
        ("distance x [m]", (s, tt) -> s(tt, idxs = S.x)),
        ("CVT ratio", (s, tt) -> s(tt, idxs = S.engine.ratio)),
        ("yaw [deg]", (s, tt) -> rad2deg(s(tt, idxs = S.yaw))),
        ("lateral drift z [m]", (s, tt) -> s(tt, idxs = S.z)),
    )
    println("\n", name)
    println("   t |", header)
    for tt in (2.0, 3.0, 5.0, 8.0, 12.0, 17.0)
        println(@sprintf("%4.0f |", tt), cols(s -> f(s, tt)))
    end
end
