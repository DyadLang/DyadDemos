# Dyad 3.5 emits a UnionAll annotation for the parametric DyadTimeseries
# value in generated analysis systems. SymbolicUtils requires a concrete
# DataType there. Run this after `dyad compile .` until the compiler emits
# the value's concrete type itself. The public analysis API is unchanged.
const GENERATED = joinpath(@__DIR__, "..", "generated")
for (dir, _, files) in walkdir(GENERATED), file in files
    endswith(file, "_definition.jl") || continue
    path = joinpath(dir, file)
    source = read(path, String)
    fixed = replace(source,
        "@parameters (data::DyadData.DyadTimeseries)" =>
        "@parameters (data::typeof(__local__data))")
    fixed = replace(fixed, "\n  \n    @named model" => "\n\n    @named model")
    fixed == source || write(path, fixed)
end
