# Stage 2: ask for AD without defining any derivatives. Each backend stops at the black box,
# or, worse, runs and returns zeros.
using BlackBoxDerivatives, ADTypes, Enzyme, ForwardDiff, Symbolics
using BlackBoxDerivatives: BACKENDS, F, callbacks, solve_jump, tire
using DifferentiationInterface: gradient

one_line(err) = first(replace(sprint(showerror, err), r"\s+" => " "), 160)
ad_backends = filter(!=("Symbolics") ∘ first, BACKENDS)  # Symbolics: see below
stage2_errors = map([ad_backends...; "JuMP, F only" => nothing]) do (name, backend)
    try
        backend === nothing ? solve_jump(derivatives = false) : callbacks(backend)
        name => "no error"
    catch err
        name => one_line(err)
    end
end
foreach(((name, msg),) -> println(rpad(name, 24), msg), stage2_errors)

# Worse than an error: Symbolics, with F registered but no derivative rules, and Enzyme's
# forward mode, which runs through the bytes, both return zero.
true_gradient = ForwardDiff.gradient(z -> tire(z[1], z[2]), [0.2, 0.9])
symbolics_gradient = Symbolics.value.(gradient(z -> F(z[1], z[2]), AutoSymbolics(), [0.2, 0.9]))
enzyme_forward = only(Enzyme.autodiff(Forward, F, Duplicated(0.2, 1.0), Const(0.9)))
println("Symbolics, ∇F(0.2, 0.9): ", symbolics_gradient, " (true value ", true_gradient, ")")
println("Enzyme forward mode, ∂F/∂x at (0.2, 0.9): ", enzyme_forward, " (true value ", true_gradient[1], ")")
