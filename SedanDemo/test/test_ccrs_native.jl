using Test, TOML, SciMLBase
using SedanDemo

# The native CCRs analysis at its defaults: 50 km/h, 50 % impact location, a_on = 5 m/s².
@testset "SedanCCRsTest native analysis" begin
    r = SedanCCRsTest()
    sol = r.sol
    @test SciMLBase.successful_retcode(sol)
    # Each wishbone loop has two assemblies; the start must be the settled one the guesses name.
    # With the closed-form loop the upper-arm angle is the assembly's revolute angle.
    @testset "corner $c starts at its settled suspension pose" for c in ("fl", "fr", "rl", "rr")
        p = "sedan.vehicle.corner_$c.suspension."
        @test sol(0.0, idxs = getproperty(r, p * "loop.revolute.phi")) ≈
              sol.ps[getproperty(r, p * "uca_rev_phi0")] atol = 1e-3
    end
    record = TOML.parsefile(joinpath(@__DIR__, "..", "validation", "sedan_aeb_ccrs",
        "ccrs_summary.toml"))["cells"]["50_kmh_+050_pct"]
    gap = sol(range(0, sol.t[end]; step = 1e-3), idxs = getproperty(r, "sensor.gap")).u
    @test minimum(gap) ≈ record["stop_gap_m"] atol = 0.01
end
