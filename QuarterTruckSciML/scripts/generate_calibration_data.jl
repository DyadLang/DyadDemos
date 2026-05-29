"""
Generate synthetic measurements for the calibration demo.

Simulates `TestQuarterTruckNonlinearISOA` on ISO 8608 Class A with the four
calibration parameters perturbed from their nominal values (per Michael
Hoffmann's spec, 2026-04-27):

    model.body.m         = 300.0 → 315.0  (+5%,  mass)
    model.tire_to_body.c = 20e3  → 22e3   (+10%, stiffness)
    model.tire_to_body.d = 1500  → 1800   (+20%, damping)
    model.friction_tb.F_c = 500.0 → 750.0  (+50%, friction)

Three observables are saved as the "measurements" in DyadData format:
    tire_F             — tire-road contact force [N]   (model.tire_to_road.f)
    suspension_travel  — tire-body relative motion [m] (model.tire_to_body.s_rel)
    seat_a             — seat acceleration [m/s²]      (model.seat.a)

Output: `data/calibration_measurements.csv` (1001 rows over 10 s @ 100 Hz).

Run from the package root:
    JULIAUP_SERVER="https://juliahub.com/juliabin" \\
    JULIAUP_DEPOT_PATH="\$HOME/.julia/juliaup-depots/juliahub.com" \\
    julia +dyad-3.0.0 --project scripts/generate_calibration_data.jl
"""

using QuarterTruckSciML
using ModelingToolkit
using OrdinaryDiffEqDefault
using CSV, DataFrames

const OUTDIR = joinpath(@__DIR__, "..", "assets", "data")
isdir(OUTDIR) || mkpath(OUTDIR)

@info "Simulating perturbed-truth nonlinear truck on ISO 8608 Class A"
@named h = QuarterTruckSciML.TestQuarterTruckNonlinearISOA()
sys = mtkcompile(h)

# Truth values applied via ODEProblem parameter overrides on the compiled
# system — these are the same parameter names the calibration analysis searches
# over (see calibration.dyad). The harness uses default values; we override at
# problem-build time to keep the harness shareable with `TestQuarterTruckNonlinearISOA`.
overrides = [
    sys.model.body.m         => 315.0,    # +5%
    sys.model.tire_to_body.c => 22e3,     # +10%
    sys.model.tire_to_body.d => 1800.0,   # +20%
    sys.model.friction_tb.F_c => 750.0,   # +50%
]

prob = ODEProblem(sys, overrides, (0.0, 10.0); fully_determined=true)
sol = solve(prob; saveat=0.01)

df = DataFrame(
    timestamp            = sol.t,
    var"tire_F(t)"             = sol[sys.model.tire_to_road.f],
    var"suspension_travel(t)"  = sol[sys.model.tire_to_body.s_rel],
    var"seat_a(t)"             = sol[sys.model.seat.a],
)

outpath = joinpath(OUTDIR, "calibration_measurements.csv")
CSV.write(outpath, df)
@info "Wrote $(nrow(df)) rows × $(ncol(df)) cols → $outpath"
@info "Truth values to recover: body.m=315, tire_to_body.c=22000, tire_to_body.d=1800, friction_tb.F_c=750"
