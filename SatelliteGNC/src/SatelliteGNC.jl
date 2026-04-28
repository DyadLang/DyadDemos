module SatelliteGNC

# Helper functions — must be included BEFORE generated code
include("trajectory_helpers.jl")
include("dynamics_helpers.jl")

include("../generated/module.jl")
    
end # module SatelliteGNC