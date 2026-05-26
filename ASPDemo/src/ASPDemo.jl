module ASPDemo

using DataInterpolations

abstract type AbstractMedium end

include("utilities.jl")
include("ASM1.jl")

include("../generated/module.jl")
    
end # module ASPDemo