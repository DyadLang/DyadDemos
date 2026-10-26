# Upstream follow-ups (drafts only; not filed)

The RC2 compiler's generated dataset annotation is handled by the existing
`fix_analysis_codegen.jl` workaround and the parent PR's compiler issue draft.
The physical-calibration failure was a demo loss/convergence configuration
problem, reproduced on 3.4; it does not need an upstream bug report.

## Draft: OptimizationOptimisers leaves completed Adam solves at ReturnCode.Default

**Affected:** OptimizationOptimisers 0.3.25 bundled with Dyad 3.5.0-rc2
(and the prior 3.4 distribution). QuarterTruck's bounded Adam probes return
`Default` after exactly the requested iterations, despite finite parameters,
finite objective values and working gradients. Do not rewrite this status to
`Success` in a caller.

**Minimal independent reproduction, tested on RC2:**

```julia
using OptimizationOptimisers, OptimizationBase
using SciMLBase: OptimizationFunction, OptimizationProblem, solve
f = OptimizationFunction((u, p...) -> sum(abs2, u);
    grad=(g, u, p...) -> (g .= 2 .* u))
r = solve(OptimizationProblem(f, [1.0, 2.0]), Adam(0.1); maxiters=3)
@show r.retcode r.stats r.objective
```

Result: `Default`, three iterations, objective `3.881259113573514`,
`u = [0.8004122286917928, 1.8001664861157012]`. This reproduction uses an
analytic gradient and has no truck model, ODE, dataset or compiler dependency.

**Demo reproduction:** instantiate QuarterTruckSciML and apply its documented RC2
code-generation workaround, then run:

```julia
using QuarterTruckSciML
r = TruckFullNNTrainingAnalysis(optimizer_maxiters=3, results_path="").r
@show r.retcode r.original.stats r.original.objective
```

ForwardDiff probe: `Default`, three iterations, objective
`50.838207224956335`. A second warm solve took 4.223714441 seconds overall
(4.011744976 seconds inside the optimizer). The adapter's
`OptimizationOptimisers.__solve` finishes with
`SciMLBase.build_solution(cache, cache.opt, θ, first(x)[1], stats=stats)`
without specifying a return code. This explains the propagated default status;
the demo has no evidence of optimizer convergence solely from reaching a budget.

The completed full-budget RC2 run also returned `Default` after exactly 5000
Adam iterations, with objective `0.38392485285212924`, finite 68-element weights
and `likely_wrong=false`. It took 4921.66849398613 seconds through the analysis,
4828.688752174377 seconds inside the optimizer. The subsequent LBFGS solve
returned `Success` after two iterations within its unchanged 200-iteration limit,
objective `0.38384846067991113`. It stopped on function change while its gradient
residual was `0.09430872088659324 > 1e-8`; it is not stationary (see next draft).
This does not retroactively change Adam's status.

**Expected:** distinguish iteration-budget completion, user callback termination,
and actual convergence with appropriate explicit SciML return codes. The demo's
training workflow records Adam's status, requires its full budget before using
that finite checkpoint, and requires both a successful LBFGS code and raw
gradient convergence before accepted weight export. The general upgrade validator
fails on all non-success optimizer statuses and nonstationary LBFGS results.

## UNFILED draft: LBFGS abstol controls function change, Success does not certify stationarity

**Status: UNFILED.** This is an adapter/documentation limitation; no upstream fix
or successful stationary training run is claimed. Affected: OptimizationOptimJL
bundled with Dyad 3.5.0-rc2 (Julia 1.13.2), and the NNTrainingAnalysis interface.

`OptimizationOptimJL.__map_optimizer_args` maps SciML `abstol` to
`Optim.Options(f_abstol=abstol)`. The analysis's `optimizer_abstol=1e-4` therefore
controls absolute objective change, while Optim's gradient tolerance remains
`g_abstol=1e-8`. `_optim_retcode` reports SciML `Success` whenever
`Optim.converged` is true, including a function-change stop. This behavior needs
to be explicit to callers using the success code as an optimality certificate.
The NNTrainingAnalysis interface does not separately expose a gradient tolerance.

**Small independent reproduction (no truck/data/ODE required):**

```julia
using OptimizationOptimJL, OptimizationBase
using SciMLBase: OptimizationFunction, OptimizationProblem, solve
f = OptimizationFunction((u, p...) -> 1e-6 * u[1]^4;
    grad=(g, u, p...) -> (g .= 4e-6 .* u.^3))
alg = LBFGS(linesearch=Optim.LineSearches.BackTracking(),
            alphaguess=Optim.LineSearches.InitialStatic())
r = solve(OptimizationProblem(f, [1.0]), alg; maxiters=200, abstol=1e-4)
raw = r.original
@show r.retcode raw.stopped_by raw.f_abschange raw.f_abstol
@show raw.g_residual raw.g_abstol
```

Tested on RC2: `Success`, `f_converged=true`, `g_converged=false`,
`f_abschange=8.024547161462743e-7`, `g_residual=1.1851780740629496e-6 > 1e-8`.
The line-search configuration matches the truck's raw LBFGS result.

**Demo reproduction:** from an instantiated QuarterTruckSciML project with its
code-generation workaround applied, pass a full-budget Adam checkpoint:

```julia
using QuarterTruckSciML
r = TruckFullNNTrainingAnalysisLBFGS(
    initial_values_path="/path/to/adam_weights.csv", results_path="").r
raw = r.original.original
@show r.retcode r.original.objective r.original.stats
@show raw.stopped_by raw.f_abschange raw.f_abstol raw.g_residual raw.g_abstol
```

The independently reproduced full-run result is `Success`, two iterations,
objective `0.38384846067991113`, `f_abschange=6.05356569405302e-5 ≤ 1e-4`,
`g_residual=0.09430872088659324 > 1e-8`. The original 5000-Adam/200-max-LBFGS
execution took 4958.64 s. No criteria or budgets were relaxed for this correction.

**Expected:** document the tolerance mapping, expose separate function-change
and gradient tolerances, and retain raw stopping reasons so callers can request
and verify optimality. Demo mitigation: preserve return codes and raw evidence,
require `stopped_by.g_converged` plus a finite gradient residual at most `1e-8`
before accepted LBFGS export, and report a nonzero failure otherwise. This leaves
training optimality unresolved rather than relabeling a function-change stall.

## Experimental observation, not a production-demo defect

A task-local performance experiment replaced the three tiny Lux Dense layers
with tuple-based matrix-vector arithmetic, retaining the same layer parameter
names, initial weights, 68-element layout and outputs. With ForwardDiff its warm
three-iteration solve took 2.922238363 seconds and allocated 1,087,425,208 bytes
(versus 4.223714441 seconds / 4,970,884,984 bytes with ordinary Dense layers).
The equivalent Enzyme experiment segfaulted during gradient preparation on RC2.
That experimental layer was **not adopted**. This is insufficiently minimized
for a separate filing; the task logs retain the probe and native crash trace.
