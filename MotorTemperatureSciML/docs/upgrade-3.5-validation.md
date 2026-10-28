# MotorTemperatureSciML: Dyad 3.5 upgrade validation

Current Julia distribution: **dyad-3.5.0**; Dyad CLI target: **3.5.1**. Forward-looking reproduction commands use the 3.5.0 Julia channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Target: Dyad `3.5.0` language with runtime `dyad-3.5.0-rc2` (Julia 1.13.2).
Baseline: the original project on `dyad-3.4.0` (Julia 1.12.7).
Runs use two Julia threads and one precompile task.

## References read before editing

- [BlockComponents changelog](https://github.com/JuliaComputing/BlockComponents/blob/v5.0.0/CHANGELOG.md): BlockComponents 5.0 and constructor API 2.
- [DyadInterface changelog](https://github.com/JuliaComputing/DyadInterface.jl/blob/v7.5.1/CHANGELOG.md): generated analysis `__system` handoff and setup adapters.
- [DyadData 2.3 release](https://github.com/JuliaComputing/DyadData.jl/releases/tag/v2.3.0): native Parquet extension and CSV 1 compatibility.
- [DyadModelOptimizer 15.5.1 release](https://github.com/JuliaComputing/DyadModelOptimizer.jl/releases/tag/v15.5.1): accepts generated `__system`.

The project also constrains LazyArrays to `2.13.1 - 2.14.4`: [LazyArrays 2.14.5](https://github.com/JuliaArrays/LazyArrays.jl/releases/tag/v2.14.5)
introduced `OffDiagonalLayout` and requires ArrayLayouts 1.15, while this Dyad
runtime bundles ArrayLayouts 1.14. The initial unconstrained resolution selected
LazyArrays 2.14.6 and failed to precompile Parquet2; this bound fixes that concrete
failure. CSV now permits 1.1, matching the distribution.

## Reproduction

Instantiate this project, regenerate with the Dyad 3.5 CLI, then run the existing tests and all concrete analyses:

```sh
julia +dyad-3.5.0 --project -e 'using Pkg; Pkg.instantiate()'
dyad --version
JULIA_EXECUTABLE="julia +dyad-3.5.0" dyad compile "$PWD"
JULIA_NUM_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=1 julia +dyad-3.5.0 --project -e 'using Pkg; Pkg.test()'
DYAD_UPGRADE_OUTPUT=/path/to/results JULIA_NUM_THREADS=2 julia +dyad-3.5.0 --project scripts/validate_upgrade.jl
```

The validation driver uses the declared simulation horizons and training budgets,
checks ODE return codes and finite state/parameter values, and writes per-analysis
metrics and state trajectories. Training output goes to the validation directory.
`DYAD_UPGRADE_ONLY` selects a comma-separated subset when retrying failed runs.

## RC2 compiler verification (2026-10-26)

Regenerated this project with the repository's then-present RC2 compiler wrapper (since removed), reporting
`3.5.0-rc2 (a24a224; compiler-only source build)`. Its source checkout is exactly
`a24a2240667872d432a3b86c4db1240d77150e35` (`v3.5.0-rc2`).
The earlier validation did not record its compiler version; its runtime was
RC2. This follow-up establishes the current generated code's RC2 provenance.
The regenerated tree differed from the committed version only in compiler-emitted
blank-line whitespace. The final review fixes retain that compiler-emitted
whitespace, so the committed generated tree now matches the compiler byte for byte. This project has no
`scripts/fix_analysis_codegen.jl` and needs no parametric-dataset annotation fix.

Re-ran `julia +dyad-3.5.0-rc2 --project test/runtests.jl` after regeneration,
with two Julia threads and one precompile task: **79/79 assertions passed**,
including the full training-profile transient check. No extension-load error
was emitted in this test rerun.

The numerical tables and workflow results below are retained from the earlier
validation; those analyses were not rerun during this provenance check. The
unchanged generated code supports retaining them without relabeling their
original compiler provenance.

## Results

The existing test suite passes **79/79** assertions: temperature scaling (14),
signal routing (43), allocation-free interpolation (5), output-path handling
(11), and full training-profile transient checks (6). The first attempt failed
before model loading with LazyArrays 2.14.6; resolving with the documented
compatibility bound selects 2.14.4 and passes all tests.

The runtime also emits an error while trying to load the optional
`MultibodyComponents.Render` extension when Makie is loaded: the extension cannot
find Makie in its dependencies. This demo does not use that extension, and the
model/tests continue successfully. Makie's optional prebuilt texture-atlas fetch
was unavailable; Makie regenerated it locally through its normal fallback.

Custom `TNNFreeRunAnalysisSpec` and `TNNTrainingAnalysisSpec` now accept the
`__system` handoff. The profile builder and temperature-scale test use constructor
API 2's dotted `__overrides` dictionary for `model.MAX_TEMP`. Regenerated partial
analysis definitions are retained. The validation inventory explicitly excludes
the two partial analysis types, which have no runnable model of their own.

All **11 concrete analyses** were executed on both runtimes, at their declared
horizons and budgets. The two partial analysis declarations are not runnable
analyses and were excluded from this inventory.

### Component and profile analyses

| Analysis | Horizon | Result on both runtimes | Numerical comparison |
|---|---:|---|---|
| Networks.Tests.TestConductanceNetAnalysis | 1 s | Success | All 100 distinct named algebraic signals agree exactly at both saved times. |
| Networks.Tests.TestPowerLossNetAnalysis | 1 s | Success | All 78 distinct named algebraic signals agree exactly at both saved times. |
| Models.Tests.TestTNNModelAnalysis | 500 s | Success | Largest final-temperature change: 8.03e-9 °C. Adaptive intermediate time grids differ by up to 0.371 s, so intermediate rows are not compared directly. |
| Models.Tests.TestTNNProfileAnalysis | 2201 s | Success | 318 samples; largest temperature-state change below 1.3e-12 °C (time grids differ by at most 8.92e-11 s). |

### Story analyses: measured-temperature RMS error

Every free-running story solve returns `Success`. Channel order in the vectors
is permanent magnet, stator yoke, stator tooth, stator winding; units are °C.
The four shipped-calibration stories change by at most **0.001544 °C** in any
channel's RMS error between 3.4 and 3.5.

| Analysis | RMS error on 3.4 [°C] | RMS error on 3.5 [°C] | Largest absolute RMS change [°C] |
|---|---|---|---:|


| Story.A1_UntrainedTNN | 38.5428 / 16.5239 / 29.8358 / 40.966 | 38.5422 / 16.5232 / 29.8351 / 40.9654 | 0.000650508 |
| Story.A2_TrainTNNQuick | 35.7017 / 14.6733 / 27.5957 / 38.3032 | 35.6408 / 14.5077 / 27.5838 / 38.2572 | 0.1656002 |
| Story.A3_RetrainedTNN | 35.7017 / 14.6733 / 27.5957 / 38.3032 | 35.6408 / 14.5077 / 27.5838 / 38.2572 | 0.1656002 |
| Story.A4_CalibratedTNN | 0.58675 / 0.413855 / 0.355073 / 0.552871 | 0.586886 / 0.413469 / 0.354834 / 0.55268 | 0.0003852982 |
| Story.A5_CalibratedTNNProfile60 | 12.7686 / 15.2973 / 19.9263 / 26.23 | 12.7691 / 15.297 / 19.9264 / 26.2304 | 0.0004398879 |
| Story.A6_CalibratedTNNProfile62 | 7.29973 / 7.55846 / 9.83892 / 12.8142 | 7.3005 / 7.55884 / 9.8398 / 12.8153 | 0.001127068 |
| Story.A7_CalibratedTNNProfile74 | 17.2473 / 14.6276 / 20.6094 / 27.386 | 17.2479 / 14.6282 / 20.6088 / 27.3845 | 0.001543841 |

`A2_TrainTNNQuick` completes one augmented-Lagrangian outer iteration and two
Adam epochs: **six Adam steps**, 96 segments of 75 s, batch size 32 and block
size 4, with a 7200 s training horizon. Both runtimes return `ConvergenceFailure`
for this intentionally small budget; no convergence claim is made. The final
objective changes from 2.5492613347190995 to 2.553127837759142 (+0.003866503,
about +0.152%). Sampling is stochastic and unseeded; the quick-training error
change is not a deterministic regression metric. `A3_RetrainedTNN` successfully
loads each run's newly written parameters and reproduces its free-running
prediction. The shipped calibration and reference files remain untouched.

The validation driver writes training outputs into its selected output directory,
so neither these runs nor the baseline runs overwrite the committed fit.
The standalone `train_stochastic_ms.jl` short budget (360 steps) and full budget
(1500 steps), the PyTorch trainer, data preparation and animation rendering were
**not run**. All defined analyses, including quick training and every held-out
profile, were run; the existing 79-assertion test suite passed. No CSV or Parquet
measurement datasets were regenerated.

The `A4_CalibratedTNN` simulation plot artifact was also rendered and exported to
PNG with CairoMakie on 3.5; the optional Multibody render-extension failure does
not prevent this demo’s plot exporter from working.
