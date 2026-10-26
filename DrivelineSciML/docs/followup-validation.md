# Calibration follow-up validation (2026-10-26)

Stage 1 now genuinely converges on both Dyad 3.4 and 3.5 by setting
`dtmax = 0.0001` seconds. The chained Stage 2 also needs `dtmax = 0.001`
seconds. Both settings are declared in `dyad/calibration.dyad` and regenerated
using compiler `3.5.0-rc2 (a24a224; compiler-only source build)`, followed by
`scripts/fix_analysis_codegen.jl`. No model equations, measurements, guesses,
bounds, loss functions, tolerances, horizons, or iteration budgets changed.

## Diagnosis and original baseline

Fresh runs of the preserved original project in
`.task/sciml/baseline/DrivelineSciML` under `+dyad-3.4.0` reproduced the failure.
This is a pre-existing numerical configuration issue, not a 3.5 regression.
The original CSVs were read and compared byte-for-byte with the preserved
baseline; neither was regenerated. Their SHA256 checksums are:

```
chirp_measurements.csv       abc0c70ff1b3e183bd62136ea414f58d0d091d465acb2a53f9fca871fd89174d
slow_cycle_measurements.csv  a05581c27e117a52739bccb62c3cd445e39cf5cd4b890a585a02ffd4a24a47ff
```

| Original Stage 1 | Return | k1 | c1 | alpha | L2 objective | Call time including compilation |
|---|---|---:|---:|---:|---:|---:|
| 3.4 | Infeasible | 293.84112154029486 | 1.02312706428496 | 46.77750128342999 | 0.09598595522912254 | 54.269797 s |
| 3.5 | Infeasible | 293.81493088067236 | 1.023115603609219 | 46.77444876683099 | 0.09598692792772814 | 47.718425 s |

The raw optimizer termination is `SEARCH_DIRECTION_BECOMES_TOO_SMALL`.
A separate 3.5 failure-path run measured primal residual 0 and dual residual
0.006184987925908159 after 35 iterations, then exited unsuccessfully through
the new workflow guard. `likely_wrong=false` alone is not evidence of success.

The chirp reaches a 2 ms period. Limiting the ODE step to 0.1 ms resolves each
cycle with at least 20 steps. Adaptive integration with accurate saved states
can still produce a loss too noisy for reliable line searches. Tightening
`abstol`/`reltol` alone to 1e-10 or 1e-11 still returned `Infeasible`; replacing
L2 with squared L2 also failed. These experiments were diagnostic only and are
not part of the fix. Switching to LBFGS reported success through a zero-change
stopping condition despite a 0.00543 gradient measure; that alternative was
rejected. The original optimizer and its 1e-4 tolerance remain in use.

## Step refinement and residual evidence

Both stages retain Tsit5, `abstol = reltol = 1e-8`, the original sample grids,
and the 400/300 iteration budgets. All successful cases below report raw
`SOLVE_SUCCEEDED`, not merely the wrapper's `Success`.

| Stage 1 run | k1 | c1 | alpha | L2 objective | Dual residual | Call time |
|---|---:|---:|---:|---:|---:|---:|
| 3.4, 0.1 ms | 293.83226122171067 | 1.0231046787864173 | 46.77716727643784 | 0.09600305043849605 | 2.4400304500586906e-6 | 56.292673203 s |
| 3.5, 0.1 ms | 293.83226102568574 | 1.023104679062793 | 46.77716723466644 | 0.0960030501706517 | 2.4543631786180924e-6 | 50.677188264 s |
| 3.4, 0.05 ms | 293.8322011107499 | 1.0231047948252932 | 46.77714706293129 | 0.09600332369648401 | 1.5961523726628575e-5 | 4.996118834 s |
| 3.5, 0.05 ms | 293.83220108141353 | 1.0231047948975638 | 46.777147056452506 | 0.09600332375955735 | 1.5988595188040228e-5 | 5.250860903 s |

All primal residuals are zero. The 0.1 ms runs take 25 optimizer iterations;
the 0.05 ms runs take 22. First calls include compilation, subsequent calls
reuse it. These are wall times on the shared worker, not performance benchmarks.
The 3.5 chirp residual RMSE is 0.0013575524073515513 rad/s over 5001 points;
halving the step changes it by 3.87e-9 rad/s and changes k1 by 0.00005995.
With the step cap and stricter 1e-10 ODE tolerances, both runtimes also succeed
(3.5 objective 0.09600325742679147, dual residual 5.321182577885498e-5).
Finite-difference derivatives still have a small integration noise floor;
these results establish convergence at the declared tolerance, not exact
parameter recovery or arbitrarily precise gradients.

The corrected Stage 1 fit freezes a Maxwell relaxation of 3.481934473401329 ms
in Stage 2. Its previously unrestricted solve then returned `Infeasible`
(objective 0.012995865426053594, dual residual 0.000166322). The strict guard
caught this and prevented the chained workflow from exporting a failed fit.
A 1 ms cap resolves this faster internal dynamics even though the applied
slow-cycle torque is only 1 Hz.

| Chained Stage 2 cap | alpha | beta | gamma | L2 objective | Dual residual | Call time |
|---|---:|---:|---:|---:|---:|---:|
| 1 ms | 49.627415992747494 | 4.9699700868123 | 0.4436686884389184 | 0.012996074748171537 | 6.624131691823909e-5 | 41.502974176 s |
| 0.5 ms | 49.62486605270218 | 4.970049292791823 | 0.4430479461755128 | 0.012996347463392038 | 4.892851007151267e-5 | 0.463848990 s |
| 0.1 ms | 49.627086133580086 | 4.969902501098953 | 0.44371409328828704 | 0.012996277956290242 | 8.784313923589581e-6 | 1.361678023 s |

All primal residuals are zero; iteration counts are 16, 12, and 14. The 1 ms
fit's training residual RMSE is 0.00041076663646215405 rad/s over 1001 points.
Its predicted saturation torque is 9.985455671943114 Nm versus 10 Nm truth.

Stage 1 deliberately fixes beta/gamma at their nominal values, so its best
three-parameter fit is biased relative to the six-parameter truth. Stage 2
inherits the small Maxwell bias; gamma remains about 11.27% below truth.
The identifiability diagnostic now explicitly distinguishes this mismatch
from optimizer convergence instead of claiming that lower loss than truth
proves the optimizer succeeded. Standalone Stage 2 uses nominal Maxwell
parameters and is not the final chained scientific fit.

## Workflow audit

`run_calibration.jl` checks each optimizer status, finite parameters/objective,
and `likely_wrong` before chaining or writing the parameter CSV.
`diagnose_calibration.jl` prints both layers of evidence and rejects failed
fits before continuing. `validate_upgrade.jl` records failures and exits
unsuccessfully for non-success optimizer statuses; it also rejects unknown
analysis selections and no longer swallows unexpected raw-solution errors.
Simulation workflows check successful return status, final time, and finite
states before exporting data or comparing predictions. Held-out validation
also requires every calibrated observable to improve over the linear baseline.
Regression tests cover rejected statuses and invalid results, as well as both
full-budget calibration stages and their training residuals.

## Final 3.5 checks and held-out accuracy

The final regenerated project passes **27/27 assertions** through `Pkg.test()`;
the timed Pkg call took 191.003990 seconds. The two-stage numerical regression
accounts for four assertions and took 97.0 seconds including compilation.
All seven declared analyses pass the stricter upgrade validator at their
original horizons and budgets:

| Analysis | Status | Saved samples / horizon | Driver time |
|---|---|---|---:|
| TestTipInTorqueTransient | Success | 4001 / 2 s | 8.363629103 s |
| TestDrivelineChirpTransient | Success | 5001 / 5 s | 2.490213871 s |
| TestDrivelineChirpMaxwellOnlyTransient | Success | 5001 / 5 s | 0.174213886 s |
| TestDrivelineSlowCycleTransient | Success | 1001 / 5 s | 1.222735167 s |
| TestDrivelineTipInTransient | Success | 4001 / 2 s | 0.893843174 s |
| DrivelineStage1CalibrationAnalysis | Success | 5001 measurements / 5 s | 45.822075129 s |
| DrivelineStage2CalibrationAnalysis | Success | 1001 measurements / 5 s | 36.043709993 s |

Standalone Stage 2 returns `[41.27946238373415, 3.3939687271136365,
0.05126855733513879]`, objective 0.39605148405164603, with its nominal fixed
Maxwell branch. The chained workflow uses the fitted branch instead and
returns the 1 ms Stage 2 values in the refinement table above. Both optimizer
statuses are `Success`, with raw `SOLVE_SUCCEEDED` confirmed by the final
diagnostic driver. Its primal/dual residuals are respectively
`0 / 2.45436e-6` (Stage 1) and `0 / 6.62413e-5` (Stage 2), below the original
1e-4 optimizer tolerance. No fit is exported from a failed optimizer run.

`run_calibration.jl` took 172.474571 seconds including compilation in a fresh
process. `validate.jl` then took 13.870126 seconds in that process, successfully
ran all three tip-in simulations to 2 s (4001 points), and wrote the ignored
`assets/validation_tipin.png` plot. The unseen tip-in was not used for fitting:

| Observable | Linear baseline RMSE | Calibrated RMSE | Reduction |
|---|---:|---:|---:|
| Engine speed (rad/s) | 0.5234271416 | 0.004489382271 | 99.142310% |
| Speed difference (rad/s) | 0.6542660387 | 0.005611571803 | 99.142310% |
| Isolator twist (rad) | 0.01072790856 | 0.00009128519010 | 99.149087% |

The successful standalone, chained, diagnostic, and held-out drivers all ran
against the final generated code. Final logs are `tests-complete.log`,
`all-analyses-final.log`, `chained-heldout-final.log`, and `diagnose-final.log`
under `.task/driveline-followup/`. The earlier chain failure is retained in
`chained-heldout.log`, so the caught Stage 2 nonconvergence is auditable.

## Reproduction commands

Run from the factory workspace root (the directory containing `DyadDemos`,
`.task`, and `.toolchain`):

```sh
export JULIAUP_DEPOT_PATH="$PWD/.toolchain/juliaup"
export JULIAUP_SERVER=https://juliahub.com/juliabin
export JULIA_DEPOT_PATH="$PWD/.toolchain/depot"
export JULIA_NUM_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=1
export JULIA_PKG_PRECOMPILE_AUTO=0 JULIA_PKG_USE_CLI_GIT=true
export JULIA_EXECUTABLE="$PWD/.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2"
export DRIVELINE_PROJECT="$PWD/DyadDemos/DrivelineSciML"
.toolchain/compiler-build/dyad compile "$DRIVELINE_PROJECT"
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project="$DRIVELINE_PROJECT" "$DRIVELINE_PROJECT/scripts/fix_analysis_codegen.jl"
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project="$DRIVELINE_PROJECT" -e 'using Pkg; @time Pkg.test()'
export DYAD_UPGRADE_OUTPUT="$PWD/.task/driveline-followup/all-analyses-final"
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project="$DRIVELINE_PROJECT" "$DRIVELINE_PROJECT/scripts/validate_upgrade.jl"
export GKSwstype=100
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project="$DRIVELINE_PROJECT" -e '@time include("DyadDemos/DrivelineSciML/scripts/run_calibration.jl"); @time include("DyadDemos/DrivelineSciML/scripts/validate.jl")'
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project="$DRIVELINE_PROJECT" "$DRIVELINE_PROJECT/scripts/diagnose_calibration.jl"
```

Original baseline command (the preserved project is not modified):

```sh
.toolchain/juliaup/bin/julia +dyad-3.4.0 --project="$PWD/.task/sciml/baseline/DrivelineSciML" -e 'using DrivelineSciML; @time r=DrivelineStage1CalibrationAnalysis(optimizer_verbose=true); println(r.r.retcode); println(r.r.original); println(r.r.u)'
```

The same baseline command with the upgraded project and `+dyad-3.5.0-rc2`
requires `dtmax=0` to reproduce the original configuration after this fix.
Investigation drivers and complete logs are preserved in
`.task/driveline-followup/`: `refine.jl` (run against both projects/runtimes),
`stage2-probe.jl`, `probe.jl`, `loss-probe.jl`, and `reject-unresolved.jl`.
For example, the refinement commands actually used were:

```sh
.toolchain/juliaup/bin/julia +dyad-3.4.0 --project="$PWD/.task/sciml/baseline/DrivelineSciML" .task/driveline-followup/refine.jl
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project="$DRIVELINE_PROJECT" .task/driveline-followup/refine.jl
.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2 --project="$DRIVELINE_PROJECT" .task/driveline-followup/stage2-probe.jl
```

Failure-path checks `reject-unresolved.jl` and
`DYAD_UPGRADE_ONLY=does-not-exist ... scripts/validate_upgrade.jl` both exited
with code 1 as intended. No hosted CI result is claimed.
