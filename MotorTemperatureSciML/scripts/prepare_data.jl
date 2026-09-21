# Slice drive profiles out of the Paderborn PMSM temperature dataset
# (`measures_v2.csv` — Kirchgässner et al., "Electric Motor Temperature" on
# Kaggle, DOI 10.34740/KAGGLE/DSV/2161054; also shipped with
# github.com/wkirgsn/thermal-nn under data/input/). Sampling is 2 Hz.
#
# Writes assets/data/profile_<id>.parquet (zstd-compressed, Float64) in the
# schema `TestTNNProfile.dyad` expects:
#
#   time, u_q, coolant, u_d, motor_speed, i_d, i_q, ambient, torque, i_s, u_s,
#   pm, stator_yoke, stator_tooth, stator_winding
#
# `time` is synthesised from the row index at 0.5 s; `profile_id` is dropped;
# `i_s` / `u_s` are the normalised current/voltage magnitudes the reference
# implementation derives as extra features.
#
# Usage (from the package root):
#   julia +dyad-3.4.0 --project scripts/prepare_data.jl --source <path>/measures_v2.csv
#   julia +dyad-3.4.0 --project scripts/prepare_data.jl --source ... --profiles 17,60
#   julia +dyad-3.4.0 --project scripts/prepare_data.jl --source ... --truncate-seconds 7200
#
# The source path can also be given via the MEASURES_V2 environment variable.
# The default profile set (17, 60, 62, 74) regenerates the shipped files.
#
# Parquet keeps the full Float64 precision of the source at about a third of
# the CSV size, and reads with one call from Julia (Parquet2.jl) and Python
# (pandas / pyarrow) alike.

using CSV, DataFrames, Parquet2

const DST_DIR = normpath(joinpath(@__DIR__, "..", "assets", "data"))
const DT      = 0.5   # Paderborn sampling period [s]
const MAX_TEMP_DEGC = 200.0   # temperature normalisation of the reference

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

# Feature scaling of the reference implementation: every non-temperature signal
# is divided by its max abs over the whole dataset, temperatures by 200 degC
# (`TNN_pytorch.ipynb` cell 5). Derived here rather than hardcoded, and written
# to assets/data/normalization.toml so that dyad/Thermal/Normalizer.dyad (the
# in-model scaling of the raw signals) and scripts/train_pytorch_reference.py
# use the same denominators. `i_s` / `u_s` are precomputed here from the
# *normalised* components because deriving them inside the model would add two
# algebraic equations and turn the ODE into a DAE.
const TEMPERATURE_COLS     = [:pm, :stator_yoke, :stator_tooth, :stator_winding,
                              :ambient, :coolant]
const NON_TEMPERATURE_COLS = [:u_q, :u_d, :motor_speed, :i_d, :i_q, :torque]

max_abs = Dict(String(c) => maximum(abs, skipmissing(df_all[!, c]))
               for c in NON_TEMPERATURE_COLS)

let path = joinpath(DST_DIR, "normalization.toml")
    open(path, "w") do io
        println(io, "# Normalisation denominators derived from the source dataset by")
        println(io, "# scripts/prepare_data.jl. Do not edit by hand: regenerating the")
        println(io, "# profiles regenerates this file, and every consumer reads it.")
        println(io, "#")
        println(io, "# source = ", repr(basename(opts.source)))
        println(io, "# rows   = ", nrow(df_all))
        println(io, "# profiles = ", length(unique(df_all.profile_id)))
        println(io)
        println(io, "max_temp = ", MAX_TEMP_DEGC)
        println(io)
        println(io, "[max_abs]")
        for c in NON_TEMPERATURE_COLS
            println(io, c, " = ", repr(max_abs[String(c)]))
        end
    end
    @info "Wrote normalisation constants" path max_abs
end

for pid in opts.profiles
    df = df_all[df_all.profile_id .== pid, :]
    isempty(df) && error("profile_id=$pid not found in $(opts.source)")
    select!(df, Not(:profile_id))
    insertcols!(df, 1, :time => (0:nrow(df) - 1) .* DT)
    df.i_s = @. sqrt((df.i_d / max_abs["i_d"])^2 + (df.i_q / max_abs["i_q"])^2)
    df.u_s = @. sqrt((df.u_d / max_abs["u_d"])^2 + (df.u_q / max_abs["u_q"])^2)
    if opts.truncate !== nothing
        df = df[1:min(nrow(df), floor(Int, opts.truncate / DT) + 1), :]
    end
    select!(df, [:time, :u_q, :coolant, :u_d, :motor_speed, :i_d, :i_q, :ambient,
                 :torque, :i_s, :u_s, :pm, :stator_yoke, :stator_tooth, :stator_winding])
    dst = joinpath(DST_DIR, "profile_$(pid).parquet")
    Parquet2.writefile(dst, df; compression_codec = :zstd)
    @info "Wrote profile" profile_id = pid dst rows = nrow(df) span_s = (df.time[1], df.time[end])
end
