# CFDReducedOrderModeling

Data-driven reduced-order models (ROMs) of CFD thermal fields, compiled as Dyad components for system simulation.

See [`application_background.md`](application_background.md) for the full engineering context.

## Quick Start

1. Open in VS Code with the Dyad Studio extension.
2. Start a Julia REPL (`Julia: Start REPL` from the command palette).
3. Enter package mode (`]`) and run `instantiate`.
4. Load the library:

```julia
using CFDReducedOrderModeling
```

## ROM Construction

Three automated pipelines build ROMs from spatial snapshot data:

```julia
# SVD → clustering → calibrated thermal network
result = RunSVDThermalNetwork(data="data/cfd_training_data.csv")

# POD/DMDc → linear state-space ROM
result = RunDataDrivenPOD(data="data/cfd_training_data.csv")

# Neural ODE → clustering → calibrated thermal network
result = RunLatentNeuralODE(data="data/cfd_training_data.csv")
```

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
