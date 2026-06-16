#=
Generate synthetic measurements for the two-stage driveline calibration demo.

Simulates the truth Maxwell-Bouc-Wen isolator (hidden parameters below) on the
two calibration excitation events and saves the encoder measurements in
DyadData CSV format:

    Event 1 (Stage 1): low-amplitude chirp, 1→500 Hz, ±2 Nm on 30 Nm mean, 5 s
    Event 2 (Stage 2): slow cycling, 1 Hz sine, ±100 Nm, 5 s

Truth (hidden) isolator parameters vs. the nominal model defaults:

    model.k1       = 200.0 → 300.0   (Maxwell stiffness)
    model.c1       =   2.0 →   1.0   (Maxwell damping)
    model.alpha    =  30.0 →  50.0   (Bouc-Wen torque scale)
    model.A_bw     =   1.0 →   1.0   (Bouc-Wen flow gain)
    model.beta_bw  =   3.0 →   5.0   (Bouc-Wen saturation)
    model.gamma_bw =   0.3 →   0.5   (Bouc-Wen shape)

Measured outputs (clean, no noise): omega_eng = J_eng.w, omega_load = J_load.w,
plus their difference delta_w (the Stage 1 calibration target — insensitive to
the common-mode speed ramp caused by the 30 Nm mean torque).

Outputs:
    assets/data/chirp_measurements.csv       (5001 rows over 5 s @ 1 kHz)
    assets/data/slow_cycle_measurements.csv  (1001 rows over 5 s @ 200 Hz)
=#

using DrivelineSciML
using ModelingToolkit
using OrdinaryDiffEqDefault
using CSV, DataFrames

const OUTDIR = joinpath(@__DIR__, "..", "assets", "data")
isdir(OUTDIR) || mkpath(OUTDIR)

const TRUTH = (k1 = 300.0, c1 = 1.0, alpha = 50.0, A_bw = 1.0, beta_bw = 5.0, gamma_bw = 0.5)

function simulate_and_export(harness, overrides_fn, stop, saveat, filename)
    sys = mtkcompile(harness)
    # Truth values applied via ODEProblem parameter overrides on the compiled
    # system — these must target the top-level knobs (the same ones the
    # calibration analyses search over), not the `final`-bound inner
    # `isolator.*` parameters.
    prob = ODEProblem(sys, overrides_fn(sys), (0.0, stop); fully_determined = true)
    sol = solve(prob; abstol = 1e-9, reltol = 1e-9, saveat)
    df = DataFrame(
        timestamp          = sol.t,
        var"omega_eng(t)"  = sol[sys.model.J_eng.w],
        var"omega_load(t)" = sol[sys.model.J_load.w],
        var"delta_w(t)"    = sol[sys.model.delta_w],
    )
    outpath = joinpath(OUTDIR, filename)
    CSV.write(outpath, df)
    @info "Wrote $(nrow(df)) rows × $(ncol(df)) cols → $outpath"
    sol
end

@info "Event 1: low-amplitude chirp (truth isolator)"
@named h_chirp = DrivelineSciML.TestDrivelineChirp()
simulate_and_export(h_chirp,
    sys -> [
        sys.model.k1       => TRUTH.k1,
        sys.model.c1       => TRUTH.c1,
        sys.model.alpha    => TRUTH.alpha,
        sys.model.A_bw     => TRUTH.A_bw,
        sys.model.beta_bw  => TRUTH.beta_bw,
        sys.model.gamma_bw => TRUTH.gamma_bw,
    ],
    5.0, 0.001, "chirp_measurements.csv")

@info "Event 2: slow cycling (truth isolator)"
# k1/c1 live at harness level here (Stage 2 freezes them to the Stage 1 fit).
@named h_slow = DrivelineSciML.TestDrivelineSlowCycle()
simulate_and_export(h_slow,
    sys -> [
        sys.k1             => TRUTH.k1,
        sys.c1             => TRUTH.c1,
        sys.model.alpha    => TRUTH.alpha,
        sys.model.A_bw     => TRUTH.A_bw,
        sys.model.beta_bw  => TRUTH.beta_bw,
        sys.model.gamma_bw => TRUTH.gamma_bw,
    ],
    5.0, 0.005, "slow_cycle_measurements.csv")

@info "Truth values to recover: k1=$(TRUTH.k1), c1=$(TRUTH.c1), alpha=$(TRUTH.alpha), A_bw=$(TRUTH.A_bw), beta_bw=$(TRUTH.beta_bw), gamma_bw=$(TRUTH.gamma_bw)"
