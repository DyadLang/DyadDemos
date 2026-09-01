# DrivelineSciML

An electric car's driveline has a rubbery coupling between motor and wheels
that soaks up shock. Its behaviour is messy, and nobody can measure it
directly.

The demo shakes the coupling in two controlled ways and fits a model to what
comes back. It then checks that model against a manoeuvre the fit never saw.

Mechanically the coupling is a **nonlinear torsional isolator** — a twisting
spring and damper whose stiffness changes with how fast and how far you twist
it. Recovering its parameters is a two-stage calibration built on
`DyadModelOptimizer.CalibrationAnalysis`.

The plant is a spinning motor and a spinning load joined by that coupling:
torque source → motor inertia → **isolator** → load inertia → damper to ground.

The isolator combines three torque paths:

- a known baseline `k0·Δθ + c0·Δω`, measured beforehand by twisting the
  coupling slowly and steadily;
- a hidden **[Maxwell branch](https://en.wikipedia.org/wiki/Maxwell_material)** (`k1` in series with `c1`) — extra stiffness that
  only appears when you shake it fast, above the corner frequency
  `1/(2π·c1/k1)` ≈ 48 Hz;
- a hidden **[Bouc-Wen element](https://en.wikipedia.org/wiki/Bouc%E2%80%93Wen_model_of_hysteresis)** (`α·z` with a nonlinear flow rule) —
  hysteresis: the torque depends on where the twist has been, not just where it
  is now, and it behaves the same at any speed. No ordinary damper does that.

The demo recovers the hidden parameters from clean "encoder" measurements of
the two shaft speeds (`ω_eng`, `ω_load`).

Each stage uses a **designed excitation**: a torque input whose frequency and
amplitude are chosen so that one mechanism, and not the others, shows up in the
response.

| Stage | Event | Excitation | What it exploits | Recovers |
|-------|-------|-----------|------------------|----------|
| 1 | chirp | 1→500 Hz, ±2 Nm on 30 Nm mean | frequency sweep separates the Maxwell relaxation (corner ≈ 48 Hz) from the frequency-flat Bouc-Wen tangent stiffness `α·A` | `k1`, `c1`, `α` |
| 2 | slow cycle | 1 Hz sine, ±100 Nm | full-amplitude hysteresis loop, Maxwell branch frozen (relaxed) | `α`, `β`, `γ` |
| — | tip-in | 30→150 Nm ramp + 600 Hz ripple | both active — **validation only** | — |

A *tip-in* is the everyday manoeuvre of pressing the accelerator from light
load. It stays out of the fit and tests whether the fitted model predicts
something it has never seen.

Stage 1 fits the **full** model, with the Bouc-Wen element active. For small
twists that element behaves like a plain spring of stiffness `α·A`, and such a
spring looks the same at every frequency.

A Maxwell-only fit has nowhere to put that spring, so it absorbs it into
`k1`/`c1` and lands ~28 % low on `k1` at *any* chirp amplitude. Freeing `α`
lets the frequency sweep tell the two apart: the Maxwell branch stiffens above
its corner frequency, and the small-twist spring does not.

Each `CalibrationAnalysis` takes one dataset and one model, so the two stages
are two analyses (`dyad/calibration.dyad`), chained by
`scripts/run_calibration.jl`. Stage 2's harness is built with the de-biased
Stage 1 `k1`/`c1` frozen via constructor keywords.

The Bouc-Wen gain `A` is fixed at 1 by convention. Scaling `A` up and `α` down
by the same factor leaves the behaviour identical, so fitting both at once has
no unique answer.

## Layout

| Path                                   | What                                                        |
|----------------------------------------|-------------------------------------------------------------|
| `dyad/driveline_model.dyad`            | `MaxwellBoucWenIsolator` + `DrivelineSystem`                |
| `dyad/torque_signals.dyad`             | `TipInTorque` validation excitation                         |
| `dyad/harnesses.dyad`                  | Chirp / slow-cycle / tip-in test harnesses                  |
| `dyad/calibration.dyad`                | `DrivelineStage1CalibrationAnalysis` + Stage 2              |
| `scripts/generate_calibration_data.jl` | Simulate truth isolator → measurement CSVs                  |
| `scripts/run_calibration.jl`           | Run both stages, print recovered vs. truth                  |
| `scripts/diagnose_calibration.jl`      | Optimizer-health + identifiability probe (why a fit lands where it does) |
| `scripts/validate.jl`                  | Tip-in 3-way comparison (linear / calibrated / truth)       |
| `assets/data/`                         | Committed measurement CSVs                                  |
| `agent_resources/reference/`           | Original hand-rolled study this demo was ported from        |

## Running the demo

Set the JuliaHub juliaup env vars once per shell (not needed for the VS Code
REPL command), then activate this project:

```bash
export JULIAUP_SERVER="https://juliahub.com/juliabin"
export JULIAUP_DEPOT_PATH="$HOME/.julia/juliaup-depots/juliahub.com"
cd DrivelineSciML
julia +dyad-3.3.0-rc2 --project -e 'using Pkg; Pkg.instantiate()'
```

The measurement CSVs are committed, so calibration runs immediately:

```bash
julia +dyad-3.3.0-rc2 --project scripts/run_calibration.jl   # both stages, ~2 min
julia +dyad-3.3.0-rc2 --project scripts/validate.jl          # → assets/validation_tipin.png
```

To regenerate the synthetic measurements from the truth model:

```bash
julia +dyad-3.3.0-rc2 --project scripts/generate_calibration_data.jl
```

After editing any `.dyad` file, regenerate `generated/` with the Dyad CLI:

```bash
dyad compile .
```

### Expected results

Stage 1 recovers the Maxwell branch to a few percent, plus a first estimate of
the Bouc-Wen scale:

| Quantity | Fitted | Truth |
|----------|--------|-------|
| `k1` [N·m/rad] | 294 | 300 |
| `c1` [N·m·s/rad] | 1.02 | 1.0 |
| `α` [N·m] | 47 | 50 |
| relaxation time τ = `c1/k1` | 3.5 ms | 3.3 ms |

Stage 2 then sharpens the Bouc-Wen element on the full-amplitude slow cycle,
with the de-biased Maxwell branch frozen:

| Quantity | Fitted | Truth |
|----------|--------|-------|
| `α` [N·m] | 49.6 | 50 |
| `β` | 4.97 | 5.0 |
| `γ` | 0.44 | 0.5 |
| max hysteresis torque `α·A/β` | 9.98 N·m | 10.0 N·m |

Two choices earn those numbers:

1. **Stage 1 fits the full model**, keeping the Bouc-Wen small-twist spring out
   of the Maxwell parameters.
2. **Stage 2 freezes the de-biased Maxwell branch**, which is what makes `γ`
   identifiable. Freeze a biased branch in, and the Bouc-Wen parameters spend
   their freedom compensating for the mismatch, which flattens `γ`.

The point the demo makes: **a designed experiment plus the right search space
recovers both the parameters and the prediction**. On the unseen tip-in event
the calibrated model cuts the RMS error vs. truth by ~99% relative to the linear
baseline:

| observable | linear RMSE | calibrated RMSE | improvement |
|------------|------------|-----------------|-------------|
| `ω_eng` [rad/s] | 0.523 | 0.0045 | +99% |
| `Δω` [rad/s] | 0.654 | 0.0056 | +99% |
| `φ_rel` [rad] | 0.0107 | 9.1e-5 | +99% |

`scripts/diagnose_calibration.jl` shows the reasoning behind the search-space
choice. It reports optimizer health (`assess_health`) and rebuilds the exact
objective (`objective(prob, alg)`), then checks whether the true parameters are
actually the lowest point of that objective. When they are not, the model's
structure is at fault rather than the optimizer.

### Smoke tests

```bash
julia +dyad-3.3.0-rc2 --project -e 'using Pkg; Pkg.test()'
```

Verifies four things:

- the Dyad library compiles;
- every harness simulates;
- the Bouc-Wen state moves in the truth model and stays inert in the
  Maxwell-only chirp harness (`TestDrivelineChirpMaxwellOnly`, kept for this
  check);
- the committed measurement CSVs have the expected shape.

## Possible extensions

The original study (see `agent_resources/reference/`) also trains a neural
network in place of the parametric Bouc-Wen flow rule (a UDE).

The natural Dyad port adds a gray-box `DrivelineSystem` variant — known physics for most of the model, a neural network only where the physics is unknown: a
`DyadModelDiscovery.NeuralNetworkBlock` for `der(z)`, plus an
`NNTrainingAnalysis` on the slow-cycle data. That mirrors the
`QuarterTruckSciML` NN-discovery demo.
