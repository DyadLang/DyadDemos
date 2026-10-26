# MotorTemperatureSciML upstream follow-up

## Draft: DataInitialization permutes measured states when depvars order differs

**Not filed.** Confirmed on Dyad 3.5.0-rc2 / Julia 1.13.2, bundled
DyadModelOptimizer 15.5.1, and Dyad 3.4.0 / Julia 1.12.7 with
DyadModelOptimizer 15.4.0. Both produce exactly the same initialization-error
numbers below. The original six-update training failure is still a
demo budget problem, not a compiler regression. Investigation of a better
initializer exposed this independent library defect.

`initialize_segments(::DataInitialization, ...)` in
`src/calibrate/multiple_shooting.jl:453` builds `model_vars_indices` using the
order of `get_saved_model_variables(experiment)`, then walks the ODE's
`get_diff_variables(model)` and assigns those rows sequentially. When both
lists contain the same states in different orders, data belonging to a
different state are assigned silently. Each state should instead locate its
own index in `model_vars`, independent of either list's order.

Exact experiment using this demo's four states and correctly paired data:

| Target declaration | Maximum initialization error across 95 junctions |
|---|---:|
| Canonical ODE states, ODE order | 0.0 °C |
| Same canonical state/data pairs, reversed pair order | 17.267799377441406 °C |
| Equivalent observed thermal aliases | 53.13800811767578 °C |

The observed-alias case warns “No model variable found in the data, segment
initialization defaulting to 0s.” It actually repeats the initial-temperature
defaults. Alias handling may be a feature limitation rather than a defect;
the reversed-pair case is an incorrect channel assignment with actual ODE
states and valid data. Merely replacing observed targets with canonical
states without also ordering the pairs still produces a wrong initializer.

First junction, ODE state order winding / tooth / yoke / magnet:
expected `[32.8321647644043, 26.36029815673828, 20.046693801879883,
28.819229125976562]` °C; reversed-pair initializer returns
`[28.819229125976562, 20.046693801879883, 26.36029815673828,
32.8321647644043]` °C. The measurements and data-fit target pairs are
unchanged; only declaration order differs.

Reproducer, from the project directory after instantiation:

```julia
using MotorTemperatureSciML, DyadModelOptimizer, OrdinaryDiffEqTsit5
const M = MotorTemperatureSciML
const D = DyadModelOptimizer
sys = M.simplify_model(M.Models.Tests.TestTNNProfile(; name=:profile))
(; t, meas) = M.profile_data(sys)
mask = t .<= 7200
canonical = M.temperature_depvars(sys) # exact aliases resolved, ODE order
expected = reduce(vcat, [permutedims(
    meas[only(findall(==(key), M.CHANNEL_KEYS)), 151:150:14251] ./ 200)
    for (_, key) in canonical])
for pairs in (canonical, reverse(canonical))
    ex = Experiment(M.normalized_targets(t[mask], meas[:,mask]), sys;
        tspan=(0.,7200.), name="initialization_order", depvars=pairs,
        loss=meansquaredl2loss, alg=Tsit5(),
        overrides=[sys.model.thermal.T_init[i]=>meas[i,1]/200 for i in 1:4],
        prob_kwargs=(; fully_determined=true, optimize=:aggressive))
    inv = M.build_invprob(ex, M.build_search_space(sys))
    alg = M.make_sms(; n_segments=96, batch_size=32, block_size=4,
        learning_rate=1e-3, inner_epochs=12, outer_maxiters=30)
    x = D.initial_state(alg, inv)
    starts = reshape(x[(length(D.search_space_names(inv))+1):end], 4, :)
    @show maximum(abs, starts - expected) * 200
end
# 0.0, then 17.267799377441406
```

The demo now resolves the thermal aliases to integrated ODE states and orders
their data pairs by the ODE state order. Its regression test checks all four
channels at all 95 shooting boundaries. This preserves the mathematical
fitting problem and avoids patching the library or accepting bad status codes.

## Optional render extension

The historical optional MultibodyComponents.Render load error did **not**
reproduce in this follow-up. Exact probe on RC2:

```sh
julia +dyad-3.5.0-rc2 --project=MotorTemperatureSciML -e \
  'using MultibodyComponents; using CairoMakie; println(Base.get_extension(MultibodyComponents, :Render))'
```

It exited successfully and printed `Render` (MultibodyComponents 0.3.0,
Makie 0.24.16); no dependency-load error was emitted. The installed package
correctly declares Makie as a weak dependency and Render extension trigger.
There is insufficient evidence to draft a precise new issue or assign a
cause to the earlier environment's failure.

The standalone validator's missing GR backend was a demo dependency assumption;
using its existing CairoMakie backend fixes it without changing the runtime.

## Investigation note: standalone calibration compilation cost

**Not filed; insufficient evidence to establish a defect or regression.** On the same RC2
distribution, the standalone full-budget script can spend minutes compiling
the calibration call before executing its optimizer callbacks. An earlier
attempt was interrupted by the factory watchdog after approximately 45
minutes without a calibration result; that unsampled run's phase is unknown.
A fresh attempt was explicitly stopped
after about three minutes; it did not report a training return code or export
weights. These interrupted runs did not produce numerical
`ConvergenceFailure` results.

Reproduction from this project, using the environment in
[followup-validation.md](followup-validation.md):

```sh
TNN_BUDGET=full JULIA_NUM_THREADS=2 julia +dyad-3.5.0-rc2 --project \
  scripts/train_stochastic_ms.jl --out-dir runs/compiler-probe
# From another terminal: kill -USR1 <julia-pid>
```

The signal-triggered stack (`.task/motor-followup/full-retry.log`) shows
`llvm::slpvectorizer::BoUpSLP::getTreeCost`,
`llvm::SLPVectorizerPass::vectorizeStoreChain`, `vectorizeStores`, and
`runImpl`, followed by Julia `jl_compile_codeinst_now`,
`OptimizationBase.solve_call` (`src/solve.jl:291`), and
`DyadModelOptimizer.calibrate` (`src/calibrate/calibrate.jl:77`). This is
LLVM 20.1 in Julia 1.13.2. The stack locates the sampled compilation cost;
it does not establish an infinite loop or identify the particular optimized
Julia method. The smaller A2/direct scheduled calibrations completed on the
same distribution. Keep the mathematically correct problem; investigate
compiler latency separately from optimizer convergence.

## Draft: document OptimizationAuglag success as continuity feasibility

**Not filed.** In the bundled RC2 `OptimizationAuglag.jl:205–223`, the dual
residual is computed as `r_dual = ρ * r_primal`, while its effective tolerance
is `max(ϵ_dual, ϵ_primal * ρ)`. For these equality constraints, satisfying the
primal test also satisfies that dual test; it does not establish Lagrangian
stationarity. A returned `Success` therefore certifies the configured shooting
continuity criterion, not first-order optimality of the data-fit objective.

The concrete A2 run illustrates the distinction: `Success` after 324 updates,
maximum junction gap 0.19840 °C against 0.2 °C, but magnet training RMS 3.31 °C
versus 0.61 °C for the shipped fit. Its independent tighter ODE replay gives
0.19848 °C. These are continuity-feasible, under-trained parameters.

Expected direction: document the actual termination guarantee and distinguish
primal feasibility from optimality in result reporting. Any future stationarity
criterion should use the Lagrangian gradient rather than a scaled primal
residual. The demo retains the original continuity criterion and separately
reports free-running training and held-out errors.
