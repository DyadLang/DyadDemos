# MotorTemperatureSciML

Estimate four internal electric-motor temperatures from measured operating
conditions. Two small neural networks estimate heat generation and heat
transfer; a thermal model integrates these into temperature predictions.
This Dyad demo shows how to train that combined model and check its accuracy
in a continuous simulation.

The shipped fit is accurate on its training profile, but errors on unseen
profiles remain around **9–28 °C RMS**. This is a demonstration of training
and validation using a single drive profile; it does not reproduce the
published model's generalization performance from much broader training data.

![Free-running prediction on the training profile](assets/validation_training_profile.png)

## Try the demo

The input profiles, calibrated parameters, and reference predictions are
included. **You can validate the saved fit without training or downloading data.**

Instantiate the standalone project once:

```bash
cd MotorTemperatureSciML
julia --project -e 'using Pkg; Pkg.instantiate()'
```

### Run it as a sequence of analyses

The same story is available as Dyad analyses, so it can be run from Dyad
Builder or from Julia without touching the scripts. They are declared in
[`dyad/Story/Story.dyad`](dyad/Story/Story.dyad), numbered `A1` to `A7` in the
order to run them, and every one has a `SimulationSolutionPlot` artifact (a
Makie figure). Each finishes in a couple of minutes, so the sequence runs
click by click:

| Step | Analysis | `SimulationSolutionPlot` shows |
|---|---|---|
| 1 · Before training | `A1_UntrainedTNN` | the untrained model free-running against the measurements |
| 2 · Training | `A2_TrainTNNQuick` (about two minutes) | loss per Adam step, junction gap and penalty per outer iteration; also `FitPlot`, `ContinuityPlot` |
| 3 · After training | `A3_RetrainedTNN` (the fit step 2 wrote), `A4_CalibratedTNN` (shipped fit) | the calibrated model against the measurements and the PyTorch reference |
| 3 · Held out | `A5_CalibratedTNNProfile60`, `…62`, `…74` | the shipped fit on profiles the model never saw |

The full-budget calibration behind the results below is
[`scripts/train_stochastic_ms.jl`](scripts/train_stochastic_ms.jl), a 20-to-40
minute run kept out of the click-through sequence.

Every analysis also exposes tables (`ErrorTable`, `SimulationSolutionTable`,
`LossTable`, …) and the raw solution. The two base analyses,
`TNNFreeRunAnalysis` and `TNNTrainingAnalysis`, live in
[`dyad/TNNAnalyses.dyad`](dyad/TNNAnalyses.dyad) with their Julia
implementation in [`src/story_analyses.jl`](src/story_analyses.jl); they read
the measurements from the harness the analysis is given, so a different
profile is just a different `TestTNNProfile` component.

From Julia, `scripts/story.jl` runs the whole sequence and saves every plot
artifact to `runs/story/`:

```bash
JULIA_NUM_THREADS=8 julia --project scripts/story.jl
```

### View the saved fit

```bash
julia --project scripts/validate_calibration.jl
```

This reads `assets/data/calibrated_params.csv`, reports RMS errors, and writes
four plots to `runs/validation/`. Start with `validation_training_profile.png`
and `validation_test_profiles.png`. Initial package loading and compilation
can take a few minutes. Each profile starts from its first measured temperatures
and then runs continuously, without resetting at the end of the training horizon.

### Check the training pipeline

```bash
TNN_BUDGET=quick JULIA_NUM_THREADS=8 julia --project scripts/train_stochastic_ms.jl --out-dir runs/quick
julia --project scripts/validate_calibration.jl --calibration runs/quick/calibrated_params.csv --out-dir runs/quick
```

The quick budget takes about a minute on the measured machine, including
compilation. It checks that the pipeline works; it is too short for an accurate
fit. The second command evaluates this quick fit explicitly.

### Retrain the full model

```bash
JULIA_NUM_THREADS=8 julia --project scripts/train_stochastic_ms.jl --out-dir runs/full
julia --project scripts/validate_calibration.jl --calibration runs/full/calibrated_params.csv --out-dir runs/full
```

Full training takes about 21 minutes on the measured machine. See
[training settings](#training-settings-and-performance) for the shorter budget
and thread-count measurements.

All run outputs go under the gitignored `runs/` directory by default. Training
without `--out-dir` writes to `runs/training/`. Validation defaults to the
**shipped calibration**, even after a training run; select your new fit with
`--calibration`. `--out-dir` selects where each script writes its results;
relative paths are relative to the working directory. Reusing a run directory
replaces its previous outputs. The committed data and README plots remain intact.

## How the model works

The TNN estimates four internal temperatures of a permanent-magnet
synchronous motor (rotor magnet, stator yoke, stator tooth, stator winding)
from ten measured operating conditions (voltages, currents, speed, torque,
coolant and ambient temperature). It is a lumped-parameter thermal network,
a 6-node heat-transfer ODE, whose coefficients are produced by small neural
networks:

| Block | Role | Trained parameters |
|---|---|---|
| `Networks/ConductanceNet` | thermal conductances of the 15 edges of the fully connected 6-node graph | `Dense(14 → 15, sigmoid)`, 225 |
| `Networks/PowerLossNet` | heat generation at the 4 target nodes | `Dense(14 → 16, tanh) → Dense(16 → 4, abs)`, 308 |
| `Thermal/CapacitanceBlock` | inverse thermal capacitances, `exp.(caps)` (log-space keeps them positive) | 4 |
| `Thermal/ThermalDynamics` | fixed physics: `C·dT/dt = Σ G·ΔT + P` | – |
| `Thermal/Normalizer` | fixed feature scaling: temperatures divided by 200, signed signals by max-abs constants | – |
| `Thermal/TemperatureOutputs` | converts the four normalized states to named outputs in °C | – |

![TNN model schematic](assets/tnn_schematic.png)

The diagram keeps feature and temperature vectors bundled, with temperature
feedback below the neural networks. Explicit junctions mark shared signals;
`BoundaryTemperatures` selects coolant and ambient from the feature vector.
Inside each neural network, `FeatureMux` concatenates `[x; T]` before the NN.
The profile harness uses named demux outputs to keep the ten scalar input wires
separate and aligned. These routing components are local to this demo.
The normalizer shows one row per input: `s1`–`s8` are the corresponding
feature scales, while the two pre-normalized magnitude features pass through.
The matching neural-network icons distinguish conductance (a thermal
resistance) from power loss (heat waves); the output block groups the four
conversions to °C.

[Profile wiring](assets/profile_schematic.png) ·
[Neural-network input mux](assets/network_schematic.png)

`TNNModel.MAX_TEMP` sets the scale for both normalization and output conversion.
The calibration scripts use the fixed 200 °C convention of the reference model.
[`Story/HighTempTNNModel`](dyad/Story/HighTempTNNModel.dyad) is the whole model
cloned to a 250 °C ceiling in one line of `extends`, and shows up in the
component browser with the ports, wiring and icon it inherits.

## How it is trained

This is a Dyad port of the Thermal Neural Network (TNN) of Kirchgässner,
Wallscheid & Böcker. It is trained on the public Paderborn PMSM dataset and
compared with a port of the reference PyTorch implementation.

Fitting a two-hour profile by single shooting is slow and badly conditioned:
the loss landscape over the network weights is dominated by how early errors
compound along the trajectory. `scripts/train_stochastic_ms.jl` instead uses
`StochasticMultipleShooting`:

- the 2 h horizon is cut into 96 segments of 75 s, each with its own free
  initial state;
- every Adam step samples a mini-batch of 32 segments in contiguous blocks of
  4 and solves them in parallel on a pool of integrators;
- continuity at the 95 segment junctions is imposed as a constraint by an
  augmented Lagrangian outer loop (`OptimizationAuglag.AugLag`); each outer
  iteration updates the multipliers and penalty, and the inner problem is
  minimised by Adam;
- gradients are ForwardDiff over the mini-batch, with the differentiated
  parameter buffer restricted to the 537 trained values.

![Stochastic multiple shooting during training](assets/sms_training.gif)

Gold segments are the ones in the current mini-batch, red bars are the
continuity defects the augmented Lagrangian shrinks. A four-panel version with
the training curves and per-junction defects is in
[`assets/sms_training_detailed.gif`](assets/sms_training_detailed.gif).
The animation is a separate, coarser run chosen so that individual segments
are visible: 24 segments of 300 s instead of 96 of 75 s, mini-batches of 8,
and 10 outer iterations of 33 epochs (990 steps, about 10 min). Its final
frame sits 2–3 °C below the rotor plateau, short of the 0.4 °C the full
calibration reaches; the GIF shows the mechanics, the results below show the
fit.

The training-time objective is not the model's accuracy: it mixes data misfit
with penalty terms and is evaluated with segment initial states that are stale
right after a multiplier update. `scripts/validate_calibration.jl` therefore
runs the calibrated model as a plain ODE over the whole training profile and
over three held-out profiles, and compares with the reference PyTorch TNN
trained on the same single profile for 100 epochs (see the note on
multi-profile training under Results).

## Results

Free-running RMS error in °C. The Dyad run is 5 outer iterations × 100
epochs, 1500 Adam steps over mini-batches of 32 segments, 21 min on 8
threads. The PyTorch column is the reference implementation trained on the
same profile for 100 epochs of truncated BPTT over 512-sample chunks, 3200
updates, about 140 s on the same machine (`scripts/train_pytorch_reference.py`,
torch on 24 threads). The reference is sensitive to its random initialisation:
three seeds give 0.4–0.8 / 2.5–4.4 / 2.4–8.5 / 2.2–5.9 °C on the training
profile; the table shows the default seed. An epoch is one pass over the profile in both cases, so
per pass the Dyad run is about 1.6× slower and takes 5× more of them; each of
its steps integrates 32 segments with an adaptive solver and differentiates
through them with ForwardDiff, whereas a TBPTT update is 512 explicit Euler
steps on one chunk.

| Profile | | T_pm | T_stator_yoke | T_stator_tooth | T_stator_winding |
|---|---|---|---|---|---|
| 17, training horizon (0–7200 s) | Dyad | 0.42 | 0.42 | 0.37 | 0.60 |
| | PyTorch | 0.78 | 4.05 | 8.53 | 2.48 |
| 17, held-out tail (7200 s–end) | Dyad | 0.10 | 0.33 | 0.23 | 0.17 |
| | PyTorch | 0.90 | 1.57 | 1.76 | 1.51 |
| 60 (held out) | Dyad | 15.2 | 16.5 | 20.1 | 25.8 |
| 62 (held out) | Dyad | 10.5 | 8.6 | 10.5 | 13.6 |
| 74 (held out) | Dyad | 17.6 | 16.4 | 21.2 | 27.6 |

![Held-out profiles](assets/validation_test_profiles.png)

Both models saw a *single* 2.2 h profile. The published TNN results are
obtained very differently: the upstream notebook trains on the whole Paderborn
training set, 66 profiles and 176 h of data, and generalises to the held-out
profiles far better than either column here. Training over several profiles
at once, one experiment per profile inside the stochastic multiple-shooting
loop, is not yet supported on the Dyad side, so this demo trains on one
profile and uses the other three only as a stress test. On that test the Dyad
fit stays bounded and tracks the shape of the unseen profiles with a 9–28 °C
error; the reference fit runs away on all three (its curves leave the frame in
the figure above, whose axes follow the measurement). The two share the same
architecture and both are trained over the whole profile (the notebook's
truncated BPTT carries the state across chunks), so the difference lies
elsewhere: the reference steps the ODE with explicit Euler at the 0.5 s
sample rate and clips its outputs, the Dyad model is integrated adaptively;
the capacitances start from different scales; and the shooting fit imposes
exact continuity at 95 junctions. Which of these keeps the Dyad fit bounded
on unseen operating conditions is not established here. The
segment-continuity residuals of the shooting fit
([`assets/validation_continuity.png`](assets/validation_continuity.png)) are
the diagnostic to watch during training: they end up within ±0.14 °C with no
systematic sign, which is what lets the segment-wise fit carry over to the
free-running simulation, and is the criterion the run stops on. The fitted
log-capacitances moved from the initial −5.0 to −5.6 / −5.2 / −5.2 / −5.3.

## Implementation details

The model has 537 trained parameters in total. The network blocks are wrapped with
`ModelingToolkitNeuralNets.NeuralNetworkBlock` (via `DyadModelDiscovery`), so
ModelingToolkit sees each network as one opaque callable over a single
parameter vector. Measured signals enter through `FastVectorInterpolation`
(`dyad/definitions.jl`), a multi-channel interpolation block stored as a
concretely typed callable parameter: one time search per RHS call and no
boxing under ForwardDiff.

`OptimizationBBO` is a direct dependency only to pin it: version 0.4.8, which
the resolver otherwise picks, does not load against `SciMLBase` 3.50 or newer.
Drop the pin once a release supporting `LogExpFunctions` 1 is available.

## Training settings and performance

The full training run uses stochastic mini-batch multiple shooting with an
augmented Lagrangian, via `DyadModelOptimizer`. The timing guidance below is
specific to the measured machine and workload.

More threads is not faster here. The CPU used, an i9-14900K, has 8
performance cores and 16 efficiency cores, and the optimum is one thread per
performance core. Wall-clock per epoch (one pass over the 96 segments, batch
32, after warm-up):

| Julia threads | 4 | 8 | 12 | 16 | 24 | 32 |
|---|---|---|---|---|---|---|
| s / epoch | 2.55 | **2.33** | 2.65 | 2.90 | 4.17 | 3.24 |

Each step waits for its slowest segment, so any thread scheduled on an
efficiency core or a hyperthread holds the whole batch back. On a machine
with uniform cores, use one thread per physical core. Keep `BATCH_SIZE = 32` even
on small machines: the per-step cost is dominated by the full-batch constraint
Jacobian, so a smaller batch costs almost as much per step and needs more
steps per epoch (batch 8 on 8 threads: 6.75 s / epoch).

`TNN_BUDGET` selects the training budget (8 threads; RMS is the free-running
error on the training horizon):

| `TNN_BUDGET` | outer × epochs | Adam steps | time | RMS pm / yoke / tooth / winding [°C] |
|---|---|---|---|---|
| `quick` | 1 × 2 | 6 | ~1 min incl. compile | pipeline check only |
| `short` | 10 × 12 | 360 | ~5 min | 4.1 / 0.8 / 0.9 / 3.1 |
| `full` (default) | 5 × 100 | 1500 | ~21 min | 0.42 / 0.42 / 0.37 / 0.60 |

The validation script can also be `include`d in the session that just trained;
it then uses the in-memory `calres`, unless `--calibration` explicitly selects
a file.
The augmented Lagrangian stops with `Success` once every segment junction has
closed to within `CONTINUITY_TOL_C = 0.2 °C` (`scripts/common.jl`); if it
runs out of outer iterations first it reports `ConvergenceFailure`. `Success`
certifies continuity, not accuracy: the junctions can close while the data
fit is still improving, so the free-running validation is the accuracy
measure either way.

To regenerate the training animation in a separate run directory:

```bash
JULIA_NUM_THREADS=8 julia --project scripts/animate_sms_training.jl --out-dir runs/animation
```

This writes the GIFs, final-frame PNGs, and reusable snapshot cache there.
Use `FORCE_RETRAIN=1` to refresh a cached animation run.

| Path | Purpose |
|---|---|
| `dyad/` | Model: `Models/TNNModel.dyad`, the `Networks/` and `Thermal/` blocks, `FastVectorInterpolation` (external component, implemented in `dyad/definitions.jl`), and the `TestTNNProfile` harness that drives the model from a profile Parquet file |
| `src/chains.jl` | Lux chains of the two networks |
| `scripts/common.jl` | Shared setup: segmentation, `Experiment` / `InverseProblem` / algorithm builders |
| `scripts/train_stochastic_ms.jl` | Calibration run |
| `scripts/validate_calibration.jl` | Free-running validation and plots |
| `scripts/animate_sms_training.jl` | Training animation |
| `scripts/prepare_data.jl` | Re-slice profiles from `measures_v2.csv` into Parquet |
| `scripts/train_pytorch_reference.py` | The reference PyTorch TNN trained on the same profile; writes new predictions under `runs/` |
| `assets/data/` | Shipped profiles, calibration, and PyTorch reference predictions |
| `runs/` | Local calibration, validation, and animation outputs (gitignored) |

Tests: `julia --project -e 'using Pkg; Pkg.test()'`.

### Reproducing the PyTorch reference

The shipped reference predictions in `assets/data/pytorch_profile_<id>.parquet`
were written by a port of the upstream notebook's training and evaluation cells,
restricted to profile 17. It reads the shipped profile files, so no download is
needed, and declares its dependencies inline; `uv` builds a CPU-only
environment on first use:

```bash
uv run scripts/train_pytorch_reference.py            # ~2.5 min, → runs/pytorch/pytorch_profile_<id>.parquet
```

Without `uv`, install `scripts/requirements.txt` into a virtualenv and run the
script with `python`. `--epochs`, `--threads`, `--seed` and `--out-dir` are
the useful knobs; `--no-export` trains and reports without writing files.
New predictions go to `runs/pytorch/` by default. Validation overlays the
shipped reference predictions; regenerating them into a run directory does
not replace that reference.

## Data

The **Paderborn PMSM temperature dataset**
([Electric Motor Temperature](https://www.kaggle.com/datasets/wkirgsn/electric-motor-temperature)
on Kaggle, DOI `10.34740/KAGGLE/DSV/2161054`, by the TNN authors): 185 hours
of test-bench measurements at 2 Hz across 69 drive profiles. `assets/data/`
ships the training profile (`profile_17.parquet`) and the three held-out profiles
the upstream notebook evaluates on (`profile_60/62/74.parquet`), sliced by
`scripts/prepare_data.jl`. The files are zstd-compressed
[Parquet](https://parquet.apache.org/) with the full Float64 precision of the
source, about a third of the equivalent CSV; read them with
`Parquet2.Dataset(path)` in Julia or `pandas.read_parquet(path)` in Python.
`pytorch_profile_<id>.parquet` are the free-running
predictions of the reference implementation ([wkirgsn/thermal-nn](https://github.com/wkirgsn/thermal-nn),
`TNN_pytorch.ipynb`) after training on profile 17 only for 100 epochs, on the
same 0.5 s grid, as written by `scripts/train_pytorch_reference.py` (seed 0).

## References

- W. Kirchgässner, O. Wallscheid, J. Böcker, *Thermal neural networks:
  Lumped-parameter thermal modeling with state-space machine learning*,
  Engineering Applications of Artificial Intelligence 117 (2023) 105537.
  DOI [10.1016/j.engappai.2022.105537](https://doi.org/10.1016/j.engappai.2022.105537),
  preprint [arXiv:2103.16323](https://arxiv.org/abs/2103.16323).
- Reference implementation (PyTorch/TensorFlow/Matlab):
  [github.com/wkirgsn/thermal-nn](https://github.com/wkirgsn/thermal-nn).
