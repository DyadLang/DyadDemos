using Test
include("../scripts/build.jl")
build_tiremodel()
using CLibraryIntegration, ModelingToolkit, Symbolics, ForwardDiff
using OrdinaryDiffEqTsit5, OrdinaryDiffEqRosenbrock
const C = CLibraryIntegration
const t = ModelingToolkit.t_nounits
const Dt = ModelingToolkit.D_nounits
const ROOT = dirname(@__DIR__)

include("../generated/tests.jl")
include("loading.jl")
include("stateless.jl")
include("stateful.jl")
