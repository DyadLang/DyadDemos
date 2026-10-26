# Follow-up workflow audit

Evidence paths and helper commands under `.task/` refer to the retained
validation workspace; those logs and investigation helpers are not shipped
with this repository. The demo entry points under `scripts/` are committed.


Validated on 2026-10-26 with Dyad 3.5.0-rc2 (Julia 1.13.2), two Julia threads, one precompile task, `--startup-file=no -O0`, and `GKSwstype=100`. Numerical/plot checks used existing distribution packages. Documentation generation and HTML builds used isolated task-local project copies; generated examples were fatal (`:example_block` removed from the generated template’s `warnonly` list). Cross-reference/missing-docstring warnings were retained. No solver success criteria, HTML size limits, physical horizons, or snapshots were relaxed. No hosted CI result is claimed.

The commands, coverage, timings and baseline limits below supplement each project’s `docs/upgrade-3.5-validation.md`. See the [upstream issue drafts](followup-upstream-issues.md) for unresolved compiler/documentation behavior.

## Documentation coverage

The handwritten pages and generated Documenter site are separate workflows. `dyad document` generates `docs/src`, `pages.jl`, and `make.jl`; it does not render the handwritten `docs/index.md`. Both were exercised. The initial generated templates included `:example_block` in `warnonly`; the audit removed that entry in task copies so broken examples could not produce a false green result.

| Project | Handwritten example | RC2 document generation | Generated HTML build (strict examples) | Build process time |
|---|---|---|---|---:|
| CoffeeMugDemo | Success, full horizon | pass | pass | 14.604 s |
| TurkeyDemo | Success, full horizon | pass | pass | 14.398 s |
| ThermalHouseDemo | Success, full horizon | pass | pass | 18.320 s |
| DynamicSteadyState | Success, full horizon | pass | pass | 13.704 s |
| FrictionBrakeDemo | Success, full horizon | pass | fail | 102.219 s |
| HybridTransmission | No executable block | pass | fail | 74.039 s |
| PassiveSuspension | Success, full horizon | pass | fail | 65.457 s |
| FIRFilterComponents | No executable block | pass | fail | 44.942 s |
| SatelliteGNC | Success, full horizon | pass | fail | 23.080 s |
| HL20Demo | No executable block | pass | fail | 27.895 s |
| MakieWebinar | Success, full horizon | pass (24.379 s after access grant) | fail: generated `Hello` parameter cycle | 73.976 s |

Full HTML passes: CoffeeMugDemo, TurkeyDemo, ThermalHouseDemo, DynamicSteadyState. Failures: FrictionBrake exceeds the unchanged HTML size limit; HybridTransmission, PassiveSuspension, FIRFilterComponents, SatelliteGNC, HL20Demo and MakieWebinar hit generated symbolic-parameter cycles. MakieWebinar generation succeeded after the artifact-host access grant. Earlier exit-zero builds with broken examples downgraded to warnings are explicitly not counted as passes.

## Notebook and headless script coverage

| Notebook | Selected analysis | End (s) | Symbols | Numerical/artifact process time | HTML serialization process time |
|---|---|---:|---:|---:|---:|
| DynamicSteadyState | `DiurnalOperation` | 86400 | 191 | 7.834 s | 7.432 s |
| FIRFilterComponents | `TestFIRFilterAnalysis` | 2π | 34 | 23.827 s | 22.368 s |
| HybridTransmission | `TestPowerSplitHybrid` | 765 | 59 | 12.749 s | 12.248 s |
| PassiveSuspension | `PassiveSuspensionTransient` | 10 | 169 | 7.733 s | 7.436 s |
| SatelliteGNC | `TestFullGNCSim` | 40 | 60 | 7.883 s | 7.636 s |

All selected notebook solves return Success, reach the declared stop time, and have finite states. Orchestrator returns predefined Plotly plot artifacts; an additional run serializes each artifact as HTML. Hybrid’s conditional-bootstrap notebook was also run without a bootstrap shortcut (11.592 s). DynamicSteadyState’s absent-package fallback was corrected from Orchestrator 0.6.1 to the distribution’s 0.15.0. These notebooks were selection templates; the placeholder itself was not a solver bug. HL20 loading/discovery returns zero analyses (3.272 s); its later selection/plot cells remain inapplicable until the documented prompts build analyses.

Complete scripts executed: CoffeeMug (both variants, 6000 s), Turkey (14400 s), FrictionBrake thermal (1800 s), coast-down (100 s), and vehicle cycle (2000 s). All numerical solves passed full-horizon/finite-state checks; every script plot expression executed. FrictionBrake’s old default method exhausted its step budget on both runtimes and its heat-flow plot used nonexistent `.Q` fields. The corrected script uses Rodas5P and `.Q_flow`, and now raises explicit errors for unsuccessful return codes, missing samples, incomplete horizons, or non-finite time/state samples. Its [accuracy evidence](FrictionBrakeDemo/docs/followup-validation.md) includes a 2001-point comparison with a tighter reference: maximum speed/disk/pad differences 1.94057e-6 m/s, 9.81024e-5 K, and 2.70796e-5 K.

DynamicSteadyState’s complete 240-frame GIF export: 204.705 s, result `0`. The full-day numerical solve is retained. Two earlier attempts timed out at 180/240 s. Old-stack two-frame export smoke: 60.473 s, result `0`; no complete 240-frame old export is claimed. Both use a task-local font cache. CairoMakie handwritten example SVG export: 50.202 s, result `0`.

The existing FrictionBrake regression testset also passed **21/21** checks (58.562517 s process time, 56.4 s testset time).

## Baseline and upstream distinctions

The original thermal/mechanical/flight projects are preserved under workspace `.task/thermal-baseline`, `.task/mechanical-baseline`, and `.task/flight-baseline`; SciML baseline data for the isolated annotation repro is under `.task/sciml/baseline`. These use the original 3.4 sources documented in each existing upgrade report. Baseline tests do not run rc2-generated model sources. For documentation behavior comparisons, the exact emitted Julia example block is executed against each original 3.4 model, then against rc2.

FIR’s `Hello` behavior block passes on 3.4 (1.038771 s in-block) and fails on
rc2 (0.427529 s) with a `T_inf` parameter cycle. Hybrid ECMSController/HybridBattery,
suspension ISO8608RoadC, and MakieWebinar Hello blocks also pass against 3.4 and
fail with the same cycle on rc2.

SatelliteGNC has **seven** failed generated blocks: `AttitudeController` (`Kp_x`),
`LuenbergerObserver` (`Ixx`), `ReactionJet` (`rx`), `SatelliteBody` (`Ixx`),
`SatelliteBody6DOF` (`Ixx`), `ThrusterAllocator` (`F_max`), and
`TrapezoidalProfile` (`target_angle`). All seven identical blocks pass against
the original 3.4 model. The review follow-up tested the last four (5.078403 s,
exit 0); the initial audit tested the first three. This is a symbolic block
comparison, not a complete old site build. See the
[component table and evidence](SatelliteGNC/docs/followup-validation.md#generated-documentation).

Original HL20 construction instead fails earlier on undefined
`ChallengeComponent`; no successful original full-flight baseline exists.
The initial SVG-only documentation fixture fails the default HTML limit under
3.4 as well (722.04 KiB, 40.616872 s process time). That fixture tests the same
generated SVG content, not an independently rebuilt 3.4 documentation generator.
The review follow-up additionally tests the committed source-asset fixture below.

The timeseries annotation regression was regenerated and reproduced only in `.task/workflows/annotation/DrivelineSciML`; neither concurrent SciML owner’s project was edited. Old spec construction: pass (2.621428 s in-process); exact rc2 system construction: failure before solving (0.242543 s). Substituting the concrete runtime timeseries type in that task copy permits construction (3.097058 s). This is code-generation evidence, not a successful calibration or a change to optimization acceptance criteria. See [precise issue drafts](followup-upstream-issues.md), including the already-open dyad-lang #1958.

## GUI and other limits

Direct GLMakie imports fail on both runtimes because DISPLAY is absent (GLMakie 0.13.16); this is expected for the headless worker. The rc2 MultibodyComponents.Render extension loaded successfully in an explicit Makie/scripts environment, so the earlier precompile diagnostic was not reproduced there. The old distribution has no MultibodyComponents package. Do not treat an extension load as validation of a GUI scene.

Unvalidated GUI workflows: Turkey `scripts/dashboard.jl`; MakieWebinar `01_intro.jl`, `02_plot_solutions.jl`, `03_paramsweep.jl`, `04_input_realtime.jl`, `visualize_flat_mesh.jl`, and the interactive PID designer in `05_autotuning_analysis.jl`; VS Code/Jupyter frontend integration and browser interaction for every notebook. Numeric analyses for those visualizations have the earlier project reports, but that is not GUI validation. No flight simulator was invented for HL20. This audit does not rerun optimizer/training workflows owned by the other workers, and does not audit hosted CI.

## Reproduction and evidence

Run from the workspace root; `repo` below is the absolute DyadDemos directory. All package installation is project-scoped. The recorded commands use this environment:

```sh
export JULIAUP_DEPOT_PATH="$PWD/.toolchain/juliaup"
export JULIAUP_SERVER=https://juliahub.com/juliabin
export JULIA_DEPOT_PATH="$PWD/.toolchain/depot"
export JULIA_NUM_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=1
export JULIA_PKG_PRECOMPILE_AUTO=0 JULIA_PKG_USE_CLI_GIT=true
export OPENBLAS_NUM_THREADS=1 GKSwstype=100
export XDG_CACHE_HOME="$PWD/.task/workflows/cache"
export JULIA_EXECUTABLE="$PWD/.toolchain/juliaup/bin/julia +dyad-3.5.0-rc2"
julia_worker="$PWD/.toolchain/juliaup/bin/julia"
repo="$PWD/DyadDemos"
"$julia_worker" +dyad-3.5.0-rc2 --startup-file=no -O0 --project="$repo/FrictionBrakeDemo/docs" "$repo/FrictionBrakeDemo/scripts/simulate_vehicle_cycle_test.jl"
"$julia_worker" +dyad-3.5.0-rc2 --startup-file=no -O0 --project="$repo/MakieWebinar/docs" .task/workflows/doc-MakieWebinar-export.jl .task/workflows/makie-doc.svg
"$julia_worker" +dyad-3.5.0-rc2 --startup-file=no -O0 --project="$repo/HybridTransmission" .task/workflows/notebook-HybridTransmission-exact.jl
```

All task-local harnesses and per-attempt logs are retained in workspace `.task/workflows/`. `jobs.py` executes subprocesses in the foreground, enforces only process time limits, and appends exact wall times/exit codes to `results.jsonl`. Catch-and-print diagnostic probes intentionally exit zero after recording expected old/new errors; their printed failure is the result, not their process exit code. The `jobs-*.json` files retain exact argv/cwd/time-limit records.

```sh
python3 .task/workflows/jobs.py .task/workflows/jobs-docgen.json
python3 .task/workflows/jobs.py .task/workflows/jobs-html.json
python3 .task/workflows/jobs.py .task/workflows/jobs-notebooks.json
python3 .task/workflows/jobs.py .task/workflows/jobs-artifacts.json
python3 .task/workflows/jobs.py .task/workflows/jobs-issues.json
python3 .task/workflows/jobs.py .task/workflows/jobs-baseline-remainder.json
```

For a clean manual documentation rerun, copy one project to a task-local directory, invoke `node "$repo/.ci/compiler/compiler.mjs" document <ProjectName>` with that copy as cwd, activate its docs environment, `Pkg.resolve(); Pkg.instantiate()`, remove only `:example_block` from the generated `make.jl` warning list, and include `make.jl`. The compiler-only CLI is the exact rc2/a24a224 build. Original handmade `docs/index.md` examples are extracted and executed separately by `docs.jl`; each result is rebuilt and checked with `successful_retcode`, the problem’s actual stop time, and finite states. The initial notebook scripts concatenate code cells with `@__DIR__` replaced by the copied scripts path, a concrete selected analysis, and appended result/HTML checks. The review follow-up below instead executes the checks shipped inside the five notebooks against the actual checkout.

Per-project reports link the relevant results and limitations. No generated HTML, generated Julia, snapshots or upstream source modifications are committed by this worker.

## Granted-access retry

The outstanding MakieWebinar artifact download was retried after the task's
`github.com` access grant. `document-MakieWebinar-access-retry` still exited
**1** after **13.352420 s**, with the same HTTP 403 CONNECT-tunnel rejection of
the DyadDAQP_jll 0.10.3 release URL. Generation/HTML coverage was still
blocked at that point; the later release-assets retry below supersedes it. The [project report](MakieWebinar/docs/followup-validation.md#artifact-access-retry)
records the exact command, logs and limits. No source/model/dependency workaround
was applied and no numerical result changed.

## Release-assets access retry: generation completed, example regression exposed

After task access to `release-assets.githubusercontent.com` was granted, the
unchanged MakieWebinar generation command completed with exit **0** in
**24.378873 s**. This supersedes the artifact blockage above. The subsequent
strict-example HTML build exited **1** in **73.975772 s**, before HTML rendering,
because generated `components/Hello.md:51` fails in `full_equations` with a
`T_inf` parameter-binding cycle. Cross-reference/missing-docstring warnings and
the optional missing-DISPLAY precompile diagnostic are retained; the terminal
Documenter error is `[:example_block]`.

All twelve emitted component behavior blocks were then executed against the
original 3.4 model and rc2 model in separate processes. Old: **12 pass**,
**6.627891 s** process time. New: **11 pass, Hello fails**, **6.929902 s** process
time. Hello's in-block times are **0.289241 s** old and **0.212930 s** new. These
are symbolic construction/equation checks; they add no numerical solve,
residual, or trajectory-accuracy claim. The probe catches and prints individual
errors to cover every component, so its zero process exit is not an all-pass
signal. The independent HTML build exits nonzero as required.

With the environment in Reproduction above, exact retained commands are:

```sh
python3 .task/workflows/jobs.py .task/workflows/jobs-release-assets-retry.json
python3 .task/workflows/jobs.py .task/workflows/jobs-html-release-assets-retry.json
python3 .task/workflows/jobs.py .task/workflows/jobs-makie-behaviors.json
```

The first invokes the same compiler `document MakieWebinar` command in the task
copy. The second uses `build-docs.jl` after removing only `:example_block` from
that copy's generated `warnonly` list. The third runs
`behavior-MakieWebinar-all.jl <model-root> <generated-docs-root>` under each
runtime/project, loads the unchanged generated models by inclusion, and executes
the emitted component blocks in separate modules. All exact argv, cwd, process
limits, per-block outcomes, and wall times remain under `.task/workflows/` in
the named job files, matching `.log` files, and `results.jsonl`. No generated
source, artifact payload, manifest, or HTML is committed. See the updated
[MakieWebinar report](MakieWebinar/docs/followup-validation.md#release-assets-access-retry).

## Review follow-up: notebook gates

The five runnable analysis notebooks now validate the actual Orchestrator result
immediately after `run_analysis` and before producing artifacts. The cell calls
`DyadInterface.rebuild_sol(solution)`, checks `successful_retcode`, requires
nonempty samples and the exact `sol.prob.tspan[2]` endpoint, and rejects
non-finite time/state samples with explicit errors. It displays the retcode,
final time and finiteness result. The criteria match the earlier audit and now
ship with each notebook.

Every checked-in code cell was rerun on rc2 against the actual project in this
checkout, including the bootstrap, validation and Plotly artifact cells. Only
`@__DIR__` was substituted with the real notebook directory for script execution;
no solver checks were appended and no bootstrap cell was skipped.

| Notebook | Declared end (s) | Validation and artifact cells | Process time |
|---|---:|---|---:|
| DynamicSteadyState | 86400 | pass | 11.841154 s |
| FIRFilterComponents | 2π | pass | 22.113513 s |
| HybridTransmission | 765 | pass | 16.211610 s |
| PassiveSuspension | 10 | pass | 7.530924 s |
| SatelliteGNC | 40 | pass | 7.780991 s |

The extracted scripts, commands, logs and exit-zero records are retained under
`.task/workflows/review-notebook-*.{jl,log}`, `jobs-review-notebooks.json` and
`results.jsonl`. Browser/frontend interaction was not exercised again; the
previous HTML serialization measurements remain the artifact-export evidence.

The FrictionBrake vehicle-cycle script also uses explicit errors for return
code, empty samples, exact final time and time/state finiteness before plotting.
The actual script rerun returned `Success`, end `2000.0`, finite states, and
executed every plot expression (10.637459 s, exit 0).

The committed [inline SVG reproducer](FrictionBrakeDemo/docs/reproduce_inline_svg.jl)
uses `FrictionBrakeDemo/assets/brake_caliper.svg` (731703 bytes) directly and
builds one temporary Documenter page with default HTML limits. This removes the
upstream draft’s dependency on a task-local generated fixture. Both runtime
results are recorded below; a size-limit failure is the expected reproduction,
not a successful documentation build.

| Runtime | Result | Rendered page | Process time |
|---|---|---:|---:|
| 3.5.0-rc2 | exit 1, `HTMLSizeThresholdError` | 720.27 KiB | 5.577645 s |
| 3.4.0 | exit 1, `HTMLSizeThresholdError` | 720.28 KiB | 4.274072 s |

Both used Documenter 1.19.0 and exceeded its unchanged 200 KiB threshold.
This minimal source-asset page differs from the earlier generated-content
fixture; both reproduce the same default size-limit failure.

With the environment in Reproduction above, run from the workspace root:

```sh
python3 .task/workflows/jobs.py .task/workflows/jobs-review-notebooks.json
python3 .task/workflows/jobs.py .task/workflows/jobs-review-satellite-baseline.json
python3 .task/workflows/jobs.py .task/workflows/jobs-review-scripts.json
```

The last job file records the guarded script and the source-asset SVG fixture
under each runtime. The latter uses the existing Documenter-only task environment
on 3.4, so it does not attempt to load rc2 model packages on that runtime. The
[upstream draft](followup-upstream-issues.md#draft-inline-svg-makes-an-otherwise-executable-generated-site-fail-html-limits)
also gives a reproduction using only committed files.

HL20’s notebook note has a cell id for nbformat 4.5, and its card title and
description now state that the checkout provides an aerodynamic core and prompts.
MakieWebinar’s obsolete artifact retry is explicitly marked superseded. The
Hybrid and Satellite drafts name components individually, and the affected docs
dependency tables keep `Documenter` in alphabetical order. Notebook JSON, cell id
uniqueness, empty outputs, relative file links, TOML parsing and whitespace were
checked. No full generated sites were rebuilt for these prose/schema edits;
previously failing generated builds remain failures.

## Final QuarterTruck notebook execution

The final Claude review caught an additional notebook error: the selected
`QuarterTruckCalibrationAnalysis` did not offer `SimulationSolutionPlot`.
The notebook now requests `ConvergencePlot` and reuses the strict finite-fit
and raw MadNLP acceptance helper used by the command-line workflow.

Every shipped code cell then executed successfully in a fresh RC2 process
with normal Julia compiler settings (two threads), with only `@__DIR__`
relocated to the notebook directory. Process wall time was **245.66 s**,
optimizer time **106.679172039 s**, **43 iterations**, objective
**0.0058507392955954975**, raw status **`SOLVE_SUCCEEDED`**, primal residual
**0.0** and dual residual **1.4388840022991673e-9**. The final convergence
artifact call completed and the driver printed `SHIPPED_NOTEBOOK_PASS`.
This extends the executed notebook coverage from five transient notebooks
to six runnable notebooks. HL20 still has no analyses to select.

Evidence is workspace-local:
`.task/workflows/final-notebook-QuarterTruckSciML.jl` and
`final-notebook-QuarterTruckSciML-default.log`. An initial `-O0` attempt
was stopped after about eight minutes while sampled in the calibration
solver; it had no final result and is not counted as a passing run.
The complete successful run changed neither the numerical problem nor its
iteration budget, tolerances or acceptance checks.
