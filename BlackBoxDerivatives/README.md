# BlackBoxDerivatives

How to give exact first and second derivatives of a black-box Julia function to every AD
backend and optimizer that a dynamic-optimization problem may use.

The black box is a tire force `F(slip, load)` with methods for `Float64` only. It sends each
value through raw bytes, as a file, a socket or a C library would, so AD cannot differentiate
it: most tools raise an error, and some silently return zero. Like a real library, it also
ships its partial derivatives `Fx, Fy, Fxx, Fxy, Fyy` as black boxes
([`src/black_box.jl`](src/black_box.jl)).

The Dyad model [`TireCar`](dyad/tirecar.dyad) connects a [`Tire`](dyad/tire.dyad), with
force `F(slip, 1 - 0.06 v)`, to a [`Car`](dyad/car.dyad), with `der(x) = v` and
`der(v) = force - 0.02 v^2`; the car's speed `v` feeds back to the tire. The problem is to
cover 10 m from rest and stop again in minimum time, with `-0.8 ≤ slip ≤ 0.8`. It is solved by direct
collocation on 40 intervals (123 unknowns, 80 constraints) with Ipopt
([`src/problem.jl`](src/problem.jl)). The reference is the same problem with the dynamics
written by hand, `F` replaced by its plain formula, and differentiated by ForwardDiff:
18 iterations, `T = 6.501371279257696`.

Run each stage from this folder with `julia --project=. scripts/<stage>.jl`. The tests run all
three in order. The outputs below come from that run, slightly trimmed.

## 1. No derivative information

[`scripts/stage1_no_derivatives.jl`](scripts/stage1_no_derivatives.jl) uses finite differences
of the black box.

```
finite differences + L-BFGS     Solve_Succeeded, 49 iterations, |T - T_ref| = 2.69e-13, 254960 black-box calls during the solve
finite differences, FD Hessian  Solve_Succeeded, 18 iterations, |T - T_ref| = 1.78e-15, 21886640 black-box calls during the solve
```

Both runs find the same optimum. With the L-BFGS Hessian approximation, Ipopt needs 2.7 times as
many iterations. With a finite-difference Hessian it needs no more iterations, but makes 22
million black-box calls. Stage 3 needs between 5 thousand and 1.1 million.

## 2. Ask for AD without defining anything

[`scripts/stage2_ask_for_ad.jl`](scripts/stage2_ask_for_ad.jl):

```
ForwardDiff             MethodError: no method matching F(::ForwardDiff.Dual{…}, ::ForwardDiff.Dual{…})
Enzyme                  EnzymeNoDerivativeError: No create nofree of empty function (jl_string_to_genericmemory) …
sparse (auto-detected)  MethodError: no method matching F(::SparseConnectivityTracer.GradientTracer{Int64, BitSet}, ::SparseConnectivityTracer.GradientTracer{Int64, BitSet})
JuMP, F only            Unable to register the function :F. …
Symbolics, ∇F(0.2, 0.9): [0, 0] (true value [1.230026980463358, 0.7420026278311731])
Enzyme forward mode, ∂F/∂x at (0.2, 0.9): 0.0 (true value 1.230026980463358)
```

The last two lines have no error, only wrong values (see [Silent failures](#silent-failures)).
Symbolics knows `F` here, because the Dyad model needs `@register_symbolic F(x, y)`, but has
no derivative rules for it.

## 3. Define the derivatives

[`scripts/stage3_define_derivatives.jl`](scripts/stage3_define_derivatives.jl) calls
`BlackBoxDerivatives.define_derivatives()`, which loads the per-backend files. (A real library
would just include them; here they load on request so that stages 1 and 2 can run without
them.) Then it solves with exact Hessians:

```
Symbolics               Solve_Succeeded, 18 iterations, |T - T_ref| = 0.0,     max |z - z_ref| = 3.9e-16, 6960 black-box calls during the solve
ForwardDiff             Solve_Succeeded, 18 iterations, |T - T_ref| = 0.0,     max |z - z_ref| = 3.9e-16, 811440 black-box calls during the solve
Enzyme                  Solve_Succeeded, 18 iterations, |T - T_ref| = 0.0,     max |z - z_ref| = 2.8e-16, 1125600 black-box calls during the solve
sparse (auto-detected)  Solve_Succeeded, 18 iterations, |T - T_ref| = 0.0,     max |z - z_ref| = 3.3e-16, 74640 black-box calls during the solve
JuMP                    LOCALLY_SOLVED,  18 iterations, |T - T_ref| = 1.8e-15, max |z - z_ref| = 1.8e-15, 5040 black-box calls during the solve
```

The tests check every backend's gradient and Hessian of `F`, and every backend's Jacobian and
Lagrangian Hessian of the whole problem, against the reference with a relative tolerance of
1e-10. The observed errors are at rounding level.

## What to define for each backend

For Hessians, `Fx` and `Fy` need the same rules as `F`.

| Backend or optimizer | What it needs | File |
|---|---|---|
| Dyad / ModelingToolkit model | `@register_symbolic` on `F` and its partials (always loaded) | [`BlackBoxDerivatives.jl`](src/BlackBoxDerivatives.jl) |
| Symbolics (`AutoSymbolics()`) | `@register_derivative` for `F → Fx, Fy`, `Fx → Fxx, Fxy` and `Fy → Fxy, Fyy` (the integer is the argument index) | [`symbolics.jl`](src/symbolics.jl) |
| ForwardDiff (`AutoForwardDiff()`) | `Dual` methods on `F`, `Fx`, `Fy` | [`forwarddiff.jl`](src/forwarddiff.jl) |
| Enzyme (`AutoEnzyme()`) | ChainRules `frule` and `rrule` on `F`, `Fx`, `Fy`, imported with `Enzyme.@import_frule` and `@import_rrule` | [`enzyme.jl`](src/enzyme.jl) |
| Automatic sparsity detection (`AutoSparse(…; sparsity_detector = TracerSparsityDetector())`) | SparseConnectivityTracer overloads on `F`, plus the rules of the dense backend inside | [`sparsity.jl`](src/sparsity.jl) |
| JuMP | an operator `F` with gradient and Hessian callbacks, and an `F` method on JuMP expressions (JuMP ignores all the rules above) | [`jump.jl`](src/jump.jl) |
| An optimizer that only takes callbacks | nothing more: build the callbacks from any backend above | [`callbacks.jl`](src/callbacks.jl) |

Dense ForwardDiff and Enzyme call the black box 11 and 15 times as often as sparse ForwardDiff
(see the call counts above). Symbolics and JuMP, which call the black-box partials directly,
are the cheapest here.

## External optimizers that only take callbacks

`callbacks(backend)` turns the problem into plain functions:

```julia
cb = BlackBoxDerivatives.callbacks(AutoSymbolics())   # or any backend in the table
cb.n, cb.lb, cb.ub, cb.z0  # unknowns, their bounds, starting point
cb.m, cb.con_lb, cb.con_ub # constraints and their bounds
cb.f(z); cb.grad!(g, z); cb.cons!(c, z)
cb.jac!(vals, z)         # values at cb.jac_structure  == (rows, cols)
cb.hess!(vals, z, σ, λ)  # Hessian of σ f(z) + λ ⋅ c(z), at cb.hess_structure (lower triangle)
```

A constrained problem also needs constraint and Jacobian callbacks, and the Hessian is that of
the Lagrangian. The structures are sparse for `AutoSparse` and dense otherwise.
[`src/ipopt.jl`](src/ipopt.jl) passes these callbacks to Ipopt's C interface, in place of
an external optimizer. Nothing here depends on JuMP or Optimization.jl.

## Silent failures

- Symbolics with `F` registered but no `@register_derivative` rules treats its derivatives as
  zero (stage 2).
- A method like `F(x::Real, y::Real) = F(value(x), value(y))` "fixes" the MethodError. It runs,
  and the derivatives are zero.
- Enzyme's forward mode runs through the byte round trip and returns 0 with no error (stage 2).
  Its reverse mode does raise an error.

Always compare the derivatives against a reference; the tests do.

## Notes

- ModelingToolkit's own dynamic-optimization problems (11.45.3) do not pass Symbolics rules to
  JuMP: with this package loaded, `JuMPDynamicOptProblem` and `InfiniteOptDynamicOptProblem` build,
  then fail at solve with ``UnsupportedNonlinearOperator: The nonlinear operator `:F` is not supported by the model.``
  This demo builds the collocation problem itself, from the model's equations.
- Versions: Dyad 3.5.0 Julia distribution (Julia 1.13.2), Enzyme 0.13.214 (bundled with that
  distribution), ForwardDiff 1.4.6, Symbolics 7.45.0, ModelingToolkit 11.45.3,
  DifferentiationInterface 0.7.21, SparseConnectivityTracer 1.2.4, JuMP 1.31.2, Ipopt.jl 1.16.0.
