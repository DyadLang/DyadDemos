# QuarterTruck follow-up validation

Date: 2026-10-26. Scope: physical calibration, full-budget neural training,
script/notebook status reporting and safe output paths. The root upgrade report
is unchanged. The original `upgrade-3.5-validation.md` records earlier runs;
this document supersedes its physical-calibration outcome and training timing
assumptions only where explicitly supported below.

## Environment and commands

Runs use the existing Dyad distribution, two Julia threads, one precompile task,
and the preserved task-local depot; no host/global packages were installed.
From the workspace above `DyadDemos`:

```sh
export JULIAUP_DEPOT_PATH="$PWD/.toolchain/juliaup"
export JULIAUP_SERVER=https://juliahub.com/juliabin
export JULIA_DEPOT_PATH="$PWD/.toolchain/depot"
export JULIA_NUM_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=1
export JULIA_PKG_PRECOMPILE_AUTO=0 JULIA_PKG_USE_CLI_GIT=true
export JULIA_EXECUTABLE="$PWD/.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2"
.toolchain/compiler-build/dyad compile "$PWD/DyadDemos/QuarterTruckSciML"
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project=DyadDemos/QuarterTruckSciML \
  DyadDemos/QuarterTruckSciML/scripts/fix_analysis_codegen.jl
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project=DyadDemos/QuarterTruckSciML \
  -e 'using Pkg; Pkg.test()'
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project=DyadDemos/QuarterTruckSciML \
  DyadDemos/QuarterTruckSciML/scripts/run_calibration.jl
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project=DyadDemos/QuarterTruckSciML \
  DyadDemos/QuarterTruckSciML/scripts/train.jl "$PWD/.task/quarter-followup/full-training"
```

Compiler: exact `v3.5.0-rc2`, `a24a2240667872d432a3b86c4db1240d77150e35`.
The existing annotation workaround remains required after every regeneration.
Evidence logs and experimental scripts are in `.task/quarter-followup`.

## Physical calibration

The pre-upgrade baseline in `.task/sciml/baseline/QuarterTruckSciML` was run with
`+dyad-3.4.0` (Julia 1.12.7), its preserved original environment and analyses.
The original analysis returns `MaxIters` after 100 iterations on 3.4 too:
328.846171221 s around analysis execution, 223.044908047 s in the optimizer,
objective `0.0764897855707439`. Parameters:
`[315.0000005744307, 22000.007194655205, 1801.4912803449884, 749.8531951517773]`.
This is a pre-existing demo configuration problem, not an upgrade regression.

The default L2 loss is the **square root** of the sum of squared residuals.
Replacing it with smooth `SquaredL2Loss()` and tightening the optimizer's
stopping tolerance from `1e-4` to `1e-8` gives successful convergence without
changing the 100-iteration limit, ODE tolerances (`1e-8`), bounds, nominal initial
guesses, model or committed measurements. Bounds still contain the truth
strictly. All parameters are estimated, rather than fixed to their truth values.

RC2 result: **Success**, 43 iterations, `likely_wrong=false`, squared objective
`0.0058507392955954975`. The diagnostic probe took 222.582610302 s around the
analysis (103.566616058 s inside the optimizer). A fresh run through the final
generated defaults and `scripts/run_calibration.jl` independently returned the
same objective/43 iterations, with 104.026826 s inside the optimizer.

| Parameter | Truth | Recovered on RC2 | Relative error |
|---|---:|---:|---:|
| body mass [kg] | 315 | 315.0000005707893 | +0.0000001812% |
| suspension stiffness [N/m] | 22000 | 22000.007209638334 | +0.0000327711% |
| suspension damping [N·s/m] | 1800 | 1801.4891303203733 | +0.0827294622% |
| friction [N] | 750 | 749.8534151574834 | −0.0195446457% |

A separate 10-second integration at `abstol=reltol=1e-10` returned `Success`.
Against all 1001 committed samples:

| Observable | RMS residual | Maximum absolute residual | RMS residual / data standard deviation |
|---|---:|---:|---:|
| Tire force [N] | 0.00241765144669 | 0.0131896125031 | 4.32894869122e-5 |
| Suspension travel [m] | 5.59086819656e-8 | 6.22679987572e-8 | 3.51107861550e-5 |
| Seat acceleration [m/s²] | 9.66121324563e-6 | 0.000302870776178 | 1.06941994953e-4 |

Limits: the ISO Class A input weakly distinguishes viscous damping from the
smooth Coulomb force. At truth the maximum relative velocity is 0.0351766 m/s,
below the friction smoothing scale of 0.1 m/s. A central finite-difference
sensitivity calculation (relative parameter step `1e-4`, each observable divided
by its measured standard deviation, integration tolerance `1e-10`) gives
singular values `[4561.5073, 1343.1336, 29.5810, 0.0715166]`, condition number
63782.5, and damping/friction column cosine 0.99994665. The local sensitivity is
full rank but poorly conditioned. These noise-free synthetic results establish
this bounded demo's recovery; they do not establish reliable inference with
real sensor noise. The force residual at exact truth is already about
0.0024213 N RMS under both `1e-8` and `1e-10` integrations, so driving the loss
to zero by changing data would misrepresent the numerical floor.

Rejected probes are retained in task logs: merely changing to LBFGS returned
`Success` in 12 iterations but recovered damping 1538.0 (14.6% low); squared
loss with the old loose stopping tolerance returned `Success` in 20 iterations
but recovered damping 1720.0 (4.44% low). Even a normalized squared-loss probe
stopped early with damping 1528.3. Success codes alone were not used to accept a
fit. An alternative sine-excitation experiment failed during parameter override
setup and was not adopted or counted as validation.

The same corrected loss/tolerance was also tried as a runtime override on the
unchanged 3.4 project: **MaxIters**, 100 iterations, squared objective
`0.005858303121495743`, parameters
`[315.00000111992443, 22000.010136391742, 1801.2381218658152, 749.8765335165813]`.
It took 491.548563893 s around the analysis / 361.849316120 s inside the
optimizer. The correction is validated as converged on the target RC2 runtime;
no successful-convergence claim is made for this tighter-tolerance 3.4 probe.

## Training performance and full schedule

The declared budgets remain **5000 Adam / 200 LBFGS**, with the same 5-second
horizon, 501 training samples, 68 weights, `1e-8` ODE tolerances, Tsit5 solver,
initialization and learning rate. Both analyses now explicitly select
ForwardDiff; no iteration budget or stopping requirement was relaxed.

A three-iteration RC2 probe with ordinary Lux Dense layers and ForwardDiff took
87.531764936 s including analysis setup/compilation (11.117348909 s inside the
optimizer). The second, warm run took **4.223714441 s**, 4.011744976 s in the
optimizer, allocated 4,970,884,984 bytes, and returned `Default`, objective
`50.838207224956335`. The profile shows repeated ODE RHS evaluation, Lux Dense
matrix operations and allocation as the main costs. The earlier recorded
Enzyme-default 25-iteration run took 149.50 s inside the optimizer; this is a
comparison between measured probes, not a measured full-schedule speedup.

A 25-iteration RC2 ForwardDiff probe returned `Default` (25 iterations,
`likely_wrong=false`) with objective `46.86387443422178`, 30.482290030 s inside
the optimizer, and 107.745311975 s through the validation driver. Its weights
differ from the preserved 3.4 25-iteration output by at most 7.21535054e-10;
the objective difference is -1.97033500626e-11. This restores numerical agreement
with the pre-upgrade ForwardDiff trajectory. The strict validator deliberately
exited nonzero for `Default`; its 152.47 s process wall time includes startup
and error reporting. This is a bounded backend comparison, not the full run.

A task-only tuple-based Dense implementation preserved all parameters and
matched the three-iteration objective to about 2e-11, reducing allocation and
warm time to 1,087,425,208 bytes / 2.922238363 s. It was not adopted: it would add
custom network implementation and its Enzyme variant segfaulted. The production
model and committed pretrained parameter layout remain unchanged.

Full schedule result: **pending while the foreground run completes**. No
extrapolated duration is presented as a measured completion time.

## Held-out validation with shipped weights

The updated `scripts/validate.jl` completed in 110.18 s process wall time
(`/usr/bin/time -p`), with successful finite-state integrations and a PNG under
`.task/quarter-followup/shipped-heldout`. Its ISO Class A errors match the
earlier report:

| Observable | Signal RMS | Linear error / signal RMS | Shipped NN error / signal RMS |
|---|---:|---:|---:|
| Tire position | 0.0005433 m | 87.65% | 11.47% |
| Driver position | 0.0006548 m | 147.09% | 56.77% |
| Driver acceleration | 0.07255 m/s² | 115.11% | 44.44% |

This validates the committed pretrained artifact, separately from newly trained
weights. A new-fit held-out result is still pending full training.

## Training objective and model limits

The model keeps known masses, gravity, linear springs and damping and asks a
3→5→5→3 tanh network (68 weights) for three instantaneous residual forces.
Inputs and force outputs are scaled in `ScaledNeuralNetworkBlock`; the seat
residual includes a velocity prefactor so that it vanishes at zero relative
velocity. The forward IVP and final fitted predictions are validated separately
from the optimizer status.

The declared loss is an unweighted L2 norm over tire position, driver position
and driver acceleration. These have different units, so the numeric loss
emphasizes acceleration; there is no claim of unit-invariant statistical
weighting. For the shipped weights, an independent Tsit5 replay returned
`Success` over all 501 training samples, recomputed L2 objective
`0.3841475545690311`, with RMS residuals 0.00368596 m, 0.00358845 m and
0.01637334 m/s² respectively (16.21%, 18.75%, 0.564% of each data standard
deviation). This illustrates why the total loss must be read alongside the
per-observable and held-out errors.

One sinusoidal road input does not identify a unique three-input nonlinear
force law or unique network weights (including ordinary hidden-unit
permutations). Held-out ISO-road prediction is the relevant generalization
check; successful optimization alone does not establish physical recovery of
all three missing force laws. No such uniqueness or broad out-of-distribution
accuracy claim is made.

## Script and notebook audit

- `run_calibration.jl` prints optimizer status/objective/statistics and rejects
  non-success, nonfinite or diagnostically flagged results.
- `train.jl` uses a fresh output directory (or the explicit directory argument),
  rejects existing checkpoint filenames, logs progress and actual timings, and
  keeps Adam's return code visible. Direct `.dyad` training exports also default
  to ignored `training-results/` paths rather than the shipped weights. `Default` is accepted only as a finite,
  full-5000-iteration checkpoint for refinement, never as convergence. Final
  LBFGS must return a successful code. The unsupported five-minute and
  machine-precision claims were removed.
- `validate_upgrade.jl` now exits with failure for non-success optimizer codes;
  finite vectors or `likely_wrong=false` no longer allow `MaxIters`/`Default`
  to pass the validator. Its physical-calibration-only run returned `PASS`,
  43 iterations, 102.467998028 s optimizer time, 251.22 s process wall time.
- `validate.jl` and `export_validation_csv.jl` check ODE success/finite states;
  `QUARTERTRUCK_WEIGHTS` and `QUARTERTRUCK_VALIDATION_OUTPUT` select new weights
  and isolated outputs for held-out evaluation. The CSV exporter was exercised
  with the shipped weights: 1001 rows × 11 columns, 102.68 s process wall time.
- Both data generators check solver success/finite states and accept an optional
  output filename. The calibration generator now uses explicit `1e-10`
  tolerances for future deliberate regeneration.
- The analysis notebook selects calibration and its convergence plot by default,
  checks optimizer status, and directs training through the safe staged script.
  Its fallback DyadOrchestrator version was updated to the bundled 0.15.0 and
  all Julia cells passed syntax parsing. The interactive DyadOrchestrator/plot
  frontend itself was not exercised in this headless run.

## Tests and data safety

`Pkg.test()` passed **19/19 assertions**: 12 existing smoke assertions, three
analysis-construction assertions and four new physical-calibration assertions
(success code, finite values, <0.1% parameter error and objective below 0.006).
Reported test-set times: 1m23.2s smoke, 7.3s construction, 2m42.1s calibration.

The calibration generator was run with a task output filename: 1001 rows,
explicit `1e-10` integration tolerances, `Success`, 80.19 s process wall time.
The training-data generator also completed with a task output filename:
501 rows, `Success`, 83.85 s process wall time.
No committed dataset or pretrained weight was regenerated or overwritten. SHA256:

| File under `assets/data` | SHA256 |
|---|---|
| calibration_measurements.csv | bed7eb09b7cc2a35d6e10e6f695cac958c89697a02a98cc1dfb01fb534395e2e |
| truck_sin_full_train.csv | 8ff03b75166cedf32a4e0f88b82297f60f6dd01a8b8da11942354da442a43ece |
| nn_weights_full_sin_lbfgs.csv | a23859999a2f7307ad665ebb6008615ca3fc3a390d6eae2e5dc0ca0c6827359d |

The full-training output and all regenerated experimental data remain under
`.task/quarter-followup`. Upstream status handling is described in
[the unfiled issue drafts](followup-upstream-issues.md).
