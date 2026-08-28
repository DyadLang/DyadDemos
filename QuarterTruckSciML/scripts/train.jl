#=
Train the full-NN gray-box truck from scratch.

Stage 1: Adam optimizer, 5000 iterations, learning rate 1e-3 — fast global
descent on the parameter space. Writes `assets/data/nn_weights_full_sin.csv`.

Stage 2: LBFGS, 200 iterations, initialized from Stage 1 — refines to machine
precision on the smooth bowl. Writes `assets/data/nn_weights_full_sin_lbfgs.csv`,
overwriting any pre-shipped weights.

End-to-end this typically takes ~5 minutes on a modern CPU. The pre-trained
weights shipped with the package are the LBFGS output from a previous run;
this script lets you reproduce them or retrain after model changes.
=#

using QuarterTruckSciML
using DyadInterface

# The generated `TruckFullNNTrainingAnalysis(; kwargs...)` shorthand already calls
# `run_analysis(...Spec(...))`, so it runs the training and returns the solution
# directly; `artifacts(result, :ResultsExport)` then writes the weights CSV.
@info "Stage 1: Adam (5000 iters, lr=1e-3)"
adam_result = QuarterTruckSciML.TruckFullNNTrainingAnalysis(; name=:adam)
artifacts(adam_result, :ResultsExport)
@info "Adam done — weights at assets/data/nn_weights_full_sin.csv"

@info "Stage 2: LBFGS refinement (200 iters)"
lbfgs_result = QuarterTruckSciML.TruckFullNNTrainingAnalysisLBFGS(; name=:lbfgs)
artifacts(lbfgs_result, :ResultsExport)
@info "LBFGS done — final weights at assets/data/nn_weights_full_sin_lbfgs.csv"

@info "Training complete. Run scripts/validate.jl to see results on ISO 8608 Class A."
