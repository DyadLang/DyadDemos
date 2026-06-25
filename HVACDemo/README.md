# HVACDemo

<img src="./assets/image.png" width="96" align="right"/>

This project is a vapor-compression refrigeration cycle model built with Dyad and ModelingToolkit. It models a complete HVAC cycle with a refrigerant loop (R32) exchanging heat with two moist-air streams. The cycle consists of a compressor, a tube-fin condenser, a linear expansion valve (LEV), and a tube-fin evaporator connected in a closed loop, with moist-air sources and sinks supplying conditioned air to each heat exchanger. Controls are fixed (open-loop): compressor speed and valve position are driven by constant signal blocks rather than feedback controllers. The domain physics come from the `HVACComponents` library; signal sources come from `BlockComponents`.

The model carries extensive start-value parameters for refrigerant pressures and enthalpies, wall and air thermal properties, and per-segment heat-exchanger discretization, reflecting the stiff initialization typical of two-phase refrigerant and moist-air models.

## Getting Started

Download this folder to your machine and open it in VS Code with the [Dyad extension](https://help.juliahub.com/dyad/dev/getting_started/).

## Models

`CompleteCycleFixedControls` (`dyad/CompleteCycleFixedControls.dyad`) is the top-level model: a closed refrigerant loop (compressor → condenser → LEV → evaporator → compressor) with a separate moist-air stream flowing across each heat exchanger. The refrigerant is R32, supplied via `HVACComponents.SimpleRefrigerantPropertiesLibrary`; the air uses the moist-air medium. The two heat exchangers are discretized into `nSeg = 8` segments with `nTube = 1` and `n_flows = 4` distributor flows.

#### CompleteCycleFixedControls Components

| Instance | Type | Role |
|---|---|---|
| `compressor` | `HVACComponents.Components.Compressor` | Drives the refrigerant circuit; compresses suction vapor to discharge pressure |
| `compressor_speed_signal` | `BlockComponents.Sources.Constant` | Fixed compressor speed command (k = 10.0) |
| `condenser` | `HVACComponents.Components.TubeFinHEX` | Tube-fin heat exchanger rejecting heat from refrigerant to moist air |
| `condAirSource` | `HVACComponents.Components.Sources.MassFlowSource_TPhi` | Condenser air supply (temperature + relative humidity + mass flow) |
| `condAirSink` | `HVACComponents.Components.Sources.Boundary_pTPhi` | Condenser air outlet boundary (pressure/temperature/humidity) |
| `LEV` | `HVACComponents.Components.LEV` | Linear expansion valve throttling refrigerant from condenser to evaporator |
| `LEV_position_signal` | `BlockComponents.Sources.Constant` | Fixed valve position command (k = 220.0) |
| `evaporator` | `HVACComponents.Components.TubeFinHEX` | Tube-fin heat exchanger absorbing heat from moist air into refrigerant |
| `evapAirSource` | `HVACComponents.Components.Sources.MassFlowSource_TPhi` | Evaporator air supply (temperature + relative humidity + mass flow) |
| `evapAirSink` | `HVACComponents.Components.Sources.Boundary_pTPhi` | Evaporator air outlet boundary (pressure/temperature/humidity) |

The refrigerant ports form the loop (`compressor.port_b → condenser → LEV → evaporator → compressor.port_a`); each heat exchanger's air ports connect its dedicated source and sink. The model file also defines the analysis used to run it.

## Running the Demo

**`scripts/main.jl`** loads the library and runs the `CompleteCycleFixedControls_SRP_Analysis` analysis, a `TransientAnalysis` over `t = 0 … 1400` s using the `Rodas5P` stiff solver with R32 as the working refrigerant.

**`scripts/analysis-notebook.ipynb`** provides an interactive environment to run the analysis and plot variables of interest.
