# The demo as a sequence of Dyad analyses (dyad/Story/Story.dyad), run from
# Julia. Each analysis is one call; every one has a SimulationSolutionPlot
# artifact, and this script saves every plot artifact as a PNG.
#
#   JULIA_NUM_THREADS=8 julia --project scripts/story.jl            # quick training run
#   TNN_STORY_FULL=1 JULIA_NUM_THREADS=8 julia --project scripts/story.jl   # 21-minute run
#
# Output: runs/story/<Analysis>_<Artifact>.png and the RMS tables on stdout.

using MotorTemperatureSciML
using MotorTemperatureSciML.Story
using DyadInterface: artifacts, AnalysisSolutionMetadata, ArtifactType
using CairoMakie
using CSV

const OUT = normpath(joinpath(@__DIR__, "..", "runs", "story"))
mkpath(OUT)

function save_plots(result, label)
    for a in AnalysisSolutionMetadata(result).artifacts
        a.type == ArtifactType.PlotlyPlot || continue
        path = joinpath(OUT, "$(label)_$(a.name).png")
        save(path, artifacts(result, a.name); px_per_unit = 2)
        println("  wrote ", path)
    end
    display(result); println()
    return result
end

@info "1 · Before training"
untrained = save_plots(A1_UntrainedTNN(), "A1_UntrainedTNN")

@info "2 · Training" full = get(ENV, "TNN_STORY_FULL", "0") == "1"
training = get(ENV, "TNN_STORY_FULL", "0") == "1" ? A3_TrainTNN() : A2_TrainTNNQuick()
train_label = get(ENV, "TNN_STORY_FULL", "0") == "1" ? "A3_TrainTNN" : "A2_TrainTNNQuick"
save_plots(training, train_label)
# Training curves as CSV, so the figures can be redrawn without retraining.
CSV.write(joinpath(OUT, "$(train_label)_LossTable.csv"), artifacts(training, :LossTable))
CSV.write(joinpath(OUT, "$(train_label)_OuterIterationTable.csv"), artifacts(training, :OuterIterationTable))

@info "3 · After training"
save_plots(A4_RetrainedTNN(), "A4_RetrainedTNN")          # the run above
save_plots(A5_CalibratedTNN(), "A5_CalibratedTNN")        # the shipped 21-minute fit
for (A, label) in ((A6_CalibratedTNNProfile60, "A6_CalibratedTNNProfile60"),
                   (A7_CalibratedTNNProfile62, "A7_CalibratedTNNProfile62"),
                   (A8_CalibratedTNNProfile74, "A8_CalibratedTNNProfile74"))
    save_plots(A(), label)
end
