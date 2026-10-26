
using FIRFilterComponents
using Test
    
include("../generated/tests.jl")

include("clocked_filter.jl")
check_clocked_filter(FIRFilterComponents.TestFIRFilterAnalysis())
