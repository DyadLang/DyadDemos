# DrivelineSciML

Two-stage parameter calibration of a nonlinear torsional isolator in an EV
driveline, built on `DyadModelOptimizer.CalibrationAnalysis`.

The plant is a two-inertia driveline — torque source → motor inertia →
**torsional hub isolator** → load inertia → damper to ground. The isolator
combines three torque paths:

- a known quasi-static baseline `k0·Δθ + c0·Δω` (from quasi-static tests),
- a hidden **Maxwell branch** (`k1` in series with `c1`): stiffness increases
  above the corner frequency `1/(2π·c1/k1)` ≈ 48 Hz,
- a hidden **Bouc-Wen element** (`α·z` with a nonlinear flow rule):
  rate-independent hysteresis that a viscous damper cannot reproduce.

The demo recovers the hidden parameters from clean "encoder" measurements
(`ω_eng`, `ω_load`) using **designed excitations** — each calibration stage
uses an experiment whose frequency/amplitude content makes a different
mechanism identifiable:

| Stage | Event | Excitation | What it exploits | Recovers |
|-------|-------|-----------|------------------|----------|
| 1 | chirp | 1→500 Hz, ±2 Nm on 30 Nm mean | frequency sweep separates the Maxwell relaxation (corner ≈ 48 Hz) from the frequency-flat Bouc-Wen tangent stiffness `α·A` | `k1`, `c1`, `α` |
| 2 | slow cycle | 1 Hz sine, ±100 Nm | full-amplitude hysteresis loop, Maxwell branch frozen (relaxed) | `α`, `β`, `γ` |
| — | tip-in | 30→150 Nm ramp + 600 Hz ripple | both active — **validation only** | — |

Stage 1 fits the **full** model (Bouc-Wen active), not a Maxwell-only model:
the Bouc-Wen element has a tangent stiffness `α·A` at the origin — a
frequency-flat linear spring that a Maxwell-only fit would lump into `k1`/`c1`,
biasing `k1` ~28 % low at *any* chirp amplitude. Freeing `α` lets the chirp's
frequency sweep separate the two (the Maxwell branch stiffens above its corner;
the tangent does not).

Each `CalibrationAnalysis` takes one dataset and one model, so the stages are
two analyses (`dyad/calibration.dyad`) chained by `scripts/run_calibration.jl`:
the Stage 2 harness is constructed with the de-biased Stage 1 `k1`/`c1` frozen
via constructor keywords. The Bouc-Wen gain `A` is fixed at 1 by convention —
the flow rule is exactly invariant under `(A → s·A, α → α/s)`, so fitting both
is structurally non-identifiable.

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

Stage 1 recovers the Maxwell branch to a few percent (`k1` ≈ 294 vs. truth 300,
`c1` ≈ 1.02 vs. 1.0, τ ≈ 3.5 ms vs. 3.3 ms) plus a first estimate of the
Bouc-Wen scale (`α` ≈ 47 vs. 50). Fitting the *full* model is what makes this
work: a Maxwell-only fit is biased ~28 % low on `k1` at **any** chirp amplitude,
because the Bouc-Wen tangent stiffness `α·A` is a frequency-flat spring the
Maxwell parameters would otherwise absorb. Stage 2 then sharpens the Bouc-Wen
element on the full-amplitude slow cycle with the de-biased Maxwell frozen:
`α` ≈ 49.6, `β` ≈ 4.97, `γ` ≈ 0.44 (max hysteresis torque `α·A/β` ≈ 9.98 Nm vs.
truth 10.0). De-biasing the Maxwell branch is also what makes `γ` identifiable:
with a biased Maxwell frozen in, the Bouc-Wen parameters waste their freedom
compensating for the mismatch and `γ` goes flat.

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
choice: it reports optimizer health (`assess_health`) and rebuilds the exact
objective (`objective(prob, alg)`) to test whether ground truth is even the loss
minimizer — separating optimizer failure from structural/identifiability bias.

### Smoke tests

```bash
julia +dyad-3.3.0-rc2 --project -e 'using Pkg; Pkg.test()'
```

Verifies that the dyad library compiles, all harnesses simulate, the Bouc-Wen
state is active in the truth model and inert in the Maxwell-only chirp harness
(`TestDrivelineChirpMaxwellOnly`, retained for this check), and the committed
measurement CSVs have the expected shape.

## Possible extensions

The original study (see `agent_resources/reference/`) also trains a neural
network in place of the parametric Bouc-Wen flow rule (UDE). The natural Dyad
port adds a gray-box `DrivelineSystem` variant with a
`DyadModelDiscovery.NeuralNetworkBlock` for `der(z)` and an
`NNTrainingAnalysis` on the slow-cycle data — mirroring the
`QuarterTruckSciML` NN-discovery demo.
