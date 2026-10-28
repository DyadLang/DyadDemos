# Dyad 3.5 follow-up: failure inventory

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
| Analysis notebooks | Not executed previously; all seven contain an explicit analysis-name placeholder; HL20 has no declared analyses | Templates also need selection on 3.4; runtime comparison pending | Templates are not unattended end-to-end workflows. Audit orchestrator versions, select real analyses where defined, and distinguish missing selection from a runtime defect. |
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

## Final follow-up inventory

The initial table above preserves the starting coverage and failures.
This table supersedes their outstanding-failure classifications. Exact commands,
metrics and baseline qualifications are in the linked reports. No hosted CI or
unexecuted workflow is counted as passing.

| Analysis or workflow | Final 3.5 result | Original 3.4 comparison | Cause and disposition |
|---|---|---|---|
| Driveline stage 1 and chained stage 2 | **Fixed:** both converge; chained calibration 172.475 s; 27/27 tests | Original stage 1 also `Infeasible` | Under-resolved forcing/relaxation made optimization unreliable. Integration step limits resolve the dynamics; data, bounds, optimizer tolerances and budgets unchanged. Chained gamma recovery still has 11.27% bias; standalone Stage 2 succeeds as an optimizer but fits gamma 0.0513 near its 0.05 lower bound, versus truth 0.5, and is not a successful physical recovery. [Evidence](DrivelineSciML/docs/followup-validation.md). |
| QuarterTruck physical calibration | **Fixed:** `Success`, 43/100 iterations, 104.027 s optimizer; worst parameter error 0.08273%; 35/35 tests | Original also hits its 100-iteration limit | Smooth squared residual loss removes norm cusp; stricter gradient tolerance resolves weak sensitivities. [Evidence](QuarterTruckSciML/docs/followup-validation.md). |
| QuarterTruck full 5000/200 training | **Budget run completed, not stationary:** 4958.64 s; LBFGS `Success` after 2/200 is a function-change stop; independent ODE replay `Success` | Full old run remains unvalidated; bounded old Adam also returns `Default` | ForwardDiff makes full validation practical. Adam completes 5000 updates with upstream `Default`, preserved as a budget checkpoint rather than convergence. LBFGS stops on `f_abstol=1e-4` with gradient norm 0.0943, above its 1e-8 gradient criterion. Adam adapter omits explicit retcode; [issue draft](QuarterTruckSciML/docs/followup-upstream-issues.md). Held-out RMS 11.4982% / 57.6970% / 44.4553% remains substantial. |
| Motor quick training and A2/A3 story | **Continuity failure fixed:** concrete A2 `Success`, 324 updates, 1210.1 s optimizer; A3 reload exactly matches; 103/103 Julia tests | Original quick fit also `ConvergenceFailure`; corrected setup succeeds on both versions | Six updates were insufficient; measured state initialization and a decaying Adam rate close the original 0.2 °C continuity constraint. Independently recomputed with tighter ODE tolerance. AugLag success certifies continuity feasibility, not stationarity or predictive accuracy; training magnet RMS is 3.31 °C versus 0.61 °C for shipped weights. Unseen-profile RMS remains 8.5–27.8 °C. [Evidence](MotorTemperatureSciML/docs/followup-validation.md). |
| Motor data-based shooting initialization | **Avoided in demo; upstream defect remains** | Identical permutation error reproduced on both versions | Library incorrectly assumes declaration and ODE-state order agree. Demo resolves aliases and orders state/data pairs correctly; all 380 initial states checked. [Unfiled draft](MotorTemperatureSciML/docs/followup-upstream-issues.md). |
| Motor calibration validator plots | **Fixed:** four headless PNGs export | Old script has same GR assumption; original plotting command not rerun on 3.4 | `gr()` requested undeclared GR backend. Use already-declared CairoMakie and check ODE return codes. |
| Motor animation diagnostic | **Diagnostic only:** `ConvergenceFailure` after 990 updates, 2305.5 s; reconstructed gap 0.06311 °C | Original fixed-budget animation not rerun on 3.4; no upgrade-regression claim | Its artificial 1e-8 normalized stopping threshold was designed to prevent early stopping, not to accept a calibration. Status/gap are displayed on the diagnostic GIFs. Rendering succeeds with three captured frames; default full-length movie unvalidated. |
| Motor PyTorch reference, data preparation | **Executed:** 3/3 Python tests; all 100 training epochs in 229.2 s; four finite predictions exported; subset preparation verified | No separate old-runtime Python run; these scripts do not use Dyad | Reference reproduces shipped predictions, including poor held-out generalization. Complete original 69-profile CSV unavailable; preparation tested with a four-profile fixture, not complete-source provenance. |
| FrictionBrake vehicle-cycle solve and heat plots | **Fixed:** full 2000 s horizon, finite states, 21/21 tests | Default solver exhausts steps on both; old plot also uses absent fields | Stiff dynamics need Rodas5P; heat-flow field is `.Q_flow`. Tighter reference agrees within 1.95e-6 m/s and 9.82e-5 K. [Evidence](FrictionBrakeDemo/docs/followup-validation.md). |
| Driveline/QuarterTruck raw rc2 codegen | **Unfixed upstream:** documented post-generation workaround still required | Original 3.4 spec construction passes | Structural `DyadTimeseries` becomes symbolic UnionAll annotation. Supplemental [draft](followup-upstream-issues.md) for existing dyad-lang #1958; correct demo data/model retained. |
| Generated strict HTML: HybridTransmission, PassiveSuspension, FIRFilterComponents, SatelliteGNC, MakieWebinar, HL20 | **Unfixed upstream:** cyclic parameter bindings in emitted examples | Tested affected example blocks pass on 3.4 except HL20, which fails earlier on old missing `ChallengeComponent`; all seven SatelliteGNC blocks now have passing 3.4 comparisons | Generated same-name symbolic constructor arguments create self-reference. No examples suppressed or warning downgrades accepted. [Draft and reproducers](followup-upstream-issues.md). |
| Generated strict FrictionBrake HTML | **Unfixed:** default HTML size limit exceeded | Same generated SVG fixture also fails on 3.4; old compiler generation not independently rerun | Large inline SVG produces 744.67 KiB page. Correct icon retained; external asset emission belongs in generator. [Unfiled draft](followup-upstream-issues.md). |
| Generated strict HTML: CoffeeMug, Turkey, ThermalHouse, DynamicSteadyState | **Pass** | Relevant original example blocks pass; full old sites unvalidated | Docs environments now declare packages used by their examples. |
| Analysis notebook templates | **Fixed runnable defaults:** five transient solves/HTML exports plus QuarterTruck calibration/convergence artifact pass | Templates also required selection on 3.4 | Select real analyses, update stale Orchestrator fallback. HL20 has zero declared analyses; its selection cells remain inapplicable. Frontend interaction unvalidated. [Coverage](followup-workflows.md). |
| DynamicSteadyState GIF and headless scripts | **Pass:** full 240-frame GIF 204.705 s; Cairo SVG 50.202 s; thermal/mechanical scripts pass | Old two-frame GIF smoke passes; full old export unvalidated | Earlier process timeouts were incomplete validation. Full rc2 artifacts now measured. |
| Optional Render extension and GUI dashboards/windows | Render extension import succeeds; GUI unvalidated headlessly | Direct GLMakie import fails without DISPLAY on both; old distribution lacks MultibodyComponents | Earlier dependency diagnostic not reproduced, so no invented defect report. Interactive scripts and notebook frontends require a display/frontend. [Limits](followup-workflows.md). |

Motor's standalone Julia trainer remains **unvalidated to completion** at every
preset in the evidence collected so far. Default optimization hits severe LLVM
compilation latency; an `-O1` full-preset retry reached finite optimization states
but was externally interrupted at 1542 updates / 5902.04 s without a final
return code or calibration CSV. Its last independently reconstructed gap was
0.21330 °C, above the unchanged 0.2 °C criterion. Intermediate checkpoints are
not completed calibrations. The validated A2 path shares the numerical core but
does not validate the standalone script's export path or full preset. See the
[Motor investigation](MotorTemperatureSciML/docs/followup-validation.md).

Shipped datasets and calibration weights are preserved. New upstream issue text
is drafted only; nothing has been filed. The independent Claude review and its
resolution are recorded in [the review report](followup-review.md). GUI frontends, complete
source-data provenance, full old-runtime retraining and every explicitly noted
unexecuted preset remain validation gaps.
