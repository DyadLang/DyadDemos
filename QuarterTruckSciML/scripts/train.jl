"""
Train the full-NN gray-box truck from scratch.

Stage 1: Adam optimizer, 5000 iterations, learning rate 1e-3 — fast global
descent on the parameter space. Writes `data/nn_weights_full_sin.csv`.

Stage 2: LBFGS, 200 iterations, initialized from Stage 1 — refines to machine
precision on the smooth bowl. Writes `data/nn_weights_full_sin_lbfgs.csv`,
overwriting any pre-shipped weights.

End-to-end this typically takes ~5 minutes on a modern CPU. The pre-trained
weights shipped with the package are the LBFGS output from a previous run;
this script lets you reproduce them or retrain after model changes.

Run from the package root:
    JULIAUP_SERVER="https://juliahub.com/juliabin" \\
    JULIAUP_DEPOT_PATH="\$HOME/.julia/juliaup-depots/juliahub.com" \\
    julia +dyad-3.0.0 --project scripts/train.jl
"""

using QuarterTruckSciML
using DyadInterface

@info "Stage 1: Adam (5000 iters, lr=1e-3)"
adam_analysis = QuarterTruckSciML.TruckFullNNTrainingAnalysis(; name=:adam)
adam_result = run_analysis(adam_analysis)
@info "Adam done — weights at data/nn_weights_full_sin.csv"

@info "Stage 2: LBFGS refinement (200 iters)"
lbfgs_analysis = QuarterTruckSciML.TruckFullNNTrainingAnalysisLBFGS(; name=:lbfgs)
lbfgs_result = run_analysis(lbfgs_analysis)
@info "LBFGS done — final weights at data/nn_weights_full_sin_lbfgs.csv"

@info "Training complete. Run scripts/validate.jl to see results on ISO 8608 Class A."
