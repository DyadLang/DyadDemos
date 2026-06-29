# Hand-authored module extension, included by generated/module.jl inside `module HL20Demo`.
# Loads the pre-provided DAVE-ML loader / registered symbolic functions and exposes
# them under the `ChallengeComponent` name expected by dyad/shared/HL20Aero.dyad.
include(joinpath(@__DIR__, "..", "src", "shared_utils.jl"))
const ChallengeComponent = @__MODULE__
export ChallengeComponent
