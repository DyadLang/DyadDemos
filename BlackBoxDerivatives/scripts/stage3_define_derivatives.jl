# Stage 3: define the derivative methods, then solve with exact Hessians from every backend.
using BlackBoxDerivatives, ADTypes
using BlackBoxDerivatives: BACKENDS, callbacks, counted, solve_ipopt, solve_jump, reference_dynamics

BlackBoxDerivatives.define_derivatives()

reference_callbacks = callbacks(AutoForwardDiff(), reference_dynamics)
reference = solve_ipopt(reference_callbacks)
backend_callbacks = [name => callbacks(backend) for (name, backend) in BACKENDS]
stage3 = [[name => counted(() -> solve_ipopt(cb)) for (name, cb) in backend_callbacks]; "JuMP" => counted(solve_jump)]

println("reference (plain formula): $(reference.iterations) iterations, T = $(reference.T)")
for (name, r) in stage3
    println(rpad(name, 24), r.status, ", ", r.iterations, " iterations, |T - T_ref| = ", abs(r.T - reference.T),
        ", max |z - z_ref| = ", maximum(abs, r.z - reference.z), ", ", r.calls, " black-box calls")
end
