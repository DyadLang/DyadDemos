# QuarterTruckSciML: Dyad 3.5 upgrade validation

Current target: Dyad **3.5.1**. Commands below use that channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Target: Dyad `3.5.0` language with runtime `dyad-3.5.0-rc2` (Julia 1.13.2).
Baseline: the original project on `dyad-3.4.0` (Julia 1.12.7).
Runs use two Julia threads and one precompile task.

This is the historical upgrade comparison. The [follow-up report](followup-validation.md)
supersedes the calibration outcome, full-training timing and training acceptance
claims: LBFGS `Success` can be a function-change stop without stationarity. The
current scripts require its raw gradient criterion before accepted weight export.

## References read before editing

- [BlockComponents changelog](https://github.com/JuliaComputing/BlockComponents/blob/v5.0.0/CHANGELOG.md): BlockComponents 5.0 and constructor API 2.
- [DyadInterface changelog](https://github.com/JuliaComputing/DyadInterface.jl/blob/v7.5.1/CHANGELOG.md): generated analysis `__system` handoff and setup adapters.
- [DyadData 2.3 release](https://github.com/JuliaComputing/DyadData.jl/releases/tag/v2.3.0): native Parquet extension and CSV 1 compatibility.
- [DyadModelOptimizer 15.5.1 release](https://github.com/JuliaComputing/DyadModelOptimizer.jl/releases/tag/v15.5.1): accepts generated `__system`.

- [RotationalComponents changelog](https://github.com/JuliaComputing/RotationalComponents/blob/v3.0.0/CHANGELOG.md): constructor API 2 requires dotted-path `__overrides`.

- [TranslationalComponents changelog](https://github.com/JuliaComputing/TranslationalComponents/blob/v3.0.0/CHANGELOG.md) and [ThermalComponents changelog](https://github.com/JuliaComputing/ThermalComponents/blob/v3.0.0/CHANGELOG.md): library 3.0 migration.
- [DyadModelDiscovery 0.6 release](https://github.com/JuliaComputing/DyadModelDiscovery.jl/releases/tag/v0.6.0): analysis `__system` handoff, CSV 1, and AD backend selection.

## Reproduction

The follow-up validator now rejects Adam’s non-success `Default` before export.
An unfiltered run therefore exits 1 by design, and its dependent LBFGS stage
has no checkpoint to load. Use `scripts/train.jl` for staged training: it
retains a completed Adam budget as a non-converged checkpoint and requires
LBFGS gradient optimality before accepted export. Historical bounded-training
commands and results below predate these stricter guards.

Instantiate this project, regenerate with the Dyad 3.5 CLI, then run the existing tests and all concrete analyses:

```sh
julia +dyad-3.5.1 --project -e 'using Pkg; Pkg.instantiate()'
../.ci/compiler/dyad --version
JULIA_EXECUTABLE="julia +dyad-3.5.1" dyad compile "$PWD"
julia +dyad-3.5.1 --project scripts/fix_analysis_codegen.jl
JULIA_NUM_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=1 julia +dyad-3.5.1 --project -e 'using Pkg; Pkg.test()'
DYAD_UPGRADE_OUTPUT=/path/to/results JULIA_NUM_THREADS=2 julia +dyad-3.5.1 --project scripts/validate_upgrade.jl
```

The validation driver uses the declared simulation horizons and training budgets,
checks ODE return codes and finite state/parameter values, and writes per-analysis
metrics and state trajectories. Training output goes to the validation directory.
`DYAD_UPGRADE_ONLY` selects a comma-separated subset when retrying failed runs.

## RC2 compiler verification (2026-10-26)

Regenerated this project with the repository's `../.ci/compiler/dyad`, reporting
`3.5.0-rc2 (a24a224; compiler-only source build)`. Its source checkout is exactly
`a24a2240667872d432a3b86c4db1240d77150e35` (`v3.5.0-rc2`).
Then ran `scripts/fix_analysis_codegen.jl` with the RC2 Julia runtime, as shown
above. The generated tree now preserves the compiler's exact output, including
blank-line whitespace, except for the required `DyadTimeseries` annotation
correction. The script's former whitespace replacement has been removed.
A byte comparison against raw compiler output verified that the annotation
replacement is the only change; rerunning the script makes no further changes.

The workaround tracks [upstream issue #1958](https://github.com/JuliaComputing/dyad-lang/issues/1958).
Every Dyad Studio recompile, including compile on save, also requires rerunning
the script before loading the project again; see the
[README workflow](../README.md#recompiling-with-dyad-studio-or-cli).

Re-ran `julia +dyad-3.5.1 --project -e 'using Pkg; Pkg.test()'` after regeneration,
with two Julia threads and one precompile task: **15/15 assertions passed**,
including the calibration/training analysis-construction regressions.

The numerical tables and workflow results below are retained from the earlier
validation; those analyses were not rerun during this provenance check. The
unchanged generated code supports retaining them without relabeling their
original compiler provenance.

## Results

The existing test suite passes **15/15** assertions: 12 ISO-road/vehicle/NN
smoke assertions and three calibration/training-construction regressions.
The numerical comparisons and training results below were originally run with
code generated by CLI `3.5.0-rc1 (e5bac67)`, using the RC2 runtime and the
documented project-local correction of the generated parametric-dataset
annotation. The public `.dyad` analysis definitions retain their declared APIs
and budgets.

### Full-horizon transient comparisons

Both runtimes return `Success` for all five transient analyses. State/signal
names are matched on identical saved time grids; duplicate algebraic aliases
are counted once. Values below are the largest absolute sample difference
across distinct matched signals, with RMS difference for the signal attaining
that maximum.

| Analysis | Samples | Distinct signals | Largest absolute change | RMS change at that signal |
|---|---:|---:|---:|---:|

| AnalysisFullNNSin | 501 | 10 | 5.830678e-10 | 4.559937e-11 |
| QuarterTruckReferenceTransient | 501 | 10 | 4.756612e-10 | 4.613364e-11 |
| TestDenseISO8608RoadTransient | 10001 | 51 | 2.773389e-16 | 4.163145e-17 |
| TestHalfSineBumpTransient | 501 | 1 | 0 | 0 |
| TestISO8608RoadTransient | 10001 | 1 | 8.673617e-17 | 1.010568e-17 |

For the signal harnesses the outputs are distances (m). For the two vehicle
harnesses the largest difference is road velocity (m/s), below 6e-10 m/s.

### Physical calibration: declared 100-iteration limit

Both runs execute 100 optimizer iterations and return `MaxIters`, with finite
parameters and `likely_wrong=false`. This is a completed bounded-budget run,
not a successful-convergence claim. The resulting 3.5 parameter errors versus
the synthetic truth are below 0.00004% for mass/stiffness, 0.083% for damping,
and 0.020% for friction.

| Parameter | Truth | 3.4 result | 3.5 result | Absolute old/new change |
|---|---:|---:|---:|---:|
| body_m | 315 | 315.000000574 | 315.000000627 | 5.283084e-08 |
| tire_to_body_c | 22000 | 22000.0071947 | 22000.0076278 | 0.0004331139 |
| tire_to_body_d | 1800 | 1801.49128034 | 1801.48089708 | 0.01038326 |
| friction_Fc | 750 | 749.853195152 | 749.854294596 | 0.001099444 |

The objective changes from 0.0764897855707 to 0.0764899643804 (absolute change 1.788096e-07).

### Neural-network training

The declared 5000-iteration Adam budget was attempted on both runtimes, then
interrupted because it had not completed after approximately 23 minutes on 3.5
and 17 minutes on 3.4. Profiling confirmed active gradient evaluation; no runtime
exception was reported, but neither attempt returned a calibration result or
exported weights. The number of iterations reached in those interrupted
attempts was not logged and is unknown. Consequently the full 5000/200 Adam/LBFGS
schedule is **not validated** here.

A follow-up feasibility review used the existing bounded-run optimizer statistics:
25 Adam iterations took 149.50 s inside the optimizer on the RC2 runtime (223.28 s including
analysis setup). Linear extrapolation of optimizer time alone gives approximately
8.3 hours for 5000 iterations, before LBFGS; this is an estimate, not a measured
full-run duration. The earlier 23-minute attempt also did not finish. There is
no evidence that the declared schedule can complete promptly, so the RC2
provenance follow-up did not launch additional training or alter the defaults.

Both analysis APIs are instead validated with explicit limits of **25 Adam
iterations followed by 10 LBFGS iterations**, with the exported Adam weights
loaded by LBFGS. Their results are recorded below. The `.dyad`
defaults remain 5000/200. To reproduce the bounded training validation, set:

```sh
DYAD_UPGRADE_ADAM_MAXITERS=25 DYAD_UPGRADE_LBFGS_MAXITERS=10 \
DYAD_UPGRADE_ONLY=TruckFullNNTrainingAnalysis,TruckFullNNTrainingAnalysisLBFGS \
DYAD_UPGRADE_OUTPUT=/path/to/results JULIA_NUM_THREADS=2 \
julia +dyad-3.5.1 --project scripts/validate_upgrade.jl
```

| Analysis | Actual iterations (3.4 / 3.5) | Optimizer status (3.4 / 3.5) | Objective 3.4 | Objective 3.5 | Absolute change |
|---|---:|---|---:|---:|---:|
| TruckFullNNTrainingAnalysis | 25 / 25 | Default / Default | 46.8638744342 | 47.1494116607 | 0.2855372 |
| TruckFullNNTrainingAnalysisLBFGS | 10 / 9 | MaxIters / Success | 3.98548056392 | 5.11265092117 | 1.12717 |

All four bounded training results have finite 68-element parameter vectors and
`likely_wrong=false`. Adam reports `Default` at its iteration budget on both
runtimes; this is not presented as converged. The LBFGS limit is 10 iterations:
3.4 reaches that limit, while 3.5 returns `Success` after nine iterations. The
final objective is about 28.3% higher on 3.5 at these short budgets. These runs
validate gradient evaluation, CSV export/import and refinement execution;
they do not establish equivalence of a newly trained full-budget fit. DyadModelDiscovery
0.6 adds a configurable AD backend and defaults to Enzyme, while the baseline
uses its earlier training implementation.

### Existing held-out validation and plot export

`scripts/validate.jl` completes on 3.5 with the committed pretrained weights and
writes the ignored `assets/validation_iso_a.png` plot. On ISO 8608 Class A input:

| Observable | Truth signal RMS | Linear error / signal RMS | Pretrained NN error / signal RMS |
|---|---:|---:|---:|
| Tire position | 0.0005433 m | 87.65% | 11.47% |
| Driver position | 0.0006548 m | 147.09% | 56.77% |
| Driver acceleration | 0.07255 m/s² | 115.11% | 44.44% |

All eight defined analyses were exercised on both runtimes. Five transients and
the physical calibration use their declared horizons/budgets; training uses the
explicit bounded limits above. The full 5000/200 retraining schedule was not
completed. No measurement/training datasets or committed NN weights were
regenerated or overwritten; generated validation outputs stay ignored or in the
selected validation output directory.
