# Calibration follow-up: upstream assessment

No additional upstream defect was identified in the numerical calibration
failure. The demo needed integration step limits for reliable optimization:
Stage 1's 500 Hz forcing and Stage 2's fitted Maxwell relaxation and Bouc-Wen
reversals must be resolved when evaluating the loss and its derivatives.
Changing only these limits gives `SOLVE_SUCCEEDED` with the existing tolerances,
loss, bounds, initial guesses, measurements, and iteration budgets.

The original `Infeasible` result is the library's mapping of MadNLP's
`SEARCH_DIRECTION_BECOMES_TOO_SMALL`; it does not establish physical
infeasibility. The original Stage 1 primal feasibility residual was zero, but
its dual residual was 0.006184987925908159, above the unchanged 0.0001
optimizer tolerance. Preserving and rejecting this status is appropriate.
No issue draft is warranted for this demo configuration error.

The separate RC2 `DyadTimeseries` generated annotation defect remains upstream,
tracked by [dyad-lang #1958](https://github.com/JuliaComputing/dyad-lang/issues/1958).
The parent upgrade task owns that issue follow-up. This change retains
`scripts/fix_analysis_codegen.jl` and applies it after exact RC2 regeneration;
it does not disguise the numerical failure as a code-generation problem.
