# JuMP ignores all the rule tables above. It wants F as an operator with gradient and Hessian
# callbacks; given F alone, it tries ForwardDiff on F itself and has no Hessian for Ipopt.
∇F!(g, x, y) = (g[1] = Fx(x, y); g[2] = Fy(x, y); nothing)
∇²F!(H, x, y) = (H[1, 1] = Fxx(x, y); H[2, 1] = Fxy(x, y); H[2, 2] = Fyy(x, y); nothing)

# When the model's dynamics meet JuMP variables, F becomes a call to that operator.
F(x::JuMP.AbstractJuMPScalar, y::JuMP.AbstractJuMPScalar) = JuMP.NonlinearExpr(:F, Any[x, y])

function solve_jump(; derivatives = true)
    lb, ub, z0 = bounds_and_start()
    model = JuMP.Model(Ipopt.Optimizer)
    JuMP.set_silent(model)
    JuMP.set_attribute(model, "tol", 1e-8)
    JuMP.@variable(model, lb[i] <= z[i in eachindex(z0)] <= ub[i], start = z0[i])
    JuMP.add_nonlinear_operator(model, 2, (derivatives ? (F, ∇F!, ∇²F!) : (F,))...; name = :F)
    JuMP.@objective(model, Min, objective(z))
    JuMP.@constraint(model, defects(car_dynamics, z) .== 0)
    JuMP.optimize!(model)
    return (; status = JuMP.termination_status(model), iterations = JuMP.barrier_iterations(model),
        T = JuMP.value(z[end]), z = JuMP.value.(z))
end
