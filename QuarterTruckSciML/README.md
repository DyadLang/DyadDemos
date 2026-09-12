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
| `dyad/Story/`                        | Ordered custom analyses for presenting the NN story      |
| `dyad/Story/definitions.jl`          | Story execution and CairoMakie plot artifacts             |
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

### Presenting the NN story

The `QuarterTruckSciML.Story` submodule asks how we can predict a car's response
to a rough road well enough to tune its springs or design better suspension
controls. The linear equations miss nonlinear suspension behavior; learning
that behavior from a controlled experiment gives us a better model to use in
those design decisions. Six custom analyses tell that story, starting
with the road and what the driver feels. Its `StoryQuarterTruck` component extends
`QuarterTruckFullNN`. Each analysis exposes a `SimulationSolutionPlot` artifact
as a CairoMakie figure, with large labels and a consistent color scheme for
presentation on a large screen.

| Analysis | Story beat |
|----------|------------|
| `Story.A1Problem` | Drive over a bump: predict what the driver feels so we can make better suspension design decisions. |
| `Story.A2Gap` | Measure where the linear suspension model misses the road response. |
| `Story.A3Training` | Spend about a minute learning from a controlled sine-wave experiment and show the resulting fit. |
| `Story.A4Performance` | Return to the road, which was excluded from training, and evaluate the fully pretrained network. |
| `Story.A5SineValidation` | Compare the pretrained model at the sine-wave amplitude and frequency used for training. |
| `Story.A6OutOfDomain` | Change the sine-wave conditions beyond training and check where the learned model generalizes or loses accuracy. |

The default road has a 3 cm half-sine bump lasting 0.3 seconds, beginning at
1 second. The single impact makes the difference in the predicted settling
response easy to see. An ISO 8608 roughness profile is also available with
`road_profile="rough"`; its roughness and vehicle speed are configurable.
The “measurements” in this demo are synthetic, generated by the nonlinear
reference model. The final
comparison checks the improved prediction; spring tuning and controller design
are its intended applications. The implementation lives in
`dyad/Story/definitions.jl`.

From Julia with this project active:

```julia
using QuarterTruckSciML, DyadInterface, CairoMakie
using QuarterTruckSciML: Story

problem = Story.A1Problem(; name=:problem)
fig = artifacts(problem, :SimulationSolutionPlot)
display(fig)
save("A1Problem.png", fig; px_per_unit=2)

gap = Story.A2Gap(; name=:gap)
display(artifacts(gap, :SimulationSolutionPlot))

# A short live training demonstration.
training = Story.A3Training(; name=:training, optimizer_maxtime=60.0)
display(artifacts(training, :SimulationSolutionPlot))

# Use the fully pretrained network for the final road comparison.
performance = Story.A4Performance(; name=:performance)
display(artifacts(performance, :SimulationSolutionPlot))

sine = Story.A5SineValidation(; name=:sine)
display(artifacts(sine, :SimulationSolutionPlot))

outside_training = Story.A6OutOfDomain(; name=:outside_training)
display(artifacts(outside_training, :SimulationSolutionPlot))

# An alternative road comparison with the same pretrained network.
rough_road = Story.A4Performance(; road_profile="rough", roughness=16e-6)
display(artifacts(rough_road, :SimulationSolutionPlot))
```

A1, A2, A4, A5, and A6 each expose the standard `TransientAnalysis` parameters,
including `start`, `stop`, `saveat`, `alg`, and solver tolerances, plus their
excitation settings. A3 exposes the `NNTrainingAnalysis` parameters, including
the dataset, optimizer, iteration limit, time limit, and weight-file paths.
Each is a directly runnable base analysis with `StoryQuarterTruck` as its default
model; there are no separate derived analysis wrappers. Each implements its own
comparison and plotting behavior internally.

A5 uses the training excitation: 3 cm amplitude at 2 Hz. A6 defaults to the
same amplitude at 4 Hz, outside the training excitation. Change `amplitude` and
`frequency` to explore other conditions. Both plot the reference, linear, and
pretrained-model responses and report their RMS errors; A6 does not assume
that the learned model will always outperform the linear model.

A3 defaults to a 60-second optimizer budget through `optimizer_maxtime`.
It trains on the first half-second of the sine experiment (`stop=0.5`), with
`abstol=reltol=1e-6`, to keep evaluations short enough for a live demonstration.
It can finish earlier if an iteration limit or convergence criterion is reached.
First-time compilation, model setup, and plotting add overhead; the optimizer
time limits are checked between iterations. Set `optimizer_maxtime` to change
the budget. Run A3 once before a live presentation to warm up compilation.

A4 uses the fully pretrained weights already checked in at
`assets/data/nn_weights_full_sin_lbfgs.csv`. The short live training run writes
separate weights into `story_output/` and does not replace A4's network.
Full offline pretraining is available through `scripts/train.jl`, without the
one-minute limit, before presenting the story. Relative weight and output paths
are resolved from the package directory.

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
