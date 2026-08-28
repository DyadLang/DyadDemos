# QuarterTruckSciML

End-to-end demo of two SciML workflows on a quarter-truck ride-comfort model:

1. **`NNTrainingAnalysis`** (DyadModelDiscovery) — train a neural network
   inside a gray-box model to recover three suspension nonlinearities (cubic
   tire stiffness with compression-only lift-off, tire-body Coulomb friction,
   seat-driver viscoelastic damping) from sin-excited training data, then
   validate against the nonlinear ground truth on a held-out ISO 8608 Class A
   road.

2. **`CalibrationAnalysis`** (DyadModelOptimizer) — recover four physical
   parameters (body mass, suspension stiffness, suspension damping, friction
   force) from time-series measurements of tire contact force, suspension
   travel and seat acceleration, with the same ISO 8608 excitation.

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

Set the JuliaHub juliaup env vars once per shell (not needed for the VS Code REPL command), then activate this project:

```bash
export JULIAUP_SERVER="https://juliahub.com/juliabin"
export JULIAUP_DEPOT_PATH="$HOME/.julia/juliaup-depots/juliahub.com"
cd QuarterTruckSciML
julia +dyad-3.3.0-rc2 --project -e 'using Pkg; Pkg.instantiate()'
```

### NN-augmented gray-box validation

The pre-trained LBFGS weights are checked in at `assets/data/nn_weights_full_sin_lbfgs.csv`,
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

The calibration recovers all four parameters to within ~0.1% of the perturbed
truth: `model.body_m` and `model.tire_to_body_c` essentially exactly, and
`model.tire_to_body_d` / `model.friction_Fc` to a fraction of a percent.

### Smoke tests

```bash
julia +dyad-3.3.0-rc2 --project -e 'using Pkg; Pkg.test()'
```

Verifies that the dyad library compiles, ISO 8608 helpers work, all three
ISO 8608 test harnesses simulate, and the pre-trained NN weights load and
produce a smaller error against the nonlinear truth than a zero-weight NN
would. Takes ~2 minutes including precompilation.
