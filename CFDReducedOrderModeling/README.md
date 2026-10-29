# CFDReducedOrderModeling

Data-driven reduced-order models (ROMs) of CFD thermal fields, compiled as Dyad components for system simulation.

See [`application_background.md`](application_background.md) for the full engineering context.

## Quick Start

Use the `dyad-3.5.0` Julia distribution (Julia 1.13.2). This project targets
the Dyad 3.5.1 CLI, matching the repository. Validation uses the released 3.5.0
CLI because 3.5.1 is not published; see [validation notes](docs/upgrade-3.5-validation.md).

1. Open in VS Code with the Dyad Studio extension.
2. Start a Julia REPL (`Julia: Start REPL` from the command palette).
3. Enter package mode (`]`) and run `instantiate`.
4. Regenerate the models with `dyad compile .` from this folder.
5. Load the library:

```julia
using CFDReducedOrderModeling
```

## ROM Construction

Three automated pipelines build ROMs from spatial snapshot data:

```julia
using CFDReducedOrderModeling
using DyadInterface: artifacts

# SVD → clustering → calibrated thermal network
result = RunSVDThermalNetwork()

# POD/DMDc → linear state-space ROM
result = RunDataDrivenPOD()

# Neural ODE → clustering → calibrated thermal network
result = RunLatentNeuralODE()
```

The runners default to the bundled training CSV, independent of the working directory.
The neural pipeline performs a full latent-dimension sweep by default; a short
smoke run is available through `n_epochs=1, n_seeds=1, latent_dims=[2]`.

Each returns a `DyadInterface.AbstractAnalysisSolution` with full artifact support:

```julia
artifacts(result)                        # list available artifacts
artifacts(result, :CalibratedNetwork)    # DataFrame of parameters
artifacts(result, :ZoneAssignments)      # zone membership table
```

## ROM Simulation

The constructed ROMs are encoded as Dyad components and can be simulated:

```julia
# Run a transient analysis on the SVD Thermal Network ROM
result = SVDThermalNetworkROMTransient()
sol = result.sol
```

## Dashboard

An interactive dashboard compares all three ROMs against CFD validation data:

```
cd app
julia --project=.. app.jl
```

Open `http://localhost:9000`.

## Project Structure

```
dyad/                   Dyad model definitions (.dyad files)
src/                    Julia analysis pipelines and utilities
generated/              Compiler output (do not edit)
data/                   Training and validation CSV data
app/                    Interactive dashboard
```

### Dyad Components

| File | Component | Description |
|------|-----------|-------------|
| `HighFidelityOilPassage.dyad` | `HighFidelityOilPassage` | 20-node FD truth model |
| `SVDThermalNetworkROM.dyad` | `SVDThermalNetworkROM` | 4-zone calibrated ROM (SVD) |
| `NeuralODEThermalNetworkROM.dyad` | `NeuralODEThermalNetworkROM` | 4-zone calibrated ROM (Neural ODE) |
| `PODDMDcROM.dyad` | `PODDMDcROM` | 2-state POD/DMDc ROM |
| `RampSource.dyad` | `RampSource` | Ramp signal source |
| `StepSineSource.dyad` | `StepSineSource` | Step + sine signal source |
| `TestCFDTraining.dyad` | `TestCFDTraining` | Training data generation harness |
| `TestCFDValidation.dyad` | `TestCFDValidation` | Validation data generation harness |
| `TestROMs.dyad` | Test harnesses + transient analyses | ROM simulation harnesses |

## Tests

From this folder, run:

```sh
dyad compile .
julia +dyad-3.5.0 --project=. -e 'using Pkg; Pkg.test()'
```

Tests exercise all five transient analyses, compare the high-fidelity outputs
with the committed CFD CSVs, check ROM persistence and artifacts, exercise the
three construction pipelines with limited optimization/training budgets, and
call the dashboard API handlers without starting a server. Full default neural
training and browser rendering are not covered.
