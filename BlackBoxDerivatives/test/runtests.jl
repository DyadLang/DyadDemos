using BlackBoxDerivatives, Test
import DifferentiationInterface as DI, Enzyme, ForwardDiff
using ADTypes: dense_ad
using LinearAlgebra: Symmetric
using BlackBoxDerivatives: BACKENDS, F, tire, bounds_and_start, ∇F!, ∇²F!

# No Dyad test cases are declared, so generated/tests.jl (which needs CSV, DataFrames, Plots) is not run.

solved(r) = string(r.status) in ("Solve_Succeeded", "LOCALLY_SOLVED")

@testset "1. No derivative information" begin
    include("../scripts/stage1_no_derivatives.jl")
    @test solved(reference)
    @test reference.T ≈ 6.501371279257 atol = 1e-9  # from an earlier, independent implementation
    @testset "$name" for (name, r) in ("L-BFGS" => fd_lbfgs, "FD Hessian" => fd_hessian)
        @test solved(r)
        @test r.T ≈ reference.T atol = 1e-9
    end
    @test fd_lbfgs.iterations > 2reference.iterations
    @test fd_hessian.calls > 50fd_lbfgs.calls
end

@testset "2. AD without derivative definitions" begin
    include("../scripts/stage2_ask_for_ad.jl")
    expected = Dict("Symbolics" => "no error", "ForwardDiff" => "MethodError: no method matching F(::ForwardDiff.Dual",
        "Enzyme" => "EnzymeNoDerivativeError", "sparse (auto-detected)" => "no method matching F(::SparseConnectivityTracer",
        "JuMP, F only" => "Unable to register the function :F")
    @testset "$name" for (name, msg) in stage2_errors
        @test occursin(expected[name], msg)
    end
    @test enzyme_forward == 0  # silently wrong
    # The wrapper black_box.jl warns against: strip the Duals, call F, get zero.
    @test ForwardDiff.gradient(z -> F(ForwardDiff.value.(z)...), [0.2, 0.9]) == [0, 0]
end

# Dense Jacobian and Lagrangian Hessian from a callback set, for comparison.
function dense_derivatives(cb, z, σ, λ)
    fill_dense(values!, (rows, cols), dims) = (v = zeros(length(rows)); values!(v);
        A = zeros(dims); A[CartesianIndex.(rows, cols)] .= v; A)
    g = zeros(length(z)); cb.grad!(g, z)
    return g, fill_dense(v -> cb.jac!(v, z), cb.jac_structure, (cb.m, length(z))),
        fill_dense(v -> cb.hess!(v, z, σ, λ), cb.hess_structure, (length(z), length(z)))
end

# Tolerances: relative 1e-10 for every derivative; observed errors are at rounding level.
@testset "3. Exact derivatives" begin
    include("../scripts/stage3_define_derivatives.jl")
    points = ([0.2, 0.9], [-0.5, 0.75], [0.03, 1.0])
    f(z) = F(z[1], z[2])
    ref(z) = tire(z[1], z[2])
    @testset "F through $name" for (name, backend) in BACKENDS, p in points
        @test DI.gradient(f, dense_ad(backend), p) ≈ ForwardDiff.gradient(ref, p) rtol = 1e-10
        @test Matrix(DI.hessian(f, backend, p)) ≈ ForwardDiff.hessian(ref, p) rtol = 1e-10
    end
    @testset "one Dual argument, one Float64" for p in points
        @test ForwardDiff.derivative(a -> F(a, p[2]), p[1]) ≈ ForwardDiff.gradient(ref, p)[1] rtol = 1e-10
        @test ForwardDiff.derivative(b -> F(p[1], b), p[2]) ≈ ForwardDiff.gradient(ref, p)[2] rtol = 1e-10
        @test only(Enzyme.autodiff(Enzyme.Forward, F, Enzyme.Duplicated(p[1], 1.0), Enzyme.Const(p[2]))) ≈
              ForwardDiff.gradient(ref, p)[1] rtol = 1e-10
    end
    @testset "F through JuMP callbacks" for p in points
        g, H = zeros(2), zeros(2, 2)
        ∇F!(g, p...), ∇²F!(H, p...)
        @test g ≈ ForwardDiff.gradient(ref, p) rtol = 1e-10
        @test Symmetric(H, :L) ≈ ForwardDiff.hessian(ref, p) rtol = 1e-10  # JuMP reads the lower triangle
    end
    z0 = bounds_and_start()[3]
    σ, λ = 0.7, collect(range(-1, 1; length = reference_callbacks.m))
    @testset "NLP callbacks from $name" for (name, cb) in backend_callbacks, z in (z0, reference.z)
        for (A, B) in zip(dense_derivatives(cb, z, σ, λ), dense_derivatives(reference_callbacks, z, σ, λ))
            @test A ≈ B rtol = 1e-10
        end
    end
    @testset "solve with exact Hessians: $name" for (name, r) in stage3
        @test solved(r)
        @test r.iterations <= reference.iterations + 2
        @test r.T ≈ reference.T atol = 1e-9
    end
end
