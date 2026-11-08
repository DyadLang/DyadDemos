# Stage 1: no derivative information. Finite differences of the black box, two ways.
using BlackBoxDerivatives, ADTypes
using BlackBoxDerivatives: callbacks, counted, solve_ipopt, reference_dynamics

reference = solve_ipopt(callbacks(AutoForwardDiff(), reference_dynamics))  # plain formula, exact Hessian
lbfgs_callbacks = callbacks(AutoFiniteDiff(); with_hessian = false)        # Ipopt approximates the Hessian
fd_hessian_callbacks = callbacks(AutoFiniteDiff())                         # finite-difference Hessian
fd_lbfgs = counted(() -> solve_ipopt(lbfgs_callbacks))
fd_hessian = counted(() -> solve_ipopt(fd_hessian_callbacks))

println("reference (plain formula, exact Hessian): $(reference.iterations) iterations, T = $(reference.T)")
for (name, r) in ("finite differences + L-BFGS" => fd_lbfgs, "finite differences, FD Hessian" => fd_hessian)
    println(rpad(name, 32), r.status, ", ", r.iterations, " iterations, |T - T_ref| = ",
        abs(r.T - reference.T), ", ", r.calls, " black-box calls")
end
