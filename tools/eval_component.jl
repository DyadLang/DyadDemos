# eval_component.jl — CLI wrapper around eval_component_run.jl
# usage: julia eval_component.jl LIBDIR Component inputs.csv outputs.csv
using Pkg
Pkg.activate(ARGS[1])
include(joinpath(@__DIR__, "eval_component_run.jl"))
run_eval(ARGS[2], ARGS[3], ARGS[4])
