# Dyad v3.5.0-rc2 (a24a2240667872d432a3b86c4db1240d77150e35) emits a
# UnionAll annotation for the parametric DyadTimeseries
# value in generated analysis systems. SymbolicUtils requires a concrete
# DataType there. Run this after `dyad compile .` until the compiler emits
# the value's concrete type itself. Every Dyad Studio recompile (including on
# save) also requires rerunning this script before loading the project.
# Upstream: https://github.com/JuliaComputing/dyad-lang/issues/1958
# The public analysis API is unchanged; preserve all compiler whitespace.
const GENERATED = joinpath(@__DIR__, "..", "generated")
for (dir, _, files) in walkdir(GENERATED), file in files
    endswith(file, "_definition.jl") || continue
    path = joinpath(dir, file)
    source = read(path, String)
    fixed = replace(source,
        "@parameters (data::DyadData.DyadTimeseries)" =>
        "@parameters (data::typeof(__local__data))")
    fixed == source || write(path, fixed)
end
