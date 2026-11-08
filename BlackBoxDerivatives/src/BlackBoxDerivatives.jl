module BlackBoxDerivatives

using ADTypes: AutoEnzyme, AutoForwardDiff, AutoSparse, AutoSymbolics, dense_ad
using DifferentiationInterface: Constant, prepare_gradient, prepare_jacobian, prepare_hessian,
    gradient!, jacobian, jacobian!, hessian, hessian!
import Enzyme, FiniteDiff, ForwardDiff, Ipopt, JuMP  # loading a backend enables it in DifferentiationInterface
using LinearAlgebra: Symmetric, dot
using ModelingToolkit: ModelingToolkit, @named, mtkcompile, unknowns, equations, initial_conditions
using SparseArrays: SparseMatrixCSC, findnz
using SparseConnectivityTracer: TracerSparsityDetector
using SparseMatrixColorings: GreedyColoringAlgorithm
using Symbolics: Symbolics, @register_symbolic, Postwalk, build_function, substitute, iscall, operation, arguments

include("black_box.jl")
include("symbolics.jl")

include("../generated/module.jl")

include("problem.jl")
include("callbacks.jl")
include("ipopt.jl")
include("jump.jl")

"""
Stage 3: give F's derivatives to ForwardDiff, Enzyme and SparseConnectivityTracer.
A real library would just `include` these files; here they load on request so that
stages 1 and 2 can show what happens without them.
"""
define_derivatives() = foreach(f -> include(joinpath(@__DIR__, f)), ("forwarddiff.jl", "enzyme.jl", "sparsity.jl"))

end
