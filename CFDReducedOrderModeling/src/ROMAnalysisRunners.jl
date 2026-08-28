# ════════════════════════════════════════════════════════════════
#  Pre-configured analysis runners for the three ROM pipelines.
#
#  These follow the same pattern the Dyad compiler generates for
#  `analysis RunX extends BaseAnalysis(param = value)`:
#    - Spec struct <: AbstractBaseSpec  (with defaults baked in)
#    - run_analysis(spec) → delegates to base spec
#    - Convenience constructor RunX(; kwargs...)
#
#  Since the Dyad compiler doesn't support `partial analysis`
#  definitions, these are hand-written Julia equivalents.
# ════════════════════════════════════════════════════════════════

using DyadInterface

# ────────────────────────────────────────────────────────────
#  RunSVDThermalNetwork
# ────────────────────────────────────────────────────────────

"""
    RunSVDThermalNetwork(; data="data/cfd_training_data.csv", ...)

Pre-configured SVD Thermal Network ROM builder.
Runs the complete pipeline: SVD → zone clustering → calibrated thermal network.

Equivalent Dyad (if partial analysis were supported):
```
analysis RunSVDThermalNetwork
  extends SVDThermalNetworkAnalysis(
    data = "data/cfd_training_data.csv"
  )
end
```

## Usage
```julia
using CFDReducedOrderModeling

result = RunSVDThermalNetwork()
result.r.network           # calibrated thermal network
artifacts(result)           # list available artifacts
artifacts(result, :CalibratedNetwork)  # DataFrame of parameters
```
"""
@kwdef mutable struct RunSVDThermalNetworkSpec <: AbstractSVDThermalNetworkSpec
    name::Symbol = :RunSVDThermalNetwork
    data::String = "data/cfd_training_data.csv"
    spatial_cols::Union{Nothing, Vector{String}} = nothing
    input_col::String = "Q_in"
    time_col::String = "time"
    reference_temp::Float64 = 300.0
    energy_threshold::Float64 = 0.999
    R2_threshold::Float64 = 0.88
    N_candidates::Vector{Int} = [2, 3, 4, 5, 6, 8, 10]
    C0_per_node::Float64 = 80.0
    G0::Float64 = 40.0
    Gc0::Float64 = 10.0
    maxiter::Int = 20000
    output::String = ""
    verbose::Bool = true
end

function DyadInterface.run_analysis(spec::RunSVDThermalNetworkSpec)
    base_spec = SVDThermalNetworkSpec(;
        name = :SVDThermalNetworkAnalysis,
        data = spec.data,
        spatial_cols = spec.spatial_cols,
        input_col = spec.input_col,
        time_col = spec.time_col,
        reference_temp = spec.reference_temp,
        energy_threshold = spec.energy_threshold,
        R2_threshold = spec.R2_threshold,
        N_candidates = spec.N_candidates,
        C0_per_node = spec.C0_per_node,
        G0 = spec.G0,
        Gc0 = spec.Gc0,
        maxiter = spec.maxiter,
        output = spec.output,
        verbose = spec.verbose,
    )
    DyadInterface.run_analysis(base_spec)
end

RunSVDThermalNetwork(; kwargs...) = DyadInterface.run_analysis(RunSVDThermalNetworkSpec(; kwargs...))

# ────────────────────────────────────────────────────────────
#  RunDataDrivenPOD
# ────────────────────────────────────────────────────────────

"""
    RunDataDrivenPOD(; data="data/cfd_training_data.csv", ...)

Pre-configured POD/DMDc ROM builder.
Runs the complete pipeline: SVD → DMDc dynamics → zone clustering.

Equivalent Dyad (if partial analysis were supported):
```
analysis RunDataDrivenPOD
  extends DataDrivenPODAnalysis(
    data = "data/cfd_training_data.csv"
  )
end
```

## Usage
```julia
using CFDReducedOrderModeling

result = RunDataDrivenPOD()
result.r.A                 # dynamics matrix
result.r.B                 # input matrix
result.r.C                 # output matrix
artifacts(result)           # list available artifacts
artifacts(result, :ROMParameters)  # DataFrame of A, B, C
```
"""
@kwdef mutable struct RunDataDrivenPODSpec <: AbstractDataDrivenPODSpec
    name::Symbol = :RunDataDrivenPOD
    data::String = "data/cfd_training_data.csv"
    spatial_cols::Union{Nothing, Vector{String}} = nothing
    input_col::String = "Q_in"
    time_col::String = "time"
    reference_temp::Float64 = 300.0
    energy_threshold::Float64 = 0.999
    k_override::Int = 0
    R2_threshold::Float64 = 0.88
    N_candidates::Vector{Int} = [2, 3, 4, 5, 6, 8, 10]
    output::String = ""
    verbose::Bool = true
end

function DyadInterface.run_analysis(spec::RunDataDrivenPODSpec)
    base_spec = DataDrivenPODSpec(;
        name = :DataDrivenPODAnalysis,
        data = spec.data,
        spatial_cols = spec.spatial_cols,
        input_col = spec.input_col,
        time_col = spec.time_col,
        reference_temp = spec.reference_temp,
        energy_threshold = spec.energy_threshold,
        k_override = spec.k_override,
        R2_threshold = spec.R2_threshold,
        N_candidates = spec.N_candidates,
        output = spec.output,
        verbose = spec.verbose,
    )
    DyadInterface.run_analysis(base_spec)
end

RunDataDrivenPOD(; kwargs...) = DyadInterface.run_analysis(RunDataDrivenPODSpec(; kwargs...))

# ────────────────────────────────────────────────────────────
#  RunLatentNeuralODE
# ────────────────────────────────────────────────────────────

"""
    RunLatentNeuralODE(; data="data/cfd_training_data.csv", ...)

Pre-configured Latent Neural ODE ROM builder.
Runs the complete pipeline: Neural ODE sweep → zone clustering → calibrated network.

Equivalent Dyad (if partial analysis were supported):
```
analysis RunLatentNeuralODE
  extends LatentNeuralODEAnalysis(
    data = "data/cfd_training_data.csv"
  )
end
```

## Usage
```julia
using CFDReducedOrderModeling

result = RunLatentNeuralODE()
result.r.best_k            # discovered ROM order
result.r.network           # calibrated thermal network
artifacts(result)           # list available artifacts
artifacts(result, :LatentDimSweep)  # DataFrame of RMSE per k
```
"""
@kwdef mutable struct RunLatentNeuralODESpec <: AbstractLatentNeuralODESpec
    name::Symbol = :RunLatentNeuralODE
    data::String = "data/cfd_training_data.csv"
    spatial_cols::Union{Nothing, Vector{String}} = nothing
    input_col::String = "Q_in"
    time_col::String = "time"
    reference_temp::Float64 = 300.0
    latent_dims::Vector{Int} = [1, 2, 3, 4, 5, 6]
    hidden_enc::Int = 64
    hidden_dyn::Int = 32
    hidden_dec::Int = 64
    n_epochs::Int = 300
    lr::Float64 = 5e-4
    n_shooting::Int = 15
    window_len::Int = 15
    n_seeds::Int = 3
    R2_threshold::Float64 = 0.88
    N_candidates::Vector{Int} = [2, 3, 4, 5, 6, 8, 10]
    C0_per_node::Float64 = 80.0
    G0::Float64 = 40.0
    Gc0::Float64 = 10.0
    maxiter::Int = 10000
    output::String = ""
    verbose::Bool = true
end

function DyadInterface.run_analysis(spec::RunLatentNeuralODESpec)
    base_spec = LatentNeuralODESpec(;
        name = :LatentNeuralODEAnalysis,
        data = spec.data,
        spatial_cols = spec.spatial_cols,
        input_col = spec.input_col,
        time_col = spec.time_col,
        reference_temp = spec.reference_temp,
        latent_dims = spec.latent_dims,
        hidden_enc = spec.hidden_enc,
        hidden_dyn = spec.hidden_dyn,
        hidden_dec = spec.hidden_dec,
        n_epochs = spec.n_epochs,
        lr = spec.lr,
        n_shooting = spec.n_shooting,
        window_len = spec.window_len,
        n_seeds = spec.n_seeds,
        R2_threshold = spec.R2_threshold,
        N_candidates = spec.N_candidates,
        C0_per_node = spec.C0_per_node,
        G0 = spec.G0,
        Gc0 = spec.Gc0,
        maxiter = spec.maxiter,
        output = spec.output,
        verbose = spec.verbose,
    )
    DyadInterface.run_analysis(base_spec)
end

RunLatentNeuralODE(; kwargs...) = DyadInterface.run_analysis(RunLatentNeuralODESpec(; kwargs...))
