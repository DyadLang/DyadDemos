# AEB and Euro NCAP CCRs on the Dyad sedan: the runs behind the demo.
#   julia --project=validation/sedan_aeb_ccrs scripts/aeb_walkthrough.jl
using SedanDemo
V = joinpath(@__DIR__, "..", "validation", "sedan_aeb_ccrs")
jl = `$(Base.julia_cmd()) --project=$V`

# CCRs test at 50 km/h, 50 % impact location
nominal = SedanCCRsTest(v_test_kmh = 50, impact_pct = 50)
# Same test with the AEB trigger at 9 m/s² instead of 5
late = SedanCCRsTest(v_test_kmh = 50, impact_pct = 50, a_on = 9)
# 56-test grid, Euro NCAP score and trigger study on SedanCCRs; rewrites the records
run(`$jl $V/ccrs_sweep.jl --gate --sensitivity`)
# 3D video of both 50 km/h tests; rewrites ccrs_aeb_50kmh.mp4
run(`$jl $V/animate_ccrs.jl`)
