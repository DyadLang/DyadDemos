module MotorTemperatureSciML
using CairoMakie

# Public surface: enough to build and fit the TNN inverse problem from outside
# the demo, e.g. as a DyadModelOptimizer test setup. `free_running` is
# deliberately not exported: the demo scripts define their own DataFrame-based
# version of that name.
export TRAIN_PROFILE, TEST_PROFILES, STORY_MAX_TEMP
export profile_uri, profile_path, load_profile, read_parquet, profile_data
export build_system, build_experiment, build_search_space, build_invprob, make_sms
export temperature_states, save_calibration, load_calibration

include("chains.jl")
include("data.jl")
# Story analyses must be defined before the generated code that derives from them.
include("story_analyses.jl")
include("story_plots.jl")
include("../generated/module.jl")
# Needs the generated `Models.Tests.TestTNNProfile`.
include("profiles.jl")

end # module MotorTemperatureSciML