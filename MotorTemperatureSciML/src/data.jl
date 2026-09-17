using TOML: TOML
using Parquet2: Parquet2
using DyadData: DyadData

"""
    profile_table(uri) -> Parquet2.Dataset

Open the Parquet drive profile behind `uri` (a `dyad://` asset URI or a plain
path) as a Tables.jl source for `DyadData.DyadTimeseries`.

The DyadData shipped with dyad 3.3 only parses delimited text files itself.
Once a DyadData release reads Parquet natively, `TestTNNProfile.dyad` can pass
`data_file` straight to `DyadTimeseries` and this helper goes away.
"""
function profile_table(uri::AbstractString)
    path = startswith(uri, "dyad://") ? DyadData.resolve_dyad_uri(uri[8:end]) : uri
    isfile(path) || error("Drive profile not found: `$(path)` (from `$(uri)`)")
    return Parquet2.Dataset(path)
end

# ── Feature scaling ─────────────────────────────────────────────────────────
# The reference implementation normalises every non-temperature signal by its
# max abs over the whole dataset (`TNN_pytorch.ipynb` cell 5:
# `data[non_temperature_cols] /= data[non_temperature_cols].abs().max()`), and
# temperatures by MAX_TEMP. Those denominators are a property of the dataset,
# so `scripts/prepare_data.jl` derives them when it slices the profiles and
# writes them next to the Parquet files. Everything that normalises reads them
# from there: `dyad/Thermal/Normalizer.dyad` for the in-model scaling of the
# raw signals, `prepare_data.jl` for the precomputed `i_s` / `u_s`, and
# `scripts/train_pytorch_reference.py` for the reference training.
#
# They must not be hardcoded: earlier revisions carried max-abs values of the
# synthetic placeholder data this demo was first prototyped against, which left
# `torque` scaled 8.6x too small and `motor_speed` 4.25x too large.

const NORMALIZATION_URI = "dyad://MotorTemperatureSciML/data/normalization.toml"

"""
    reference_max_abs() -> NamedTuple

Per-channel normalisation denominators, as derived from the source dataset by
`scripts/prepare_data.jl` and shipped in `assets/data/normalization.toml`.
"""
function reference_max_abs()
    path = DyadData.resolve_dyad_uri(NORMALIZATION_URI[8:end])
    isfile(path) || error("Normalisation constants not found: `$(path)`. " *
                          "Run `scripts/prepare_data.jl --source <measures_v2.csv>` to derive them.")
    tbl = TOML.parsefile(path)["max_abs"]
    return (; (Symbol(k) => Float64(v) for (k, v) in sort(collect(tbl)))...)
end

const REFERENCE_MAX_ABS = reference_max_abs()
