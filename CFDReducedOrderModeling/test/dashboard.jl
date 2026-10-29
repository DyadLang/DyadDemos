module DashboardTests
using Test
include("../app/app.jl")

@testset "Dashboard handlers" begin
    @test router(HTTP.Request("GET", "/")).status == 200
    @test router(HTTP.Request("GET", "/missing")).status == 404
    training = router(HTTP.Request("POST", "/api/training", [], JSON.json(Dict("n_zones" => 4))))
    @test training.status == 200
    @test length(JSON.parse(String(training.body))["t"]) == 1000
    for rom in ("SVD Network", "Neural ODE Network", "POD/DMD")
        response = router(HTTP.Request("POST", "/api/validate", [], JSON.json(Dict("rom_type" => rom))))
        body = JSON.parse(String(response.body))
        @test response.status == 200
        @test length(body["t"]) == 1000
        @test isfinite(body["overall_rms"])
        @test body["overall_rms"] < 5
        @test length(body["cfd_zones"]) == length(body["rom_zones"])
        println(rom, " dashboard validation RMS: ", body["overall_rms"], " K")
    end
end
end
