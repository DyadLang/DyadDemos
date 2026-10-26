# Dyad 3.5 follow-up: initial failure inventory

Baseline of this inventory: `dyad-3.5` at `97c9fac` (draft PR #41), compared
with the preserved original projects on Dyad 3.4. This initial inventory uses
the retained measured results in each project's `docs/upgrade-3.5-validation.md`
and `.task/`; it is not a claim that every workflow has just been rerun.
There are no hosted GitHub CI results. A workflow file exists, but its presence
does not establish a successful run.

| Analysis or workflow | On 3.5 at start of follow-up | Also on 3.4? | Likely cause / next check |
|---|---|---|---|
| Driveline stage 1 calibration | `Infeasible`; objective 0.0959869, finite parameters | Yes: `Infeasible`, objective 0.0959860 | Calibration formulation, scaling or optimizer termination; diagnose gradients/bounds and chained fit rather than accept status. |
| QuarterTruck physical calibration | `MaxIters` after 100 iterations; objective 0.0764900 | Yes: same 100-iteration limit, objective 0.0764898 | Conditioning/stopping behavior in a highly accurate synthetic-data fit; inspect parameter scales, sensitivities and formulation. |
| QuarterTruck full NN training (5000 Adam / 200 LBFGS) | Unvalidated: interrupted after about 23 minutes without result | Also unvalidated: interrupted after about 17 minutes | Gradient evaluation cost; 25 Adam iterations previously took 149.50 s in optimizer. Full-run duration is unknown. Profile before making convergence claims. |
| QuarterTruck bounded training (25 / 10) | Adam `Default` at budget, LBFGS `Success`; objective 5.11265 | Adam `Default`, LBFGS `MaxIters`; objective 3.98548 | Short stochastic/AD-dependent optimization trajectories; +28.3% final objective is not evidence of full-training equivalence. |
| Motor `Story.A2_TrainTNNQuick` | `ConvergenceFailure` after six Adam steps; objective 2.55313 | Yes: `ConvergenceFailure`, objective 2.54926 | One augmented-Lagrangian outer iteration and two epochs are insufficient to establish convergence; inspect continuity constraints and training implementation. |
| Driveline/QuarterTruck generated dataset analyses after raw compiler output | Construction fails without `fix_analysis_codegen.jl` | No equivalent workaround was required in original 3.4 project | RC2 compiler emits a UnionAll `DyadTimeseries` symbolic structural-parameter annotation instead of the concrete value type; upstream dyad-lang #1958. Existing workaround restores construction but must be reapplied after compile-on-save. |
| Optional `MultibodyComponents.Render` extension (seen with Motor Makie plots) | Dependency-load diagnostic; numerical solve and PNG export still succeed | Not yet isolated on original 3.4 | Upstream extension dependency declaration/load context; needs a minimal reproducer, separate from numerical failures. |
| MakieWebinar GLMakie/interactive windows | Headless initialization diagnostic (`DISPLAY` absent) | Same environmental restriction; old GUI session not tested | No display in runner. Numerical analyses and headless PID tuning succeeded; interactive behavior is unvalidated. |
| Analysis notebooks | Not executed previously; all eight contain an explicit analysis-name placeholder; HL20 has no declared analyses | Templates also need selection on 3.4; runtime comparison pending | Templates are not unattended end-to-end workflows. Audit orchestrator versions, select real analyses where defined, and distinguish missing selection from a runtime defect. |
| Documentation HTML | Full build unvalidated; docs environments instantiated, compiler document smoke checks passed | Full old build unvalidated | No measured HTML-build failure yet. Audit actual build entry points and execute documentation examples. |
| Motor standalone Julia short/full training, PyTorch trainer/tests, data preparation, animation | Previously not run | Previously not run | Coverage gap, not a confirmed failure. Audit scripts and run feasible headless checks. |
| Other GUI dashboards, live sliders, video/animation rendering and manual plotting scripts | Previously unvalidated except documented headless exporters | Previously unvalidated | Coverage gap/environmental requirements. Audit available entry points; do not label unexecuted workflows as passing or broken. |
| HL20 design-brief full-flight analyses | Not implemented (zero declared analyses); aerodynamic core and 20 tests pass | Not implemented; original standalone core construction was already fixed in #41 | Future-feature brief, not a newly failing analysis. |

All 14 package test suites had passed (3412 assertions), and no other declared
numerical analysis failure was recorded among the 74 exercised analyses. Prior
LazyArrays/Parquet2 compatibility, CSV-extension dependencies, Makie oscillator
initialization and PID tuning failures were already fixed in #41; they are not
outstanding failures. Full 5000/200 training and unexecuted workflows must remain
explicitly unvalidated until measured.

Four Codex children are now investigating Driveline, QuarterTruck, Motor, and
the documentation/notebook/compiler workflows independently in the shared
checkout. The parent checks repository validation orchestration. Final results
and newly discovered failures will be appended after those investigations.


## Interim measured results (2026-10-26)

This update records completed child work while full training and dependency access
are pending. It does not supersede the final per-project evidence.

- **Driveline fixed:** original failure reproduced on both 3.4 and 3.5.
  Under-resolved dynamics caused the optimizer failure. Stage 1/2 step limits of
  0.0001/0.001 seconds give genuine standalone and chained convergence without
  changing data, bounds, tolerances or budgets. All seven analyses and 27 tests
  pass; chained calibration took 172.475 s. See
  `DrivelineSciML/docs/followup-validation.md`.
- **QuarterTruck calibration fixed:** squared residuals remove the norm cusp;
  the stricter gradient tolerance gives `Success` in 43/100 iterations,
  worst parameter error 0.08273%, optimizer time 104.027 s. The original
  3.4 100-iteration failure was reproduced.
- **QuarterTruck full training completed:** 5000 Adam steps followed by LBFGS
  `Success` in 2/200 iterations, total 4958.64 s. Adam retains its upstream
  `Default` status; it is a budget-completed checkpoint, not converged training.
  Final objective 0.38384846067991113 was independently replayed successfully.
  Held-out normalized RMS errors are 11.4982%, 57.6970%, 44.4553%: better
  than linear, still substantial and not uniformly better than shipped weights.
  Full 3.4 retraining remains unvalidated. Data and shipped weights are unchanged.
- **Motor:** quick-training failure remains unresolved and reproduces on both
  versions. Python audit awaits task-local CPU PyTorch download access.
- **FrictionBrake fixed:** original vehicle-cycle default solver exhausts its
  step budget on both versions; heat-flow plots used nonexistent `.Q` fields.
  Rodas5P plus `.Q_flow` gives full-horizon success; 21/21 tests pass. Maximum
  speed/disk/pad differences against a tighter reference are 1.94057e-6 m/s,
  9.81024e-5 K and 2.70796e-5 K.
- **Documentation:** strict generated HTML passes for CoffeeMug, Turkey,
  ThermalHouse and DynamicSteadyState. HybridTransmission, PassiveSuspension,
  FIRFilterComponents, SatelliteGNC and HL20 hit upstream symbolic-parameter
  cycles. Relevant example blocks pass on original 3.4 for the first four;
  original HL20 fails earlier on undefined `ChallengeComponent`.
  FrictionBrake hits Documenter's unchanged HTML size limit (same SVG fixture
  also fails on 3.4). After artifact access was granted, MakieWebinar generation
  passed in 24.379 s; its strict HTML build failed in 73.976 s on the same
  upstream `Hello` parameter cycle. All 12 emitted component blocks pass on
  original 3.4; 11 pass on rc2 and `Hello` fails.
- **Notebook/scripts:** five selected notebook solves and HTML artifacts pass;
  standalone headless simulation scripts pass. Full 240-frame GIF export takes
  204.705 s; Cairo SVG export takes 50.202 s. Notebook frontends and interactive
  windows remain unvalidated. HL20 has no declared analyses.
- **Compiler:** the raw rc2 timeseries annotation failure is isolated; original
  3.4 spec construction passes. Existing workaround remains necessary; issue
  drafts reference already-open dyad-lang #1958. Render extension loading
  succeeds in an explicit environment, so its earlier diagnostic is not a
  confirmed remaining numerical defect.

Detailed coverage, baseline qualifications, exact commands and issue drafts:
`followup-workflows.md`, `followup-upstream-issues.md`, and each project's
`docs/followup-validation.md`. No new branch has been pushed yet. The combined
fixes still require independent Claude review.

## Final follow-up inventory

The initial and interim sections above preserve what was known at those times.
This table supersedes their outstanding-failure classifications. Exact commands,
metrics and baseline qualifications are in the linked reports. No hosted CI or
unexecuted workflow is counted as passing.

| Analysis or workflow | Final 3.5 result | Original 3.4 comparison | Cause and disposition |
|---|---|---|---|
| Driveline stage 1 and chained stage 2 | **Fixed:** both converge; chained calibration 172.475 s; 27/27 tests | Original stage 1 also `Infeasible` | Under-resolved forcing/relaxation made optimization unreliable. Integration step limits resolve the dynamics; data, bounds, optimizer tolerances and budgets unchanged. Gamma recovery still has 11.27% bias. [Evidence](DrivelineSciML/docs/followup-validation.md). |
| QuarterTruck physical calibration | **Fixed:** `Success`, 43/100 iterations, 104.027 s optimizer; worst parameter error 0.08273%; 19/19 tests | Original also hits its 100-iteration limit | Smooth squared residual loss removes norm cusp; stricter gradient tolerance resolves weak sensitivities. [Evidence](QuarterTruckSciML/docs/followup-validation.md). |
| QuarterTruck full 5000/200 training | **Completed:** 4958.64 s; LBFGS `Success` after 2/200; independent replay `Success` | Full old run remains unvalidated; bounded old Adam also returns `Default` | ForwardDiff makes full validation practical. Adam completes 5000 updates with upstream `Default`, preserved as a budget checkpoint rather than convergence. Library adapter omits explicit retcode; [issue draft](QuarterTruckSciML/docs/followup-upstream-issues.md). Held-out RMS 11.4982% / 57.6970% / 44.4553% remains substantial. |
| Motor quick training and A2/A3 story | **Fixed:** concrete A2 `Success`, 324 updates, 1210.1 s optimizer; A3 reload exactly matches; 102/102 Julia tests | Original quick fit also `ConvergenceFailure`; corrected setup succeeds on both versions | Six updates were insufficient; measured state initialization and a decaying Adam rate close the original 0.2 °C continuity constraint. Independently recomputed with tighter ODE tolerance. Unseen-profile RMS remains 8.5–27.8 °C. [Evidence](MotorTemperatureSciML/docs/followup-validation.md). |
| Motor data-based shooting initialization | **Avoided in demo; upstream defect remains** | Identical permutation error reproduced on both versions | Library incorrectly assumes declaration and ODE-state order agree. Demo resolves aliases and orders state/data pairs correctly; all 380 initial states checked. [Unfiled draft](MotorTemperatureSciML/docs/followup-upstream-issues.md). |
| Motor calibration validator plots | **Fixed:** four headless PNGs export | Old script has same GR assumption; original plotting command not rerun on 3.4 | `gr()` requested undeclared GR backend. Use already-declared CairoMakie and check ODE return codes. |
| Motor animation calibration | **Unfixed:** `ConvergenceFailure` after original 990 updates, 2305.5 s; reconstructed gap 0.06311 °C | Original strict-budget animation not rerun on 3.4; no upgrade-regression claim | Original 0.000002 °C requirement is below configured ODE tolerance and stochastic-update scale. Criterion unchanged; actual status/gap displayed on exported diagnostic GIFs. Rendering succeeds with three captured frames; default full-length movie unvalidated. |
| Motor PyTorch reference, data preparation | **Executed:** 3/3 Python tests; all 100 training epochs in 229.2 s; four finite predictions exported; subset preparation verified | No separate old-runtime Python run; these scripts do not use Dyad | Reference reproduces shipped predictions, including poor held-out generalization. Complete original 69-profile CSV unavailable; preparation tested with a four-profile fixture, not complete-source provenance. |
| FrictionBrake vehicle-cycle solve and heat plots | **Fixed:** full 2000 s horizon, finite states, 21/21 tests | Default solver exhausts steps on both; old plot also uses absent fields | Stiff dynamics need Rodas5P; heat-flow field is `.Q_flow`. Tighter reference agrees within 1.95e-6 m/s and 9.82e-5 K. [Evidence](FrictionBrakeDemo/docs/followup-validation.md). |
| Driveline/QuarterTruck raw rc2 codegen | **Unfixed upstream:** documented post-generation workaround still required | Original 3.4 spec construction passes | Structural `DyadTimeseries` becomes symbolic UnionAll annotation. Supplemental [draft](followup-upstream-issues.md) for existing dyad-lang #1958; correct demo data/model retained. |
| Generated strict HTML: HybridTransmission, PassiveSuspension, FIRFilterComponents, SatelliteGNC, MakieWebinar, HL20 | **Unfixed upstream:** cyclic parameter bindings in emitted examples | Same affected example blocks pass on 3.4 except HL20, which fails earlier on old missing `ChallengeComponent` | Generated same-name symbolic constructor arguments create self-reference. No examples suppressed or warning downgrades accepted. [Draft and reproducers](followup-upstream-issues.md). |
| Generated strict FrictionBrake HTML | **Unfixed:** default HTML size limit exceeded | Same generated SVG fixture also fails on 3.4; old compiler generation not independently rerun | Large inline SVG produces 744.67 KiB page. Correct icon retained; external asset emission belongs in generator. [Unfiled draft](followup-upstream-issues.md). |
| Generated strict HTML: CoffeeMug, Turkey, ThermalHouse, DynamicSteadyState | **Pass** | Relevant original example blocks pass; full old sites unvalidated | Docs environments now declare packages used by their examples. |
| Analysis notebook templates | **Fixed runnable defaults:** five selected notebook solves and HTML artifacts pass | Templates also required selection on 3.4 | Select real analyses, update stale Orchestrator fallback. HL20 has zero declared analyses; its selection cells remain inapplicable. Frontend interaction unvalidated. [Coverage](followup-workflows.md). |
| DynamicSteadyState GIF and headless scripts | **Pass:** full 240-frame GIF 204.705 s; Cairo SVG 50.202 s; thermal/mechanical scripts pass | Old two-frame GIF smoke passes; full old export unvalidated | Earlier process timeouts were incomplete validation. Full rc2 artifacts now measured. |
| Optional Render extension and GUI dashboards/windows | Render extension import succeeds; GUI unvalidated headlessly | Direct GLMakie import fails without DISPLAY on both; old distribution lacks MultibodyComponents | Earlier dependency diagnostic not reproduced, so no invented defect report. Interactive scripts and notebook frontends require a display/frontend. [Limits](followup-workflows.md). |

Motor's standalone full-budget trainer is undergoing its final check; quick
training, the concrete A1–A7 story and the separate strict animation trajectory
have the measured results above. The final report will record the full trainer
outcome separately. Shipped datasets, calibration weights and success thresholds
are preserved. New upstream issue text is drafted only; nothing has been filed.
