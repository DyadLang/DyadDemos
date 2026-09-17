# Drive profiles shipped in assets/data/ (see scripts/prepare_data.jl) and the
# compiled harness that is driven by one of them. Included after the generated
# code because `build_system` instantiates the Dyad `TestTNNProfile` component.

using DataFrames: DataFrame, disallowmissing!
using DyadInterface: symbolic_container

# Paderborn PMSM dataset profiles. 17 is the training profile; 60/62/74 are the
# held-out profiles the upstream TNN notebook evaluates on.
const TRAIN_PROFILE = 17
const TEST_PROFILES = (60, 62, 74)

profile_uri(id) = "dyad://MotorTemperatureSciML/data/profile_$(id).parquet"
profile_path(id) = DyadData.resolve_dyad_uri(profile_uri(id)[8:end])

"""
Read a Parquet file into a `DataFrame` (all columns materialised). Columns that
pandas marks as nullable but contain no missing values are narrowed to plain
`Float64` so downstream arithmetic sees no `Missing`.
"""
read_parquet(path) = disallowmissing!(DataFrame(profile_table(path); copycols = true); error = false)

"""Measured drive profile `id` as a `DataFrame` (columns `time`, `pm`, `stator_yoke`, …)."""
load_profile(id) = read_parquet(profile_path(id))

"""
    build_system(profile_id = TRAIN_PROFILE; MAX_TEMP = STORY_MAX_TEMP)

Compiled `TestTNNProfile` system driven by `assets/data/profile_<id>.parquet`.
The harness is instantiated with `data_file` overridden and pushed through its
`TransientAnalysis` so it is compiled exactly the way the Dyad pipeline does it
(the 1 s solve the analysis performs is discarded).
"""
function build_system(profile_id = TRAIN_PROFILE; MAX_TEMP = STORY_MAX_TEMP)
    harness = Models.Tests.TestTNNProfile(;
        name = :TestTNNProfile, data_file = profile_uri(profile_id),
        model__MAX_TEMP = MAX_TEMP)
    result = Models.Tests.TestTNNProfileAnalysis(; model = harness, stop = 1.0)
    return symbolic_container(result)
end
