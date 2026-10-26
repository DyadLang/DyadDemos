# Follow-up review and validation

Base: `dyad-3.5` at `97c9fac`. The failure inventory and per-project validation
reports distinguish optimizer termination, physical recovery, ODE validity and
coverage gaps. Shipped datasets and pretrained weights are unchanged.

## First independent Claude review

The first review inspected the combined diff and ran the Motor tests,
QuarterTruck physical calibration and LBFGS replay, and the FrictionBrake
script. It identified two high and six medium findings, plus smaller checks.
Its detailed scratch report is retained at `.task/followup-claude-review.md`
in the validation workspace.

| Finding | Resolution |
|---|---|
| QuarterTruck LBFGS claimed convergence after a function-change stop | Removed the claim; raw gradient convergence and residual ≤ 1e-8 are required before accepted export. The actual saved result is rejected and no accepted weights are exported. Stationarity remains unresolved. |
| Motor standalone presets presented as validated | README and inventory explicitly state no completed calibration. The last full-run checkpoint at 5902.04 s does not meet the 0.2 °C criterion. No diagnostic checkpoint is exported as a calibration. |
| Motor animation artificial threshold described as a calibration requirement | Declared a fixed-budget diagnostic, preserving the raw failure status and threshold on plots. Its 2305.5 s training run is separate from rendering success. |
| Motor A2 success described as convergence | Qualified as continuity feasibility; stationarity and predictive accuracy are separate. Actual timing, small feasibility margin and held-out errors are reported. Added an unfiled library documentation draft. |
| Inventory inconsistent with committed files and counts | Committed Motor sources and evidence; corrected notebook/test counts and removed pending outcome claims. |
| Satellite generated-documentation failures undercounted | All seven failing blocks documented and independently checked against original 3.4 sources. No complete old-site success claimed. |
| Notebook results lacked acceptance gates | Five runnable notebooks now check actual retcode, full horizon and finite values before plotting; all five executed successfully. |
| Driveline standalone Stage 2 success confused with physical recovery | Validator and reports explicitly identify the near-bound gamma estimate and distinguish it from the chained calibration, whose 11.27% gamma bias remains reported. |

Smaller corrections include strict raw MadNLP checks, validation before exports,
QuarterTruck full-grid/finite-value checks, honest data-generation-error wording,
HL20 notebook cell identifiers, explicit FrictionBrake errors, and a portable
SVG documentation-size reproducer. Motor's residual-row plot correction is a
permutation only; it leaves objectives and the maximum-gap criterion unchanged
and is covered by the passing initialization/order tests.

## Validation evidence and limits

The original upgrade exercised all 14 package suites (3412 assertions) and
74 analyses. Follow-up suites passed for Driveline (27), QuarterTruck (35),
Motor (103 Julia and 3 Python) and FrictionBrake (21). Full numerical runs,
negative export checks, notebooks, headless plots and documentation builds
are detailed in [the inventory](FOLLOWUP_FAILURE_INVENTORY.md),
[workflow report](followup-workflows.md), and per-project reports.

QuarterTruck's 5000-Adam/up-to-200-LBFGS schedule ran in 4958.64 s, but failed
stationarity; it is diagnostic evidence. Motor A2 completed in 1210.1 s,
with its 0.19840 °C gap independently replayed at 0.19848 °C. Motor standalone
full training remains interrupted and unvalidated. GUI frontends, complete
source-data provenance and full original-runtime training/site builds remain
explicit coverage gaps. Compiler/library defects have unfiled drafts linked
from the inventory; no upstream issue was submitted.
