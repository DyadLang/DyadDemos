# The demo as a sequence of Dyad analyses (dyad/Story/Story.dyad), run from
# Julia. Each analysis is one call; every one has a SimulationSolutionPlot
# artifact, and this script saves every plot artifact as a PNG.
#
#   JULIA_NUM_THREADS=8 julia --project scripts/story.jl
#
# Output: runs/story/<Analysis>_<Artifact>.png and the RMS tables on stdout.
# For the full-budget calibration behind the README results, run
# scripts/train_stochastic_ms.jl.

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

@info "2 · Training"
training = save_plots(A2_TrainTNNQuick(), "A2_TrainTNNQuick")
# Training curves as CSV, so the figures can be redrawn without retraining.
CSV.write(joinpath(OUT, "A2_TrainTNNQuick_LossTable.csv"), artifacts(training, :LossTable))
CSV.write(joinpath(OUT, "A2_TrainTNNQuick_OuterIterationTable.csv"), artifacts(training, :OuterIterationTable))

@info "3 · After training"
save_plots(A3_RetrainedTNN(), "A3_RetrainedTNN")      # the run above
save_plots(A4_CalibratedTNN(), "A4_CalibratedTNN")    # the shipped fit
for (A, label) in ((A5_CalibratedTNNProfile60, "A5_CalibratedTNNProfile60"),
                   (A6_CalibratedTNNProfile62, "A6_CalibratedTNNProfile62"),
                   (A7_CalibratedTNNProfile74, "A7_CalibratedTNNProfile74"))
    save_plots(A(), label)
end
