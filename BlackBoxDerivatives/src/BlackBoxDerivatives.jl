module BlackBoxDerivatives

using ADTypes: AutoEnzyme, AutoForwardDiff, AutoSparse, AutoSymbolics, dense_ad
using DifferentiationInterface: Constant, prepare_gradient, prepare_jacobian, prepare_hessian,
    gradient!, jacobian, jacobian!, hessian, hessian!
import Enzyme, FiniteDiff, ForwardDiff  # loading an AD package enables it in DifferentiationInterface
import Ipopt, JuMP
using LinearAlgebra: Symmetric, dot
using ModelingToolkit: ModelingToolkit, mtkcompile, unknowns, equations, initial_conditions
using SparseArrays: SparseMatrixCSC, findnz
using SparseConnectivityTracer: TracerSparsityDetector
using SparseMatrixColorings: GreedyColoringAlgorithm
using Symbolics: Symbolics, @register_symbolic, build_function, substitute

include("black_box.jl")
# The Dyad model calls F, so Symbolics must know it as an opaque function. Always loaded.
@register_symbolic F(x, y)
@register_symbolic Fx(x, y)
@register_symbolic Fy(x, y)
@register_symbolic Fxx(x, y)
@register_symbolic Fxy(x, y)
@register_symbolic Fyy(x, y)

include("../generated/module.jl")

include("problem.jl")
include("callbacks.jl")
include("ipopt.jl")
include("jump.jl")

"""
Stage 3: give F's derivatives to Symbolics, ForwardDiff, Enzyme and SparseConnectivityTracer.
A real library would just `include` these files; here they load on request so that
stages 1 and 2 can show what happens without them.
"""
define_derivatives() = foreach(f -> include(joinpath(@__DIR__, f)), ("symbolics.jl", "forwarddiff.jl", "enzyme.jl", "sparsity.jl"))

end
