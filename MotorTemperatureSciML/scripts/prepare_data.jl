# Slice drive profiles out of the Paderborn PMSM temperature dataset
# (`measures_v2.csv` — Kirchgässner et al., "Electric Motor Temperature" on
# Kaggle, DOI 10.34740/KAGGLE/DSV/2161054; also shipped with
# github.com/wkirgsn/thermal-nn under data/input/). Sampling is 2 Hz.
#
# Writes assets/data/profile_<id>.csv in the schema `TestTNNProfile.dyad`
# expects:
#
#   time, u_q, coolant, u_d, motor_speed, i_d, i_q, ambient, torque, i_s, u_s,
#   pm, stator_yoke, stator_tooth, stator_winding
#
# `time` is synthesised from the row index at 0.5 s; `profile_id` is dropped;
# `i_s` / `u_s` are the normalised current/voltage magnitudes the reference
# implementation derives as extra features.
#
# Usage (from the package root):
#   julia +dyad-3.3.0 --project scripts/prepare_data.jl --source <path>/measures_v2.csv
#   julia +dyad-3.3.0 --project scripts/prepare_data.jl --source ... --profiles 17,60
#   julia +dyad-3.3.0 --project scripts/prepare_data.jl --source ... --truncate-seconds 7200
#
# The source path can also be given via the MEASURES_V2 environment variable.
# The default profile set (17, 60, 62, 74) regenerates the shipped CSVs.

using CSV, DataFrames

const DST_DIR = normpath(joinpath(@__DIR__, "..", "assets", "data"))
const DT      = 0.5   # Paderborn sampling period [s]

function parse_args(argv)
    profiles = [17, 60, 62, 74]
    truncate = nothing
    source   = get(ENV, "MEASURES_V2", "")
    i = 1
    while i ≤ length(argv)
        a = argv[i]
        if a == "--profiles"
            profiles = parse.(Int, split(argv[i + 1], ',')); i += 2
        elseif a == "--truncate-seconds"
            truncate = parse(Float64, argv[i + 1]); i += 2
        elseif a == "--source"
            source = argv[i + 1]; i += 2
        else
            error("unknown argument: $a")
        end
    end
    return (; profiles, truncate, source)
end

opts = parse_args(ARGS)
isfile(opts.source) || error(
    "measures_v2.csv not found at '$(opts.source)'. Pass --source <path> or set MEASURES_V2. " *
    "Download: https://www.kaggle.com/datasets/wkirgsn/electric-motor-temperature")

@info "Loading Paderborn dataset" source = opts.source
df_all = CSV.read(opts.source, DataFrame)

# Feature scaling constants of the reference implementation (column-wise max
# abs over the full dataset). They also live in dyad/Thermal/Normalizer.dyad,
# where the in-model normalisation of the raw signals happens; `i_s` / `u_s`
# are precomputed here from the *normalised* components because deriving them
# inside the model would add two algebraic equations and turn the ODE into a
# DAE.
const MAX_ABS_I_D = 399.7197265625
const MAX_ABS_I_Q = 369.958343505859
const MAX_ABS_U_D = 164.791656494141
const MAX_ABS_U_Q = 162.266159057617

for pid in opts.profiles
    df = df_all[df_all.profile_id .== pid, :]
    isempty(df) && error("profile_id=$pid not found in $(opts.source)")
    select!(df, Not(:profile_id))
    insertcols!(df, 1, :time => (0:nrow(df) - 1) .* DT)
    df.i_s = @. sqrt((df.i_d / MAX_ABS_I_D)^2 + (df.i_q / MAX_ABS_I_Q)^2)
    df.u_s = @. sqrt((df.u_d / MAX_ABS_U_D)^2 + (df.u_q / MAX_ABS_U_Q)^2)
    if opts.truncate !== nothing
        df = df[1:min(nrow(df), floor(Int, opts.truncate / DT) + 1), :]
    end
    select!(df, [:time, :u_q, :coolant, :u_d, :motor_speed, :i_d, :i_q, :ambient,
                 :torque, :i_s, :u_s, :pm, :stator_yoke, :stator_tooth, :stator_winding])
    dst = joinpath(DST_DIR, "profile_$(pid).csv")
    CSV.write(dst, df)
    @info "Wrote profile" profile_id = pid dst rows = nrow(df) span_s = (df.time[1], df.time[end])
end
