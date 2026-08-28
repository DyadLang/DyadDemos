module CFDReducedOrderModeling

include("../generated/module.jl")
include("ThermalNetworkUtils.jl")
include("SVDThermalNetworkAnalysis.jl")
include("LatentNeuralODEAnalysis.jl")
include("DataDrivenPODAnalysis.jl")
include("ROMAnalysisRunners.jl")

export CalibratedThermalNetwork, save_network, load_network

export SVDThermalNetworkAnalysis, SVDThermalNetworkResult, SVDThermalNetworkSolution
export SVDThermalNetworkSpec, AbstractSVDThermalNetworkSpec

export LatentNeuralODEAnalysis, LatentNeuralODEResult, LatentNeuralODESolution
export LatentNeuralODESpec, AbstractLatentNeuralODESpec

export DataDrivenPODAnalysis, DataDrivenPODResult, DataDrivenPODSolution
export DataDrivenPODSpec, AbstractDataDrivenPODSpec

export save_pod_rom, load_pod_rom, simulate_pod_rom

# Pre-configured analysis runners
export RunSVDThermalNetwork, RunSVDThermalNetworkSpec
export RunDataDrivenPOD, RunDataDrivenPODSpec
export RunLatentNeuralODE, RunLatentNeuralODESpec

end # module CFDReducedOrderModeling
