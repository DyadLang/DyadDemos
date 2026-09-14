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
