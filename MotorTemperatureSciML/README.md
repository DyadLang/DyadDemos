# MotorTemperatureSciML

Physics-informed machine learning for electric-motor temperature estimation:
a Dyad port of the **Thermal Neural Network** (TNN) of Kirchgässner,
Wallscheid & Böcker, trained on the public Paderborn PMSM dataset with
**stochastic mini-batch multiple shooting** under an **augmented Lagrangian**
via `DyadModelOptimizer`, and validated free-running against the reference
PyTorch implementation.

![Free-running prediction on the training profile](assets/validation_training_profile.png)

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
| `Thermal/Normalizer` | fixed max-abs feature scaling to `[0, 1]` | – |

537 parameters in total, three orders of magnitude fewer than a comparably
accurate black-box estimator. The network blocks are wrapped with
`ModelingToolkitNeuralNets.NeuralNetworkBlock` (via `DyadModelDiscovery`), so
ModelingToolkit sees each network as one opaque callable over a single
parameter vector. Measured signals enter through `FastVectorInterpolation`
(`dyad/definitions.jl`), a multi-channel interpolation block stored as a
concretely typed callable parameter: one time search per RHS call and no
boxing under ForwardDiff.

## How it is trained

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

## Running the demo

Set the JuliaHub juliaup env vars once per shell (not needed for the VS Code
REPL command), then instantiate this project:

```bash
export JULIAUP_SERVER="https://juliahub.com/juliabin"
export JULIAUP_DEPOT_PATH="$HOME/.julia/juliaup-depots/juliahub.com"
cd MotorTemperatureSciML
julia +dyad-3.3.0 --project -e 'using Pkg; Pkg.instantiate()'
```

The profiles are committed, so training runs immediately. Segments in a
mini-batch solve in parallel across Julia threads:

```bash
JULIA_NUM_THREADS=8 julia +dyad-3.3.0 --project scripts/train_stochastic_ms.jl    # ~20 min, → assets/data/calibrated_params.csv
julia +dyad-3.3.0 --project scripts/validate_calibration.jl                       # → assets/validation_*.png
JULIA_NUM_THREADS=8 julia +dyad-3.3.0 --project scripts/animate_sms_training.jl   # ~13 min, → assets/sms_training*.gif
```

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

The validation script can also be `include`d in the session that just trained.
The augmented Lagrangian stops with `Success` once every segment junction has
closed to within `CONTINUITY_TOL_C = 0.2 °C` (`scripts/common.jl`); if it
runs out of outer iterations first it reports `ConvergenceFailure`. `Success`
certifies continuity, not accuracy: the junctions can close while the data
fit is still improving, so the free-running validation is the accuracy
measure either way.

| Path | Purpose |
|---|---|
| `dyad/` | Model: `Models/TNNModel.dyad`, the `Networks/` and `Thermal/` blocks, `FastVectorInterpolation` (external component, implemented in `dyad/definitions.jl`), and the `TestTNNProfile` harness that drives the model from a profile CSV |
| `src/chains.jl` | Lux chains of the two networks |
| `scripts/common.jl` | Shared setup: segmentation, `Experiment` / `InverseProblem` / algorithm builders |
| `scripts/train_stochastic_ms.jl` | Calibration run |
| `scripts/validate_calibration.jl` | Free-running validation and plots |
| `scripts/animate_sms_training.jl` | Training animation |
| `scripts/prepare_data.jl` | Re-slice profiles from `measures_v2.csv` |
| `scripts/train_pytorch_reference.py` | The reference PyTorch TNN trained on the same profile; writes the predictions the validation overlays |
| `assets/data/` | Profiles 17, 60, 62, 74 and the PyTorch reference predictions |

Tests: `julia +dyad-3.3.0 --project -e 'using Pkg; Pkg.test()'`.

### Reproducing the PyTorch reference

The reference predictions in `assets/data/pytorch_profile_<id>.csv` are
written by a port of the upstream notebook's training and evaluation cells,
restricted to profile 17. It reads the shipped profile CSVs, so no download is
needed, and declares its dependencies inline; `uv` builds a CPU-only
environment on first use:

```bash
uv run scripts/train_pytorch_reference.py            # ~2.5 min, → assets/data/pytorch_profile_<id>.csv
```

Without `uv`, install `scripts/requirements.txt` into a virtualenv and run the
script with `python`. `--epochs`, `--threads`, `--seed` and `--out-dir` are
the useful knobs; `--no-export` trains and reports without touching the CSVs.

## Data

The **Paderborn PMSM temperature dataset**
([Electric Motor Temperature](https://www.kaggle.com/datasets/wkirgsn/electric-motor-temperature)
on Kaggle, DOI `10.34740/KAGGLE/DSV/2161054`, by the TNN authors): 185 hours
of test-bench measurements at 2 Hz across 69 drive profiles. `assets/data/`
ships the training profile (`profile_17.csv`) and the three held-out profiles
the upstream notebook evaluates on (`profile_60/62/74.csv`), sliced by
`scripts/prepare_data.jl`. `pytorch_profile_<id>.csv` are the free-running
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
