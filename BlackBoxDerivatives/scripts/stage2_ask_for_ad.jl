# Stage 2: ask for AD without defining any derivatives. Each backend stops at the black box,
# except Symbolics: its rules (symbolics.jl) load with the Dyad model.
using BlackBoxDerivatives, Enzyme, ForwardDiff
using BlackBoxDerivatives: BACKENDS, F, callbacks, solve_jump, tire

one_line(err) = first(replace(sprint(showerror, err), r"\s+" => " "), 160)
stage2_errors = map([BACKENDS...; "JuMP, F only" => nothing]) do (name, backend)
    try
        backend === nothing ? solve_jump(derivatives = false) : callbacks(backend)
        name => "no error"
    catch err
        name => one_line(err)
    end
end
foreach(((name, msg),) -> println(rpad(name, 24), msg), stage2_errors)

# Worse than an error: Enzyme's forward mode runs through the bytes and returns zero.
enzyme_forward = only(Enzyme.autodiff(Forward, F, Duplicated(0.2, 1.0), Const(0.9)))
println("Enzyme forward mode, ∂F/∂x at (0.2, 0.9): ", enzyme_forward,
    " (true value ", ForwardDiff.derivative(x -> tire(x, 0.9), 0.2), ")")
