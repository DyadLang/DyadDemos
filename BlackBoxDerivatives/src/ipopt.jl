# Ipopt's C interface stands in for an external optimizer that only takes callbacks.

function solve_ipopt(cb)
    hessian = haskey(cb, :hess!)
    (jr, jc) = cb.jac_structure
    (hr, hc) = hessian ? cb.hess_structure : (Int[], Int[])
    eval_jac(z, rows, cols, vals) = vals === nothing ? (rows .= jr; cols .= jc; nothing) : cb.jac!(vals, z)
    eval_h(z, rows, cols, σ, λ, vals) = vals === nothing ? (rows .= hr; cols .= hc; nothing) : cb.hess!(vals, z, σ, λ)
    prob = Ipopt.CreateIpoptProblem(cb.n, cb.lb, cb.ub, cb.m, cb.con_lb, cb.con_ub, length(jr), length(hr),
        cb.f, (z, c) -> cb.cons!(c, z), (z, g) -> cb.grad!(g, z), eval_jac, hessian ? eval_h : nothing)
    iterations = Ref(0)
    Ipopt.SetIntermediateCallback(prob, (_, iter, args...) -> (iterations[] = iter; true))
    Ipopt.AddIpoptIntOption(prob, "print_level", 0)
    Ipopt.AddIpoptNumOption(prob, "tol", 1e-8)
    hessian || Ipopt.AddIpoptStrOption(prob, "hessian_approximation", "limited-memory")
    prob.x .= cb.z0
    status = Ipopt.ApplicationReturnStatus(Ipopt.IpoptSolve(prob))
    return (; status, iterations = iterations[], T = prob.x[end], z = copy(prob.x))
end
