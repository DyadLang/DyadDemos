module CLibraryIntegration
using ModelingToolkit, Symbolics, ForwardDiff
import SynchToolkit
using ModelingToolkit: t_nounits, ImperativeAffect, SymbolicDiscreteCallback
using TireModel_jll: libtiremodel
include("4_stateless.jl")
include("5_stateful.jl")
include("../generated/module.jl")
end
