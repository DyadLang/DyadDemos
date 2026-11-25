# Euro NCAP CCRs prediction for the Sedan with AEB (requirements.md).
#
# Builds `SedanCCRs` once and runs every cell of the protocol grid (test speed ×
# impact location). On each solution it locates T0 (TTC 4 s), TAEB and the
# impact, checks the test conduct, and colours the cell; the grid is then scored.
# Writes ccrs_cells.csv, ccrs_summary.toml, ccrs_traces.csv (100 Hz time histories
# of the TRACE_CASES) and, for a scorable grid, ccrs_grid.svg.
# With `--gate` the process exits nonzero unless every cell's conduct is valid
# and REQ-AEB-1 holds. With `--sensitivity` it also reruns the grid for later AEB
# trigger thresholds and writes ccrs_sensitivity.csv and ccrs_sensitivity.toml.
#
#   julia --project=validation/sedan_aeb_ccrs validation/sedan_aeb_ccrs/ccrs_sweep.jl [--gate] [--sensitivity]
using ModelingToolkit, MultibodyComponents, SedanDemo
using OrdinaryDiffEq, ADTypes
using OrdinaryDiffEqNonlinearSolve: ShampineCollocationInit
import LinearAlgebra

# ShampineCollocationInit corrects the algebraic variables of a mass-matrix DAE (the loop-form
# suspension); the closed-form sedan is a plain ODE (identity mass matrix) and uses the default.
init_kw(prob) = prob.f.mass_matrix isa LinearAlgebra.UniformScaling ? (;) : (; initializealg = ShampineCollocationInit())
using SciMLBase: successful_retcode
using Symbolics, TOML, Printf
include(joinpath(@__DIR__, "ccrs_analysis.jl"))
using .CCRsAnalysis

const PROTOCOL = load_protocol()
const DT = 1 / PROTOCOL["conduct"]["sample_rate_min_hz"]
const T_AFTER = 12.0    # simulated time beyond t_lead
# Trigger thresholds a_on of the sensitivity study; a_full = a_on + 3 m/s^2 in each.
const A_ON_STUDY = (7.0, 8.0, 9.0, 10.0)
# Cells recorded as time histories: name => (test speed, impact location, a_on).
const TRACE_CASES = ("nominal_50kmh" => (50, 50, 5.0), "late_a_on_9_50kmh" => (50, 50, 9.0))
const SIGNALS = (:x_front, :z_front, :v, :throttle, :braking, :z_front_axle, :a_req, :gap, :yaw)

function build()
    @named model = SedanDemo.SedanCCRs()
    ssys = multibody(model)
    prob = ODEProblem(ssys, [], (0.0, 1.0); optimize = :basic)
    S, V = ssys.sedan, ssys.sedan.vehicle
    syms = [ssys.sensor.x_front, ssys.sensor.z_front, S.v, S.throttle, S.braking,
        (V.corner_fl.carrier.r_0[3] + V.corner_fr.carrier.r_0[3]) / 2, ssys.aeb.a_req, ssys.sensor.gap,
        ssys.sensor.yaw]
    derived = derived_parameters(ssys, (ssys.v_test_kmh, ssys.impact_pct))
    return ssys, prob, ModelingToolkit.getu(ssys, syms), derived
end

# Tunable parameters whose value is an expression of the cell inputs, directly or
# through the scenario's bindings (which MTK evaluates on read), in dependency order.
function derived_parameters(ssys, inputs)
    binds = Dict(ModelingToolkit.bindings(ssys))
    pars = Set(ModelingToolkit.unwrap.(ModelingToolkit.parameters(ssys)))
    exprs = merge(binds, Dict(ModelingToolkit.initial_conditions(ssys)))
    reached = Set(ModelingToolkit.unwrap.(inputs))
    derived = Pair[]
    while true
        next = [k => v for (k, v) in exprs if (k in pars || haskey(binds, k)) && !(k in reached) &&
                any(in(reached), Symbolics.get_variables(v))]
        isempty(next) && return derived
        append!(derived, filter(kv -> !haskey(binds, first(kv)), next))
        union!(reached, first.(next))
    end
end

# A copy of `prob0` with `given` parameter values and every derived parameter
# re-evaluated to a fixed point. `remake(prob; p)` evaluates the subcomponent
# parameters before the bindings they read are updated, so one call leaves them
# one dependency level stale; it also rebuilds the initialization problem (about
# 20 s per call). Neither happens here.
function with_parameters(prob0, derived, given)
    prob = remake(prob0)
    for (k, v) in given
        prob.ps[k] = v
    end
    for _ in 1:10
        changed = false
        for (k, ex) in derived
            val = Symbolics.value(Symbolics.substitute(ex,
                Dict(v => prob.ps[v] for v in Symbolics.get_variables(ex))))
            val isa Real || error("derived parameter $k did not evaluate to a number: $val")
            if prob.ps[k] != val
                prob.ps[k] = val
                changed = true
            end
        end
        changed || return prob
    end
    error("derived parameters did not reach a fixed point")
end

# Sample the named signals at times `ts` from the dense solution.
function sample(sol, getter, ts)
    p = ModelingToolkit.parameter_values(sol)
    rows = [getter(ModelingToolkit.ProblemState(; u = sol(t), p, t)) for t in ts]
    return NamedTuple{SIGNALS}(Tuple([row[k] for row in rows] for k in eachindex(SIGNALS)))
end

# First instant in (ta, tb] where the front profile reaches `x_target`, by bisection
# on the dense solution; `reach` maps a sample to the profile's x (`profile_reach`).
# Returns the time and the speed there.
function dense_impact(sol, getter, ta, tb, x_target, reach)
    at(t) = sample(sol, getter, [t])
    reach(at(ta)) < x_target <= reach(at(tb)) ||
        error("impact interval [$ta, $tb] does not bracket the target plane")
    for _ in 1:60
        tm = (ta + tb) / 2
        reach(at(tm)) < x_target ? (ta = tm) : (tb = tm)
    end
    return tb, at(tb).v[1]
end

function run_cell(ssys, prob0, getter, derived, v_kmh, p_pct, cell_range; extra = (), solver_kw...)
    prob = with_parameters(prob0, derived, (ssys.v_test_kmh => v_kmh, ssys.impact_pct => p_pct, extra...))
    prob = remake(prob; tspan = (0.0, prob.ps[ssys.t_lead] + T_AFTER))
    v_test, x_target, z_target = prob.ps[ssys.v_test], prob.ps[ssys.x_target], prob.ps[ssys.z_target]
    wall = @elapsed sol = solve(prob, Rodas5P(autodiff = AutoFiniteDiff());
        init_kw(prob)..., solver_kw...)
    successful_retcode(sol) || error("$v_kmh km/h, $p_pct %: solver returned $(sol.retcode)")
    # The solved problem must carry the cell's values down to the subcomponents.
    for (sym, val) in ((ssys.v_ref.k, v_test), (ssys.robot.v_test, v_test), (ssys.target.x, x_target),
            (ssys.target.z, z_target), (ssys.v_test, v_kmh / 3.6))
        isapprox(sol.ps[sym], val; rtol = 1e-12, atol = 1e-12) ||
            error("$v_kmh km/h, $p_pct %: $sym = $(sol.ps[sym]), expected $val")
    end
    ts = collect(range(sol.t[1], sol.t[end]; step = DT))
    r = sample(sol, getter, ts)
    # The record ends at the last sample before the vehicle comes to rest after its
    # top speed (at rest, the speed can dip slightly below zero).
    stop = findnext(<=(0.0), r.v, argmax(r.v))
    iend = isnothing(stop) ? lastindex(ts) : stop - 1
    t, rr = ts[1:iend], map(s -> s[1:iend], r)
    meas = PROTOCOL["measurement"]
    w_vut, w_target = prob.ps[ssys.w_vut], prob.ps[ssys.target.w]
    t0 = test_start(t, rr.x_front, rr.v; x_target, ttc_s = PROTOCOL["conduct"]["ttc_start_s"])
    inset = meas["front_profile_inset_m"]
    hit = impact(t, rr.x_front, rr.z_front, rr.yaw, rr.v;
        x_target, z_target, w_vut, w_target, inset)
    v_impact_kmh, t_impact = 0.0, nothing
    if hit.contact
        i = findlast(<=(hit.t_impact), t)
        reach(s) = profile_reach(s.x_front[1], s.z_front[1], s.yaw[1];
            z_target, halfwidth = w_vut / 2 - inset, w_target).x
        t_impact, v_hit = dense_impact(sol, getter, t[i], t[i + 1], x_target, reach)
        v_impact_kmh = 3.6v_hit
    end
    i0 = findfirst(>=(t0), t)
    tb = taeb(t[i0:end], rr.v[i0:end]; protocol = PROTOCOL)
    t_check = something(tb, t_impact, t[end])
    # Test conduct is judged from T0 on; the record before it is the launch.
    w = (i0 - 1):lastindex(t)
    conduct = conduct_checks(t[w], rr.v[w], rr.z_front_axle[w], rr.throttle[w];
        v_test, t0, t_end_check = t_check, protocol = PROTOCOL)
    colour_name = colour(v_kmh, v_impact_kmh, hit.contact; protocol = PROTOCOL)
    gap_min = minimum(rr.gap)
    notes = hit.contact ? "contact" : @sprintf("stopped %.2f m short", gap_min)
    cell = (v_test_kmh = Float64(v_kmh), impact_location_pct = Float64(p_pct), range = cell_range,
        contact = hit.contact, v_impact_kmh, t0_s = t0, taeb_s = tb, colour = colour_name,
        valid = conduct.valid, notes)
    detail = Dict{String, Any}("wall_s" => round(wall; digits = 2),
        "t0_s" => round(t0; digits = 3), "taeb_s" => isnothing(tb) ? "none" : round(tb; digits = 3),
        "ttc_at_taeb_s" => isnothing(tb) ? "none" :
            round((x_target - rr.x_front[findfirst(>=(tb), t)]) / rr.v[findfirst(>=(tb), t)]; digits = 3),
        "v_impact_kmh" => round(v_impact_kmh; digits = 3), "stop_gap_m" => round(gap_min; digits = 3),
        "speed_dev_worst_kmh" => round(conduct.speed.worst_kmh; digits = 3),
        "lateral_dev_worst_m" => round(conduct.lateral.worst_m; digits = 4),
        "throttle_after_release" => conduct.throttle.maximum_after_release,
        "peak_braking" => round(maximum(rr.braking); digits = 3),
        "peak_a_req_mps2" => round(maximum(rr.a_req[t .<= something(t_impact, t[end])]); digits = 2),
        "valid" => conduct.valid)
    return cell, detail, (; sol, t, r = rr, t0, tb, t_impact, x_target, z_target)
end

# Every cell of the protocol grid; `extra` overrides model parameters in all cells.
function run_grid(built; extra = ())
    ssys, prob0, getter, derived = built
    m = PROTOCOL["matrix"]
    cells, details = [], Dict{String, Any}()
    for v in m["vut_speed_kmh"], (cell_range, key) in ((:standard, "impact_location_standard_pct"),
            (:extended, "impact_location_extended_pct")), p in m[key]
        cell, detail, _ = run_cell(ssys, prob0, getter, derived, v, p, cell_range; extra)
        push!(cells, cell)
        details[@sprintf("%02d_kmh_%+04d_pct", v, p)] = detail
        @printf("%2d km/h %4d %%  %-6s  Vimpact %6.2f km/h  %s  valid=%s  (%.1f s)\n", v, p,
            cell.colour, cell.v_impact_kmh, cell.notes, cell.valid, detail["wall_s"])
    end
    return cells, details
end

# 100 Hz time histories from T0 - 1 s to the end of each record, with the cell's
# T0, TAEB and impact time on every row.
function write_traces(built)
    ssys, prob0, getter, derived = built
    open(joinpath(@__DIR__, "ccrs_traces.csv"), "w") do io
        println(io, "case,t_s,t0_s,taeb_s,t_impact_s,x_target_m,z_target_m,", join(SIGNALS, ","))
        for (name, (v, p, a_on)) in TRACE_CASES
            _, _, run = run_cell(ssys, prob0, getter, derived, v, p, :standard;
                extra = (ssys.a_on => a_on,))
            fmt(x) = isnothing(x) ? "" : string(round(x; digits = 4))
            for i in eachindex(run.t)
                run.t[i] >= run.t0 - 1 || continue
                println(io, join((name, round(run.t[i]; digits = 3), fmt(run.t0), fmt(run.tb), fmt(run.t_impact),
                    round(run.x_target; digits = 4), round(run.z_target; digits = 4),
                    (round(run.r[k][i]; sigdigits = 7) for k in SIGNALS)...), ","))
            end
        end
    end
end

# Commit and whether tracked files differ from it; read before any output is written.
git_state() = (commit = readchomp(`git -C $(@__DIR__) rev-parse --short HEAD`),
    dirty = !isempty(readchomp(`git -C $(@__DIR__) status --porcelain --untracked-files=no`)))

# Grids for each trigger threshold in `results` (a_on => cells), written as one CSV
# and a TOML of points per threshold. Labelled a design study: no criterion.
function write_sensitivity(results, git; a_full_offset = 3.0)
    open(joinpath(@__DIR__, "ccrs_sensitivity.csv"), "w") do io
        println(io, "a_on_mps2,a_full_mps2,v_test_kmh,impact_location_pct,range,contact,v_impact_kmh,colour,valid")
        for a_on in sort(collect(keys(results))), c in results[a_on]
            println(io, join((a_on, a_on + a_full_offset, c.v_test_kmh, c.impact_location_pct, c.range,
                c.contact, round(c.v_impact_kmh; digits = 3), c.colour, c.valid), ","))
        end
    end
    record = Dict{String, Any}("commit" => git.commit, "dirty" => git.dirty,
        "label" => "design study, no criterion", "a_full_offset_mps2" => a_full_offset)
    record["thresholds"] = Dict{String, Any}()
    for (a_on, cells) in results
        entry = Dict{String, Any}("a_on_mps2" => a_on, "all_conduct_valid" => all(c -> c.valid, cells))
        contact = [c.v_test_kmh for c in cells if c.contact]
        entry["first_contact_kmh"] = isempty(contact) ? "none" : minimum(contact)
        if entry["all_conduct_valid"]
            res = score(cells; protocol = PROTOCOL)
            merge!(entry, Dict("standard_points" => res.standard_points, "req_aeb1" => res.req_aeb1,
                "extended_points" => res.extended_points, "total_points" => res.total_points))
        end
        record["thresholds"][@sprintf("a_on_%.1f", a_on)] = entry
    end
    open(io -> TOML.print(io, record; sorted = true), joinpath(@__DIR__, "ccrs_sensitivity.toml"), "w")
end

function main(args; built = build())
    gate = "--gate" in args
    git = git_state()
    cells, details = run_grid(built)
    write_cells_csv(joinpath(@__DIR__, "ccrs_cells.csv"), cells; protocol = PROTOCOL)
    all_valid = all(c -> c.valid, cells)
    result = all_valid ? score(cells; protocol = PROTOCOL) : nothing
    all_valid && grid_svg(joinpath(@__DIR__, "ccrs_grid.svg"), cells; protocol = PROTOCOL)
    write_traces(built)
    summary = Dict{String, Any}("commit" => git.commit, "dirty" => git.dirty,
        "julia" => string(VERSION), "all_conduct_valid" => all_valid, "cells" => details)
    if result !== nothing
        summary["score"] = Dict(string(k) => v for (k, v) in pairs(result))
    end
    open(io -> TOML.print(io, summary; sorted = true), joinpath(@__DIR__, "ccrs_summary.toml"), "w")
    println(result === nothing ? "grid not scorable: invalid test conduct" : result)
    if "--sensitivity" in args
        ssys = first(built)
        study = Dict(5.0 => cells)
        for a_on in A_ON_STUDY
            study[a_on] = first(run_grid(built; extra = (ssys.a_on => a_on,)))
        end
        write_sensitivity(study, git)
    end
    gate && !(all_valid && result.req_aeb1) && exit(1)
    return cells, details, result
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
