module MotorTemperatureSciML

include("chains.jl")
include("data.jl")
# Story analyses must be defined before the generated code that derives from them.
include("story_analyses.jl")
include("story_plots.jl")
include("../generated/module.jl")
    
end # module MotorTemperatureSciML