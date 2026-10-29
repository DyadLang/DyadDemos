# Run from the project with: julia --project=. test/validate_upgrade.jl results.toml
# The output stores sampled trajectories for old/new comparisons, not snapshot refs.
using TOML
using ModelingToolkit
using DyadInterface
using Test

project_root = dirname(@__DIR__)
project_name = TOML.parsefile(joinpath(project_root, "Project.toml"))["name"]
project_module = Base.require(Main, Symbol(project_name))
output_path = isempty(ARGS) ? joinpath(project_root, "upgrade-results.toml") : ARGS[1]
selected = length(ARGS) > 1 ? Set(ARGS[2:end]) : nothing
analysis_names = String[]
for (root, _, files) in walkdir(joinpath(project_root, "dyad")), file in files
    endswith(file, ".dyad") || continue
    for line in eachline(joinpath(root, file))
        m = match(r"^analysis\s+(\w+)", line)
        isnothing(m) || push!(analysis_names, m.captures[1])
    end
end
sort!(analysis_names)
results = Dict{String, Any}("project" => project_name, "julia" => string(VERSION),
    "analyses" => Dict{String, Any}())
for name in analysis_names
    !isnothing(selected) && !(name in selected) && continue
    println("START ", name); flush(stdout)
    entry = Dict{String, Any}()
    elapsed = @elapsed try
        result = getfield(project_module, Symbol(name))()
        sol = DyadInterface.rebuild_sol(result)
        @test ModelingToolkit.SciMLBase.successful_retcode(sol)
        times = collect(range(first(sol.t), last(sol.t); length=51))
        samples = Dict{String, Any}()
        variables = unique(vcat(ModelingToolkit.unknowns(result.sys),
            ModelingToolkit.outputs(result.sys)))
        # Include observable outputs in small models, including algebraic and clocked cases.
        # Large grids retain their states and declared outputs to limit result size.
        if length(variables) <= 20
            variables = unique(vcat(variables, [eq.lhs for eq in ModelingToolkit.observed(result.sys)]))
        end
        for variable in variables
            trajectory = Float64.(vec(Array(sol(times; idxs=variable))))
            @test all(isfinite, trajectory)
            samples[string(variable)] = trajectory
        end
        entry["status"] = "pass"
        entry["retcode"] = string(sol.retcode)
        entry["times"] = times
        entry["samples"] = samples
        entry["state_count"] = length(samples)
        entry["max_abs_sample"] = isempty(samples) ? 0.0 : maximum(maximum(abs, v) for v in values(samples))
        entry["final_max_abs"] = isempty(samples) ? 0.0 : maximum(abs(last(v)) for v in values(samples))
    catch err
        entry["status"] = "fail"
        entry["error"] = sprint(showerror, err, catch_backtrace())
        showerror(stderr, err, catch_backtrace()); println(stderr)
    end
    entry["seconds"] = elapsed
    results["analyses"][name] = entry
    open(output_path, "w") do io
        TOML.print(io, results)
    end
    println("RESULT ", name, " ", entry["status"], " ", elapsed, " seconds"); flush(stdout)
    GC.gc()
end
isempty(analysis_names) && open(io -> TOML.print(io, results), output_path, "w")
any(x -> x["status"] == "fail", values(results["analyses"])) && exit(1)
