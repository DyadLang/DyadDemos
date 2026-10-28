# MotorTemperatureSciML convergence follow-up

Current target: Dyad **3.5.1**. Commands below use that channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Evidence paths and helper commands under `.task/` refer to the retained
validation workspace; those logs and investigation helpers are not shipped
with this repository. The demo entry points under `scripts/` are committed.


## Environment and scope

2026-10-26, Dyad 3.5.0-rc2 / Julia 1.13.2; original baseline Dyad
3.4.0 / Julia 1.12.7. Two Julia threads, one precompile task. Commands below
run from the workspace containing `DyadDemos/` and `.toolchain/`; outputs and
logs are under `.task/motor-followup/`, never the shipped calibration/data.
The baseline project is `.task/sciml/baseline/MotorTemperatureSciML`.

```sh
export JULIAUP_DEPOT_PATH="$PWD/.toolchain/juliaup"
export JULIAUP_SERVER=https://juliahub.com/juliabin
export JULIA_DEPOT_PATH="$PWD/.toolchain/depot"
export JULIA_NUM_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=1
export JULIA_PKG_PRECOMPILE_AUTO=0 JULIA_PKG_USE_CLI_GIT=true
export XDG_CACHE_HOME="$PWD/.task/motor-followup/cache"
JULIA="$PWD/.toolchain/juliaup/bin/julia"
PROJECT="$PWD/DyadDemos/MotorTemperatureSciML"
```

## Diagnosis

The old `A2_TrainTNNQuick` used six Adam updates (one outer iteration, two
passes of three batches) to fit 537 model parameters and 380 shooting initial
states over 7200 s. Its own documentation said this was too short for a fit.
An exhausted budget really is `ConvergenceFailure`: relabeling it a successful
pipeline check does not solve the constrained problem. The original baseline
reproduction returned `ConvergenceFailure`, maximum junction gap
**1.3927705643753314 °C** versus the unchanged **0.2 °C** requirement, optimizer
elapsed **115.511283762 s**, analysis wall time **230.490897 s** (94.39% reported
compilation). Training-horizon RMS errors were 36.3444 / 15.0229 / 28.2531 /
39.4677 °C; tail errors 27.4972 / 9.95547 / 19.3258 / 25.3614 °C. See
`baseline-retry.log`.

The original RC2 reproduction also returned `ConvergenceFailure`, maximum
junction gap **1.374997289424984 °C**, optimizer elapsed **81.472879308 s**,
analysis wall time **178.544417 s** (89.12% reported compilation).
Training-horizon RMS errors were 36.4394 / 15.1833 / 28.3179 / 39.5382 °C;
tail 27.6672 / 10.2392 / 19.4769 / 25.7851 °C. See `original-rc2.log`.
It used a task-local copy with `src/story_analyses.jl` restored from the
committed pre-follow-up version, not the edited source.

The replacement resolves measured `thermal.T` aliases to the integrated
`cond_net.T` states and orders state/data pairs by the actual ODE state order,
then seeds segment states from measured training temperatures
(`DataInitialization`); all four ODE states are measured. The initializer was
verified against all four channels at all 95 junctions: maximum error 0.0 °C.
A plain `DataInitialization()` change is insufficient: with observed aliases
it silently falls back to constant initial temperatures (with a warning), up
to 53.13800811767578 °C away from the measurements. Reversing canonical
state/data pairs exposes a separate library ordering bug, maximum error
17.267799377441406 °C. Both behaviors reproduce with identical numbers on
DMO 15.4.0 / Dyad 3.4 and DMO 15.5.1 / Dyad 3.5. See the
[draft upstream issue](followup-upstream-issues.md) for the complete reproducer.
Exploratory runs using the fallback initializer were interrupted and are not
reported as successful training. In the corrected problem the measured
segment initial states remain free optimization variables constrained by the
original continuity equations.
No held-out temperatures are used in training. Adam's initial 1e-3 normalized
state update is 0.2 °C, the same scale as the continuity criterion. A
constant-rate exploratory run plateaued near 0.25–0.35 °C for iterations 6–10,
then needed a penalty increase to reach 0.17950638142946174 °C at iteration 11
(396 updates, optimizer 1356.006819434 s, objective 0.005052860646635319).
The final setup retains 50 warm-up epochs and then decays the rate inversely
with epoch squared, down to a rate floor whose normalized-to-°C step scale is one tenth of the
requested junction tolerance. The applied rate is recorded in A2's `LossTable`. This changes the
optimizer, not the success threshold. Iteration budgets must be
sufficient to meet continuity; optimizer success alone still does not certify
predictive accuracy or first-order stationarity. Free-running solves and
holdout RMS errors are checked separately. Failed training cannot export a
calibration, and the validation driver fails on unsuccessful optimizer codes.
The schedule rejects nonpositive/nonfinite inputs, nonintegral windows and
uncovered training horizons instead of silently shortening the problem.

## Corrected training on both distributions

Same 7200 s training interval, 96 segments, batches of 32 in blocks of four,
Adam base rate 1e-3 with the documented decay, 12 epochs per outer iteration,
30 outer iterations maximum. **The physical continuity criterion stays
0.2 °C.** Both runs stopped on actual `Success`, with finite saved weights;
each saved file was reloaded by parameter name for all four full profiles.

| Runtime | Actual outer iterations / Adam updates | Optimizer elapsed s | Calibration call wall s | Max gap °C | Gap norm °C | Final objective |
|---|---:|---:|---:|---:|---:|---:|
| Dyad 3.4.0 | 8 / 288 | 1029.415715175 | 1036.367188 | 0.14842871116639844 | 0.8440794115974781 | 0.008497921997308056 |
| Dyad 3.5.0-rc2 | 10 / 360 | 1345.472618052 | 1351.902303 | 0.13451968407657278 | 0.6326411080174908 | 0.007513651537528113 |

Free-running RMS errors in °C, channel order magnet / yoke / tooth / winding:

| Data window | Dyad 3.4.0 | Dyad 3.5.0-rc2 |
|---|---|---|
| Profile 17, training | 3.550961 / 0.646339 / 0.591513 / 0.649004 | 3.330819 / 0.574148 / 0.499937 / 0.641705 |
| Profile 17, held-out tail | 1.271633 / 0.462827 / 0.498680 / 0.181714 | 1.350716 / 0.192841 / 0.251213 / 0.139620 |
| Profile 60, held out | 16.606107 / 16.453228 / 19.433663 / 25.673909 | 16.360787 / 16.405373 / 19.683046 / 25.707421 |
| Profile 62, held out | 12.157037 / 8.592893 / 10.074431 / 13.284511 | 11.910227 / 8.513956 / 10.092700 / 13.249896 |
| Profile 74, held out | 19.792021 / 16.667976 / 20.818331 / 27.715311 | 19.525114 / 16.596083 / 21.004614 / 27.701798 |

Every free-running solve returned `Success`; no resets at the 7200 s boundary.
The short fit improves the original six-update training errors substantially,
while its 8.5–27.8 °C unseen-profile errors remain a single-profile-training
limitation, comparable with the shipped fit. These are stochastic runs:
DMO derives segment sampler seeds from each experiment UUID, and threaded
adaptive solves also vary. They establish successful training on both
versions; timing or small RMS differences do not isolate a runtime regression.
Exact full-precision metrics and parameters are in `scheduled.log`,
`baseline-scheduled.log`, `scheduled/params.csv`, and
`baseline-scheduled/params.csv`.

The baseline used a task-local copy of the preserved original project with
only `src/story_analyses.jl` replaced by the corrected implementation. It kept
the original 3.4 manifest, generated constructor API and data. The RC2 project
uses the regenerated 3.5 code. No shipped weights were replaced.

## Builder story and A3 persistence

`story.jl --out-dir .task/motor-followup/story-scheduled` completed **A1–A7**
and exported **15 PNGs**, seven RMS tables, per-step/per-outer training tables,
and the new calibration CSV. The concrete `Story.A2_TrainTNNQuick` returned
`Success` after **9 outer iterations / 324 updates**, optimizer elapsed
**1210.1 s**, maximum junction gap **0.19840163756691398 °C**. Its recorded
learning rate goes from **0.001** to **0.00021433470507544583**; all recorded
losses, gradients and rates are finite. The training RMS is
3.313798339344169 / 0.6028294408144057 / 0.507753842093184 /
0.6552615305119441 °C; tail 1.2938106955821245 / 0.2670018319426271 /
0.3345252716263818 / 0.20214147806407584 °C.

**A3's reloaded prediction matches A2 exactly: maximum difference 0.0 °C**
over all four channels and 15,964 samples. Both analyses' complete RMS CSVs
are identical. This tests the regenerated Builder analyses and the standalone
story flow, in addition to the direct optimizer comparison above.

## Independent continuity and holdout checks

The actual story CSV was reloaded by `validate_calibration.jl` into a freshly
built problem. All four PNGs exported, with training RMS 3.31 / 0.60 / 0.51 /
0.66 °C, tail 1.29 / 0.27 / 0.33 / 0.20; holdout 60: 16.36 / 16.54 / 19.83 /
25.84; 62: 11.85 / 8.57 / 10.13 / 13.30; 74: 19.57 / 16.73 / 21.17 /
27.84 °C. Rebuilt continuity max 0.19740681168406438 °C, norm
0.9307538041606016 °C. See `quick-validation.log`.

After correcting the residual plot's channel order, reran this validator on
the same story file: all four PNGs exported, the same rounded RMS tables
were reproduced, and the independently rebuilt maximum gap was 0.1985 °C
(norm 0.9321 °C), still below 0.2 °C. See
`quick-channel-validation.log`. Adaptive solves on a freshly constructed
problem change residuals slightly; row permutation itself preserves maxima
and norms exactly.

A separate reference check rebuilt each inverse problem and recomputed all
380 constraints with both the production tolerance and **abstol=reltol=1e-9**.
All values were finite and every maximum stayed strictly below 0.2 °C:

| Saved weights/states | Max gap at 1e-6 [°C] | Max gap at 1e-9 [°C] | Norm at 1e-9 [°C] |
|---|---:|---:|---:|
| Actual RC2 story A2 | 0.19740681168406438 | 0.19847949444612434 | 0.9322888067121017 |
| Direct RC2 comparison | 0.13343375814411917 | 0.13199520220037453 | 0.6266866191020999 |
| Baseline-trained comparison | 0.14920649870808766 | 0.14931512317590823 | 0.840986182218292 |

This reference check used the RC2 runtime, including for the baseline-trained
file; it tests saved weights/states across a separately constructed problem
and a tighter ODE solve. See `precision-final.log`. Numerical reconstruction
changes the last few millikelvin of the residual; none is treated as zero or
hidden by rounding.

The baseline's concrete `Story.A3_RetrainedTNN` also loaded its new CSV on
Dyad 3.4, returned `Success`, produced finite predictions with maximum
absolute temperature 72.72334092262763 °C, and reproduced the baseline RMS
table above. Its first-use analysis wall time was 105.772537 s; see
`baseline-a3-retry.log`.

## Standalone workflow audit

- Python: task-local venv, torch 2.14.1+cpu, pandas 3.1.0, numpy 2.5.4,
  pyarrow 26.0.0. The authorized `download-r2.pytorch.org` retry succeeded.
  `python -m unittest discover -s "$PROJECT/test" -p 'test_*.py'`: **3/3 pass**,
  0.031 s for test execution. Full `train_pytorch_reference.py --threads 2
  --out-dir .task/motor-followup/pytorch`: **100 epochs, 2900 updates,
  229.2 s training**, final training loss 0.003050. Train RMS 0.71 / 4.25 /
  9.40 / 2.59 °C; tail 0.57 / 2.93 / 3.55 / 1.61. Holdout 60: 97.55 / 81.23 /
  121.03 / 128.97; 62: 178.36 / 147.31 / 232.03 / 232.53; 74: 160.42 / 132.42 /
  212.02 / 198.90 °C. This reproduces the documented reference's poor
  generalization; it is not a new Dyad defect. All four Parquet predictions
  were exported outside assets. They have matching row counts and exact
  timestamp grids; all values are finite. Largest differences from the
  shipped predictions are 1.5258789e-5 / 6.1035156e-5 / 9.1552734e-5 /
  9.1552734e-5 °C for profiles 17 / 60 / 62 / 74 (float32/thread effects).
- Data preparation: added `--out-dir`. The full original 69-profile source
  CSV is unavailable locally. Built a 79,868-row CSV fixture from the four
  shipped profiles, excluding derived fields; ran `prepare_data.jl --source
  .task/motor-followup/measures_subset.csv --out-dir .task/motor-followup/prepared`.
  All four full-length outputs passed independent Python checks of raw
  signal preservation, timestamps, subset max-abs denominators, and derived
  magnitudes (maximum discrepancy 2.220446049250313e-16). This validates the
  workflow, not provenance of the unavailable complete source dataset.
- `validate_calibration.jl` initially failed at `gr()` with `Package GR not
  found`. It now uses the already-declared CairoMakie backend, shared with
  Builder's plots, and checks each free-running ODE return code. All four
  PNGs now export headlessly. Shipped-fit train RMS: 0.61 / 0.41 / 0.37 /
  0.58 °C; tail: 0.23 / 0.46 / 0.25 / 0.17; holdout 60: 12.77 / 15.30 /
  19.93 / 26.23; 62: 7.30 / 7.56 / 9.84 / 12.82; 74: 17.25 / 14.63 / 20.61 /
  27.39 °C. Independently recomputed continuity max 0.1417 °C, norm 0.5799 °C,
  mean -0.0002339 °C. See `shipped-validation-cairo.log`. Fontconfig could not
  write its default host caches, but rendering succeeded; subsequent runs
  use a task-local `XDG_CACHE_HOME`.
- Julia tests after the optimizer change, regeneration and continuity-label
  audit: **103/103 pass**, including 14 schedule assertions, six initialization
  and channel-order checks covering all 380 shooting values, four checks of
  actual Optimisers updates/callback chaining, and the original 79 tests.
  The final audit also found that continuity plots labeled ODE-ordered
  residuals in measurement-channel order. Both Builder and standalone plots
  now reorder residual rows for their channel labels; residual maxima and
  norms, optimizer inputs and all convergence criteria are unchanged.
  Testset times: normalization 67.1 s, routing 3.3 s, interpolation 0.3 s,
  paths 0.2 s, schedule 0.2 s, initialization/order 11.7 s, rate adapter 0.5 s,
  transient 0.8 s. See `tests-channel-order.log`.
  Run: `"$JULIA" +dyad-3.5.0-rc2 --project="$PROJECT" "$PROJECT/test/runtests.jl"`.

## Standalone full-preset investigation

The default-optimization full-preset attempt did not reach a calibration
result: a SIGUSR1 sample showed LLVM's SLP vectorizer compiling the solver
call. An earlier factory run was interrupted after approximately 45 minutes;
the new sampled attempt was stopped after approximately three minutes.
The unsampled factory attempt's phase is unknown; buffering obscured its
progress. This does not establish a compiler defect or regression. See
the separate [compilation-cost investigation note](followup-upstream-issues.md).

A first `-O1` retry reached numerical constraint ODE solves and exposed 32
epochs in its buffered log, with finite losses decreasing from
3.68033780656473 to 0.06245229127527922. It was interrupted at **1783 s**
before a return code or calibration CSV existed (SIGTERM, followed by SIGKILL
when the process did not exit). This interrupted run is not a converged
calibration or a numerical `ConvergenceFailure` result.

The subsequent diagnostic run adds task-local epoch checkpoints and flushed
progress to the same standalone script. These snapshots are diagnostic state,
not exported calibration files. The production script now flushes its epoch
progress too. Compiler optimization and logging do not change the model,
training interval, budget, ODE tolerances, or 0.2 °C success criterion.

That diagnostic run also did not survive the factory resume. Its last
completed checkpoint is **epoch 514 / 1542 Adam updates**, **5902.036639928818 s**
after the checkpoint timer started immediately before calibration; last
mini-batch objective **0.0025421011071030553**, learning rate **0.0001**.
Five 100-epoch outer iterations completed; the sixth was in progress. On
resume the process and harness session were absent, the log ended at that
checkpoint, and the output directory contained **no calibration CSV**. There
is no final optimizer return code. This is an externally interrupted run,
not a completed full-preset validation or a numerical `ConvergenceFailure`.
No calibration was exported from its diagnostic snapshots.

Independent checks of four intermediate checkpoints and the last available
checkpoint establish that these are finite, physically sensible optimization
states; none meets the continuity criterion:

| Adam update | Checkpoint elapsed s | Max gap °C | Gap norm °C | Independent residual-call s | Full-profile temperatures °C |
|---|---:|---:|---:|---:|---|
| 102 | 372.569650888443 | 1.51303967025756 | 13.294224922285805 | 3.652325993 | 18.2932186126709–64.65379404291444 |
| 318 | 1173.3730709552765 | 1.4394530099181735 | 4.338610987881391 | 3.622687511 | 18.2932186126709–68.41878752594279 |
| 618 | 2343.067214012146 | 0.236705315338126 | 1.193567044920428 | 3.784080549 | 18.2932186126709–71.90604382444045 |
| 915 | 3518.2456529140472 | 0.37609568264662663 | 1.0870901347742847 | 3.569359278 | 18.2932186126709–73.09356101906099 |
| 1542 (last available) | 5902.036639928818 | 0.21330417203487828 | 0.8232354508508847 | 2.700189623 | 18.2932186126709–73.47330785367843 |

All five full-profile ODE solves returned `Success`, with finite predictions.
Log-capacitances remained near -5, and shooting temperatures stayed between
21.388101280227396 and 73.35691535652934 °C. See `inspect-checkpoint.log`,
`inspect-outer2.log`, `inspect-outer3.log`, `inspect-outer4.log`, and
`inspect-final-interrupted.log`. Update 915 improves the norm but worsens the
maximum gap relative to update 618, illustrating why norm reduction alone
does not meet the unchanged maximum-gap stopping criterion. The last available
checkpoint remains above 0.2 °C; its finite weights and successful free-running
solve do not establish continuity feasibility or optimizer convergence.
These checks do not identify the cause of the earlier buffered run's lack of
visible progress, and do not turn its interruption into a library-defect claim.

## Animation audit

Ran the real fixed-budget diagnostic with its **original 24 × 300 s segments,
batch size eight, 10 × 33 epochs = 990 Adam updates**, and its **unchanged
artificial 1e-8 normalized stopping threshold (0.000002 °C)**. That threshold
was designed to prevent early stopping; it is not a calibration acceptance
requirement. It finished in
**2305.5 s** and returned **`ConvergenceFailure`**. The final reconstructed
maximum gap was **0.06310550081657595 °C**, far above that artificial threshold.
This is a fixed-budget diagnostic trajectory; it is **not** counted as
successful calibration. The threshold lies below the configured 1e-6 ODE
tolerance, and the finite stochastic-update scale also limits junction
refinement. The raw return code and numerical threshold remain visible.

Both GIFs and both final PNGs exported headlessly. The return code, final gap
and original criterion appear on both figures. Limited stored frames to three
with `TNN_ANIMATION_MAX_FRAMES=3 TNN_ANIMATION_CAPTURE_EVERY=100`; this changes
capture/render work only, not the 990-step training problem. FFprobe verified
**three frames, 0.38 s** for each GIF, with resolutions **1800 × 1320** and
**3000 × 2080**. The default up-to-120-frame movie was not rendered.

Replayed the actual cached training through the latest script, including its
final-snapshot check; both GIFs/PNGs exported again. Rebuilt final gap
**0.06158862698167411 °C**, same `ConvergenceFailure`. See
`animation-scheduled.log`, `animation-cache-replay.log`, `video-metadata.log`
and `animation-scheduled/`.

A separate render-only fixture also exercised the same rendering code and
exported both GIFs/PNGs, explicitly labeled `NotRun (render fixture)`; it was
not used as training evidence. The script now preserves the final optimizer
snapshot, counts steps across outer iterations, checks segment ODE return
codes, and uses a symmetric-log plot for augmented objectives that can be
negative (observed minimum -0.016335245674401283 in the real A2 step table).
Older caches without a matching final snapshot require `FORCE_RETRAIN=1`.

## Other analysis and failure checks

The nine non-training analyses were rerun after regeneration. All returned
`Success`, with finite trajectories. Elapsed times (including first-use
compilation where applicable):

| Analysis | elapsed s |
|---|---:|
| Networks.Tests.TestConductanceNetAnalysis | 62.785056829452515 |
| Networks.Tests.TestPowerLossNetAnalysis | 4.7162559032440186 |
| Models.Tests.TestTNNModelAnalysis | 5.98114800453186 |
| Models.Tests.TestTNNProfileAnalysis | 7.55295205116272 |
| Story.A1_UntrainedTNN | 12.17240595817566 |
| Story.A4_CalibratedTNN | 5.315237045288086 |
| Story.A5_CalibratedTNNProfile60 | 0.3329911231994629 |
| Story.A6_CalibratedTNNProfile62 | 0.4985489845275879 |
| Story.A7_CalibratedTNNProfile74 | 0.6412498950958252 |

See `analyses.log` and `analyses/*.txt` / `*-states.tsv`. The final learning-rate
change only affects training callbacks, not these component/free-run analyses.

The six-update negative-path check explicitly overrides A2's new budget with
`inner_epochs=2, outer_maxiters=1`. It returned `ConvergenceFailure`, elapsed
81.6 s, independently recomputed gap 20.007370456365603 °C, threw an error
containing the return code and gap, and did **not** create the requested CSV.
This check validates failure handling; it is not counted as converged training.

The exploratory constant-rate converged fit independently reloaded through
`validate_calibration.jl`: training RMS 2.56 / 0.70 / 0.76 / 0.94 °C, tail
0.95 / 0.19 / 0.47 / 0.36; holdout 60: 15.59 / 16.51 / 19.80 / 25.84; 62:
11.29 / 8.57 / 10.10 / 13.30; 74: 18.83 / 16.64 / 21.04 / 27.69 °C.
The rebuilt shooting residual max was 0.1819 °C (norm 1.326 °C); this small
difference from the optimizer's 0.1795 °C reflects independent adaptive solves.
All four PNGs exported. See `constant-rate-validation.log`. The task-local
prototype's first holdout loop had a Julia parse error after saving that fit;
this was corrected before final runs, and the independent validator supplied
these accuracy/residual results. It is not a demo-source failure.

## Compiler

Regenerated with the exact RC2 compiler:
`3.5.0-rc2 (a24a224; compiler-only source build)`. The generated A2 and partial
training-analysis defaults now match the source schedule. No manual generated
code patch is required.

```sh
export JULIA_EXECUTABLE="$JULIA +dyad-3.5.1"
.toolchain/compiler-build/dyad compile "$PROJECT"
```

## Commands for the completed checks

Use the environment block at the top of this report. The task-local baseline
copies and helper drivers are retained in the shared workspace.

```sh
# Original pre-upgrade baseline; the helper's MOTOR_ORIGINAL branch calls A2.
MOTOR_ORIGINAL=1 "$JULIA" +dyad-3.4.0 \
  --project="$PWD/.task/sciml/baseline/MotorTemperatureSciML" \
  .task/motor-followup/probe.jl .task/motor-followup/baseline
MOTOR_ORIGINAL=1 "$JULIA" +dyad-3.5.0-rc2 \
  --project="$PWD/.task/motor-followup/original-rc2" \
  .task/motor-followup/probe.jl .task/motor-followup/original-rc2-output

# Corrected problem on both distributions (12 epochs x 30 outer maximum).
"$JULIA" +dyad-3.4.0 --project="$PWD/.task/motor-followup/baseline-fixed" \
  .task/motor-followup/probe.jl .task/motor-followup/baseline-scheduled
"$JULIA" +dyad-3.5.0-rc2 --project="$PROJECT" \
  .task/motor-followup/probe.jl .task/motor-followup/scheduled

# All seven concrete story analyses, real training and A3 reload, all plot artifacts.
"$JULIA" +dyad-3.5.0-rc2 --project="$PROJECT" \
  "$PROJECT/scripts/story.jl" --out-dir .task/motor-followup/story-scheduled
"$JULIA" +dyad-3.5.0-rc2 --project="$PROJECT" \
  "$PROJECT/scripts/validate_calibration.jl" \
  --calibration .task/motor-followup/story-scheduled/calibrated_params.csv \
  --out-dir .task/motor-followup/quick-validation

# Tighter independent constraint check on all three saved fits.
"$JULIA" +dyad-3.5.0-rc2 --project="$PROJECT" \
  .task/motor-followup/check-precision.jl \
  .task/motor-followup/story-scheduled/calibrated_params.csv \
  .task/motor-followup/scheduled/params.csv \
  .task/motor-followup/baseline-scheduled/params.csv

# Nine remaining concrete analyses; A2/A3 are covered by the story above.
DYAD_UPGRADE_OUTPUT="$PWD/.task/motor-followup/analyses" \
DYAD_UPGRADE_ONLY="Networks.Tests.TestConductanceNetAnalysis,Networks.Tests.TestPowerLossNetAnalysis,Models.Tests.TestTNNModelAnalysis,Models.Tests.TestTNNProfileAnalysis,Story.A1_UntrainedTNN,Story.A4_CalibratedTNN,Story.A5_CalibratedTNNProfile60,Story.A6_CalibratedTNNProfile62,Story.A7_CalibratedTNNProfile74" \
  "$JULIA" +dyad-3.5.0-rc2 --project="$PROJECT" "$PROJECT/scripts/validate_upgrade.jl"

# Data fixture and the six-update failure/no-export check.
"$JULIA" +dyad-3.5.0-rc2 --project="$PROJECT" "$PROJECT/scripts/prepare_data.jl" \
  --source .task/motor-followup/measures_subset.csv --out-dir .task/motor-followup/prepared
"$JULIA" +dyad-3.5.0-rc2 --project="$PROJECT" .task/motor-followup/check-failure.jl

# Full diagnostic animation budget; three captured frames, unchanged threshold.
TNN_ANIMATION_MAX_FRAMES=3 TNN_ANIMATION_CAPTURE_EVERY=100 \
  "$JULIA" +dyad-3.5.0-rc2 --project="$PROJECT" \
  "$PROJECT/scripts/animate_sms_training.jl" --out-dir .task/motor-followup/animation-scheduled
# Repeat the command to test replay from its real cache; FORCE_RETRAIN=1 retrains.

# Standalone full preset: interrupted, no completed calibration claim.
# The task-local helper runs this same production script with additional
# checkpoint serialization and flushed progress only.
TNN_BUDGET=full "$JULIA" +dyad-3.5.0-rc2 -O1 --project="$PROJECT" \
  .task/motor-followup/full-checkpoint.jl --out-dir .task/motor-followup/full-checkpoint
# Independent check of the retained final diagnostic snapshot (not a calibration).
"$JULIA" +dyad-3.5.0-rc2 -O1 --project="$PROJECT" \
  .task/motor-followup/inspect-checkpoint.jl \
  .task/motor-followup/checkpoint-final-interrupted.bin

# Python reference in the task-local venv.
.task/motor-followup/venv/bin/python -m unittest discover -s "$PROJECT/test" -p 'test_*.py'
.task/motor-followup/venv/bin/python "$PROJECT/scripts/train_pytorch_reference.py" \
  --threads 2 --out-dir .task/motor-followup/pytorch
```

## Limits

Timing includes competing foreground validation processes and compilation;
it is not a framework benchmark. One profile is insufficient evidence of
production generalization. The PyTorch reference deliberately follows the
published notebook's single-profile restriction used in this demo; its large
holdout errors are reported unchanged.

The standalone `short` preset (50 epochs per outer iteration) was not run
as a separate calibration; the real quick/Builder fits and the full-preset
investigation exercise the shared implementation at different budgets.
The full-preset checks use `-O1`; the interrupted default-optimization runs
provide no completed full-preset result at the default compiler setting.
