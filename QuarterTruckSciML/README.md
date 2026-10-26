# QuarterTruckSciML

A quarter truck is one wheel and the mass it carries — the smallest model that
still predicts how rough a road feels to the person in the seat. Its
hand-written
equations are only approximately right, and this demo shows two ways of closing
the gap with data.

**1. Learn the missing physics** — `NNTrainingAnalysis` (DyadModelDiscovery).
A neural network sits inside the model and learns three effects the equations
leave out:

- the tire stiffening as it squashes, and going slack when the wheel lifts off
- the tire and body sticking before they slide
- the seat cushion resisting fast motion more than a plain damper would

It trains on data from shaking the truck with a sine wave, then is checked
against the true nonlinear truck on a road it never saw: ISO 8608 Class A, a
standard smooth-highway roughness profile.

**2. Recover the numbers** — `CalibrationAnalysis` (DyadModelOptimizer).
From recordings of tire contact force, suspension travel, and seat acceleration
on that same road, the calibrator works backwards to the four values that
produced them:

- body mass
- suspension stiffness
- suspension damping
- friction force

## Layout

| Path                                  | What                                                     |
|---------------------------------------|----------------------------------------------------------|
| `dyad/road_signals.dyad`              | `HalfSineBump`, `ISO8608Road`, `DenseISO8608Road`        |
| `dyad/truck_model.dyad`               | `QuarterTruckConfigurable` + custom components           |
| `dyad/truck_full_nn.dyad`             | `QuarterTruckFullNN` gray-box + ISO 8608 test harnesses  |
| `dyad/nn_analyses.dyad`               | Adam + LBFGS NN training analyses                        |
| `dyad/calibration.dyad`               | Calibration harness + `CalibrationAnalysis`              |
| `src/QuarterTruckSciML.jl`            | ISO 8608 spectrum helpers (Julia)                        |
| `scripts/generate_training_data.jl`   | Produce `assets/data/truck_sin_full_train.csv`           |
| `scripts/train.jl`                    | Run Adam + LBFGS to retrain the NN                       |
| `scripts/evaluate_training_fit.jl`    | Replay exported NN weights against all training samples |
| `scripts/validate.jl`                 | 3-panel overlay PNG (linear / NN / truth) on ISO 8608    |
| `scripts/export_validation_csv.jl`    | Same data as `validate.jl` but as a tidy CSV             |
| `scripts/generate_calibration_data.jl`| Simulate perturbed truth → synthetic measurements        |
| `scripts/run_calibration.jl`          | Run `CalibrationAnalysis`, print recovered vs. truth     |
| `assets/data/`                        | Pre-trained NN weights + cached training/measurement CSVs|

## Running the demo

Set the JuliaHub juliaup env vars once per shell (not needed for the VS Code
REPL command), then activate this project:

```bash
export JULIAUP_SERVER="https://juliahub.com/juliabin"
export JULIAUP_DEPOT_PATH="$HOME/.julia/juliaup-depots/juliahub.com"
cd QuarterTruckSciML
julia +dyad-3.5.0-rc2 --project -e 'using Pkg; Pkg.instantiate()'
```

### Recompiling with Dyad Studio or CLI

**Every Dyad Studio recompile, including compile on save, requires rerunning
`scripts/fix_analysis_codegen.jl` before loading the project again.** The same
applies after every CLI compile:

```bash
dyad compile .  # use the 3.5.0-rc2 compiler
julia +dyad-3.5.0-rc2 --project scripts/fix_analysis_codegen.jl
```

The rc2 compiler emits `@parameters (data::DyadData.DyadTimeseries)`, whose
`UnionAll` type causes a `MethodError` converting to `DataType` when constructing
the calibration analysis and both NN training analyses. The script changes only
that annotation to
`typeof(__local__data)`, preserving compiler whitespace. See the matching
[upstream compiler issue #1958](https://github.com/JuliaComputing/dyad-lang/issues/1958).
Keep the workaround until regeneration and the analysis construction tests pass
without it on a compiler containing an upstream fix.

The affected compiler is tag `v3.5.0-rc2`, commit
`a24a2240667872d432a3b86c4db1240d77150e35`. A reproduction from this project
directory, with a fresh Julia process and deliberately before applying the fix:

```bash
../.ci/compiler/dyad compile .
julia +dyad-3.5.0-rc2 --project -e 'using QuarterTruckSciML; QuarterTruckSciML.QuarterTruckCalibrationAnalysis__Spec()'
```

This fails with `Cannot convert an object of type Type{DyadData.DyadTimeseries}
to an object of type DataType`. Run the fix script before retrying. The tests
construct every affected analysis without running calibration or training.

### NN-augmented gray-box validation

The pre-trained LBFGS weights are checked in at
`assets/data/nn_weights_full_sin_lbfgs.csv`,
so validation runs immediately:

```bash
julia +dyad-3.5.0-rc2 --project scripts/validate.jl              # → assets/validation_iso_a.png
julia +dyad-3.5.0-rc2 --project scripts/export_validation_csv.jl # → assets/validation_iso_a.csv
```

Expected output: 3-panel overlay (tire position, driver position, driver
acceleration) showing the NN-augmented model tracking the nonlinear truth
several times more accurately than the linear baseline.

To retrain from scratch at the declared 5000 Adam / 200 LBFGS budgets
(runtime depends on the machine and backend; see the measured follow-up report):

```bash
julia +dyad-3.5.0-rc2 --project scripts/train.jl /path/to/fresh-training-output  # Adam → LBFGS
```

The training script preserves the committed dataset and pretrained weights. It
records actual optimizer return codes, losses and timings in `training-results.txt`
and writes `adam_weights.csv` / `lbfgs_weights.csv` in the output directory.
The measured RC2 full run took 82 min 38.64 s, with Adam completing all 5000
iterations and LBFGS converging after two iterations within its 200-iteration
limit; see the [follow-up report](docs/followup-validation.md) for exact statuses
and fit limitations.
Direct analysis exports default to the ignored `training-results/` directory,
with LBFGS reading Adam's checkpoint there.
Adam may return `Default` after its full budget; the script reports this without
claiming convergence and requires successful LBFGS refinement. To evaluate the
new fit against the training samples and on the held-out road:

```bash
julia +dyad-3.5.0-rc2 --project scripts/evaluate_training_fit.jl /path/to/fresh-training-output/lbfgs_weights.csv
QUARTERTRUCK_WEIGHTS=/path/to/fresh-training-output/lbfgs_weights.csv \
QUARTERTRUCK_VALIDATION_OUTPUT=/path/to/validation-output \
julia +dyad-3.5.0-rc2 --project scripts/validate.jl
```

The validation output directory receives a PNG and
`validation_iso_a_metrics.csv` with full-precision errors.

Regenerate `assets/data/truck_sin_full_train.csv` only deliberately with
`scripts/generate_training_data.jl`; an optional output filename keeps the
committed dataset untouched.

### Parameter calibration

Run the calibrator against the committed synthetic measurements from the
perturbed nonlinear truth (mass +5%, stiffness +10%, damping +20%, friction +50%):

```bash
julia +dyad-3.5.0-rc2 --project scripts/run_calibration.jl
```

The calibration uses squared residuals and a strict optimizer tolerance to recover
all four parameters within 0.1% of truth and return `Success` in 43 iterations on
RC2. The weak damping/friction distinction makes a loose stopping tolerance
inadequate. See [follow-up validation](docs/followup-validation.md) for residuals
and limitations. To deliberately regenerate the synthetic measurements, use
`scripts/generate_calibration_data.jl`; an optional output filename preserves
the committed file. The generator checks integration success and uses explicit
`1e-10` solver tolerances.

The ground-truth parameters are:

| parameter              | nominal | truth |
|------------------------|---------|-------|
| `model.body_m`         | 300     | 315   |
| `model.tire_to_body_c` | 20e3    | 22e3  |
| `model.tire_to_body_d` | 1500    | 1800  |
| `model.friction_Fc`    | 500     | 750   |

### Smoke tests

```bash
julia +dyad-3.5.0-rc2 --project -e 'using Pkg; Pkg.test()'
```

Verifies that:

- the Dyad library compiles
- the ISO 8608 helpers work
- all three ISO 8608 test harnesses simulate
- the pre-trained NN weights load, and beat a zero-weight NN against the
  nonlinear truth
- physical calibration returns success and recovers the synthetic parameters
  within 0.1%

The follow-up validation records measured test-set times, including the full
physical-calibration regression.

## Dyad 3.5 validation

See [the upgrade validation report](docs/upgrade-3.5-validation.md) for the
full analysis inventory, old/new numerical comparisons, and regeneration steps.
See also [follow-up validation](docs/followup-validation.md) and
[unfiled upstream issue drafts](docs/followup-upstream-issues.md).
Follow the [recompile workflow](#recompiling-with-dyad-studio-or-cli) after
every Studio or CLI compile to reapply the required annotation workaround.
