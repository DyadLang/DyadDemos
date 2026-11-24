# Parameter sweep of the SedanAcceleration maneuver over road friction `sedan.mu_road` and
# final drive ratio `sedan.final_ratio`, with DyadParameterAnalysis on CPU threads.
#
# Each grid point is a full 17 s full-throttle launch; the report lists, per road friction, the
# final drive ratio that covers the most distance, and how many ratios make the car spin out.
#
# Run:  julia -t 8 --project=scripts scripts/parameter_sweep.jl
# Environment: N (grid points per parameter, default 8), TOL (abstol = reltol, default 1e-7),
# STOP (default 17.0). The reported time includes compiling the solver on the first run.
using ModelingToolkit, SedanDemo
using DyadParameterAnalysis
using OrdinaryDiffEqBDF: FBDF
using ADTypes: AutoFiniteDiff
using Printf

n = parse(Int, get(ENV, "N", "8"))
tol = parse(Float64, get(ENV, "TOL", "1e-7"))
stop = parse(Float64, get(ENV, "STOP", "17.0"))

@named model = SedanDemo.SedanAcceleration(render = false)
spec = ParameterSweepAnalysisSpec(; model, stop, saveat = 0.1, abstol = tol, reltol = tol,
    alg = ODEAlg.NativeAlgorithm(FBDF(autodiff = AutoFiniteDiff()), @__MODULE__),
    ensemble_mode = EnsembleMode.Threads(),
    sweep_parameters = ["sedan.mu_road", "sedan.final_ratio"],
    sweep_lower = [0.5, 0.16], sweep_upper = [1.0, 0.28], sweep_samples = [n, n],
    outputs = ["sedan.v", "sedan.x", "sedan.yaw"])
println(Threads.nthreads(), " threads: ", n, " x ", n, " grid, tol ", tol, ", ", stop, " s")

@time "setup" setup = setup_analysis(spec)
wall = @elapsed sol = run_analysis(setup)

# the output / parameter named `x` (MTK writes the hierarchy separator as ₊)
byname(names, x) = only(filter(s -> replace(string(s), "₊" => ".") == x, names))
imu = findfirst(==(byname(sol.parameter_names, "sedan.mu_road")), sol.parameter_names)
ifr = findfirst(==(byname(sol.parameter_names, "sedan.final_ratio")), sol.parameter_names)
v, x, yaw = (byname(sol.output_names, "sedan.$o") for o in ("v", "x", "yaw"))
ok = findall(==(:Success), sol.retcodes)
@printf("\n%d trajectories in %.1f s, %d failed\n", length(sol), wall, length(sol) - length(ok))
println("\nmu_road | best final_ratio | x(end) [m] | v(end) [m/s] | spun out (|yaw| > 30 deg)")
for mu in sort(unique(sol.points[:, imu]))
    idx = filter(i -> sol.points[i, imu] == mu, ok)
    isempty(idx) && continue
    best = idx[argmax([sol[i][x][end] for i in idx])]
    spun = count(i -> maximum(abs, rad2deg.(sol[i][yaw])) > 30, idx)
    @printf("%7.3f | %16.3f | %10.1f | %12.2f | %d / %d\n", mu, sol.points[best, ifr],
        sol[best][x][end], sol[best][v][end], spun, length(idx))
end
