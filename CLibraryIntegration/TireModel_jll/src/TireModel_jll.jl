# Stage 3: a local JLL, using JLLWrappers' development override directory.
module TireModel_jll
using Base
using Base: UUID
import JLLWrappers

# The override must exist before JLLWrappers expands its wrapper macros.
include("../deps/build.jl")
JLLWrappers.@generate_main_file_header("TireModel")
JLLWrappers.@generate_main_file("TireModel", UUID("05ed9bfa-a1af-4766-ad26-33c8c1e93ffc"))
end
