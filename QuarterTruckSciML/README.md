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
julia +dyad-3.3.0-rc2 --project -e 'using Pkg; Pkg.instantiate()'
```

### NN-augmented gray-box validation

The pre-trained LBFGS weights are checked in at
`assets/data/nn_weights_full_sin_lbfgs.csv`,
so validation runs immediately:

```bash
julia +dyad-3.3.0-rc2 --project scripts/validate.jl              # → assets/validation_iso_a.png
julia +dyad-3.3.0-rc2 --project scripts/export_validation_csv.jl # → assets/validation_iso_a.csv
```

Expected output: 3-panel overlay (tire position, driver position, driver
acceleration) showing the NN-augmented model tracking the nonlinear truth
several times more accurately than the linear baseline.

To retrain from scratch (~5 min):

```bash
julia +dyad-3.3.0-rc2 --project scripts/generate_training_data.jl  # regenerate sin training set
julia +dyad-3.3.0-rc2 --project scripts/train.jl                   # Adam → LBFGS
```

### Parameter calibration

Generate synthetic measurements from the perturbed nonlinear truth (mass +5%,
stiffness +10%, damping +20%, friction +50%) and run the calibrator:

```bash
julia +dyad-3.3.0-rc2 --project scripts/generate_calibration_data.jl
julia +dyad-3.3.0-rc2 --project scripts/run_calibration.jl
```

The calibration recovers all four parameters to within ~0.1% of the truth:

| parameter              | nominal | truth |
|------------------------|---------|-------|
| `model.body_m`         | 300     | 315   |
| `model.tire_to_body_c` | 20e3    | 22e3  |
| `model.tire_to_body_d` | 1500    | 1800  |
| `model.friction_Fc`    | 500     | 750   |

### Smoke tests

```bash
julia +dyad-3.3.0-rc2 --project -e 'using Pkg; Pkg.test()'
```

Verifies that:

- the Dyad library compiles
- the ISO 8608 helpers work
- all three ISO 8608 test harnesses simulate
- the pre-trained NN weights load, and beat a zero-weight NN against the
  nonlinear truth

Takes ~2 minutes including precompilation.
