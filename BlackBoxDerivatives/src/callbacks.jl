# The NLP as plain callbacks, for an optimizer that only wants functions. Any AD backend
# (from ADTypes, see BACKENDS) can produce them, through DifferentiationInterface.
# The problem: n unknowns z with bounds lb ≤ z ≤ ub, start z0, objective f(z), m constraints
# con_lb ≤ c(z) ≤ con_ub. Jacobian and Hessian come as a fixed sparsity structure (rows, cols)
# and a values callback; the Hessian is that of the Lagrangian σ⋅f(z) + λ⋅c(z), lower triangle only.

structure(A::SparseMatrixCSC) = findnz(A)[1:2]
structure(A::AbstractMatrix) = (I = vec(CartesianIndices(A)); (getindex.(I, 1), getindex.(I, 2)))
values!(vals, A, (rows, cols)) = (vals .= getindex.(Ref(A), rows, cols); nothing)

function callbacks(backend, dynamics = car_dynamics; with_hessian = true)
    lb, ub, z = bounds_and_start()
    c(z) = defects(dynamics, z)
    m = length(c(z))
    # σλ = [σ; λ] in one argument: DifferentiationInterface's Symbolics backend fails with two.
    lagrangian(z, σλ) = σλ[1] * objective(z) + dot(σλ[2:end], c(z))
    gprep = prepare_gradient(objective, dense_ad(backend), z)
    jprep = prepare_jacobian(c, backend, z)
    J = jacobian(c, jprep, backend, z)
    jac_structure = structure(J)
    grad!(g, z) = (gradient!(objective, g, gprep, dense_ad(backend), z); nothing)
    cons!(out, z) = (out .= c(z); nothing)
    jac!(vals, z) = values!(vals, jacobian!(c, J, jprep, backend, z), jac_structure)
    first_order = (; n = length(z), lb, ub, z0 = z, m, con_lb = zeros(m), con_ub = zeros(m),
        f = objective, grad!, cons!, jac!, jac_structure)
    with_hessian || return first_order
    hprep = prepare_hessian(lagrangian, backend, z, Constant(ones(m + 1)))
    H = hessian(lagrangian, hprep, backend, z, Constant(ones(m + 1)))
    H isa Symmetric && (H = Matrix(H))  # FiniteDiff's Hessian
    rows, cols = structure(H)
    hess_structure = (rows[rows .>= cols], cols[rows .>= cols])
    hess!(vals, z, σ, λ) = values!(vals, hessian!(lagrangian, H, hprep, backend, z, Constant([σ; λ])), hess_structure)
    return (; first_order..., hess!, hess_structure)
end

const BACKENDS = (
    "Symbolics" => AutoSymbolics(),
    "ForwardDiff" => AutoForwardDiff(),
    "Enzyme" => AutoEnzyme(),
    "sparse (auto-detected)" => AutoSparse(AutoForwardDiff();
        sparsity_detector = TracerSparsityDetector(), coloring_algorithm = GreedyColoringAlgorithm()),
)
