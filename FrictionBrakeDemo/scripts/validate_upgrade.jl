# Run from this project: julia --project=. scripts/validate_upgrade.jl [output-directory]
using DyadInterface, ModelingToolkit
output_dir = isempty(ARGS) ? mktempdir() : only(ARGS)
using FrictionBrakeDemo
mod = FrictionBrakeDemo
mkpath(output_dir)
analyses = sort(filter(n -> endswith(string(n), "Spec") &&
    isdefined(mod, n) && getfield(mod, n) isa DataType &&
    getfield(mod, n) <: DyadInterface.AbstractAnalysisSpec &&
    !isabstracttype(getfield(mod, n)), names(mod)))
isempty(analyses) && error("No concrete analyses were found")
open(joinpath(output_dir, "analyses.tsv"), "w") do io
    println(io, "analysis\tstatus\tt_start\tt_stop\tpoints\tstate_count\tmax_abs_state\terror")
    for name in analyses
        println("START ", name); flush(stdout)
        try
            spec = getfield(mod, name)(; progress=false)
            result = DyadInterface.run_analysis(spec)
            sol = DyadInterface.rebuild_sol(result)
            model = DyadInterface.get_model(result)
            @assert ModelingToolkit.SciMLBase.successful_retcode(sol)
            @assert sol.t[end] ≈ spec.stop
            grid = range(sol.t[1], sol.t[end]; length=201)
            states = ModelingToolkit.unknowns(model)
            data = reduce(hcat, [Float64.(sol(t; idxs=states)) for t in grid])'
            @assert all(isfinite, data)
            stem = replace(string(name), r"(__)?Spec$" => "")
            open(joinpath(output_dir, stem * ".tsv"), "w") do out
                println(out, join(vcat(["t"], string.(states)), '\t'))
                for (t, row) in zip(grid, eachrow(data))
                    println(out, join(vcat(t, collect(row)), '\t'))
                end
            end
            println(io, join((stem,"PASS",sol.t[1],sol.t[end],length(sol.t),length(states),maximum(abs,data),""), '\t'))
            println("PASS ", stem); flush(stdout)
        catch err
            msg = replace(sprint(showerror,err,catch_backtrace()), '\n'=>" ", '\t'=>" ")
            println(io, string(name), "\tFAIL\t\t\t\t\t\t", msg)
            showerror(stdout,err,catch_backtrace()); println(); flush(stdout)
        end
        flush(io)
    end
end

println("Validation results: ", abspath(output_dir))

occursin("\tFAIL\t", read(joinpath(output_dir, "analyses.tsv"), String)) && error("One or more analyses failed; see analyses.tsv")
