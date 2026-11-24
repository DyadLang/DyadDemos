using SedanDemo
using Test

# Rendering needs a display, so it is opt-in: set ENV["TEST_RENDERING"] = "true" to
# also render the settled sedan with GLMakie (otherwise GLMakie is never loaded)
if get(ENV, "TEST_RENDERING", "false") != "true"
    @info "TEST_RENDERING is not \"true\", skipping rendering tests"
end

@testset "SedanDemo.jl" begin
    @testset "vehicles" begin
        include("test_vehicles.jl")
    end
end
