# Follow-up workflow audit

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
| MakieWebinar | Success, full horizon | blocked: artifact host | blocked during generation (DyadDAQP artifact download) | 9.344 s |

Full HTML passes: CoffeeMugDemo, TurkeyDemo, ThermalHouseDemo, DynamicSteadyState. Failures: FrictionBrake exceeds the unchanged HTML size limit; HybridTransmission, PassiveSuspension, FIRFilterComponents, SatelliteGNC and HL20Demo hit generated symbolic-parameter cycles. MakieWebinar generation requires a blocked DyadDAQP artifact. Earlier exit-zero builds with broken examples downgraded to warnings are explicitly not counted as passes.

## Notebook and headless script coverage

| Notebook | Selected analysis | End (s) | Symbols | Numerical/artifact process time | HTML serialization process time |
|---|---|---:|---:|---:|---:|
| DynamicSteadyState | `DiurnalOperation` | 86400 | 191 | 7.834 s | 7.432 s |
| FIRFilterComponents | `TestFIRFilterAnalysis` | 2π | 34 | 23.827 s | 22.368 s |
| HybridTransmission | `TestPowerSplitHybrid` | 765 | 59 | 12.749 s | 12.248 s |
| PassiveSuspension | `PassiveSuspensionTransient` | 10 | 169 | 7.733 s | 7.436 s |
| SatelliteGNC | `TestFullGNCSim` | 40 | 60 | 7.883 s | 7.636 s |

All selected notebook solves return Success, reach the declared stop time, and have finite states. Orchestrator returns predefined Plotly plot artifacts; an additional run serializes each artifact as HTML. Hybrid’s conditional-bootstrap notebook was also run without a bootstrap shortcut (11.592 s). DynamicSteadyState’s absent-package fallback was corrected from Orchestrator 0.6.1 to the distribution’s 0.15.0. These notebooks were selection templates; the placeholder itself was not a solver bug. HL20 loading/discovery returns zero analyses (3.272 s); its later selection/plot cells remain inapplicable until the documented prompts build analyses.

Complete scripts executed: CoffeeMug (both variants, 6000 s), Turkey (14400 s), FrictionBrake thermal (1800 s), coast-down (100 s), and vehicle cycle (2000 s). All numerical solves passed full-horizon/finite-state checks; every script plot expression executed. FrictionBrake’s old default method exhausted its step budget on both runtimes and its heat-flow plot used nonexistent `.Q` fields. The corrected script uses Rodas5P and `.Q_flow`, and checks its return code and final time. Its [accuracy evidence](FrictionBrakeDemo/docs/followup-validation.md) includes a 2001-point comparison with a tighter reference: maximum speed/disk/pad differences 1.94057e-6 m/s, 9.81024e-5 K, and 2.70796e-5 K.

DynamicSteadyState’s complete 240-frame GIF export: 204.705 s, result `0`. The full-day numerical solve is retained. Two earlier attempts timed out at 180/240 s. Old-stack two-frame export smoke: 60.473 s, result `0`; no complete 240-frame old export is claimed. Both use a task-local font cache. CairoMakie handwritten example SVG export: 50.202 s, result `0`.

The existing FrictionBrake regression testset also passed **21/21** checks (58.562517 s process time, 56.4 s testset time).

## Baseline and upstream distinctions

The original thermal/mechanical/flight projects are preserved under workspace `.task/thermal-baseline`, `.task/mechanical-baseline`, and `.task/flight-baseline`; SciML baseline data for the isolated annotation repro is under `.task/sciml/baseline`. These use the original 3.4 sources documented in each existing upgrade report. Baseline tests do not run rc2-generated model sources. For documentation behavior comparisons, the exact emitted Julia example block is executed against each original 3.4 model, then against rc2.

FIR’s `Hello` behavior block passes on 3.4 (1.038771 s in-block) and fails on rc2 (0.427529 s) with a `T_inf` parameter cycle. Hybrid ECMSController/HybridBattery, suspension ISO8608RoadC, and satellite AttitudeController/LuenbergerObserver/ReactionJet blocks also pass against 3.4 and fail with the same cycle on rc2. Original HL20 construction instead fails earlier on undefined `ChallengeComponent`; no successful original full-flight baseline exists. The SVG-only documentation fixture fails the default HTML limit under 3.4 as well (722.04 KiB, 40.616872 s process time). This tests the same generated SVG content, not an independently rebuilt 3.4 documentation generator.

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

For a clean manual documentation rerun, copy one project to a task-local directory, invoke `node "$repo/.ci/compiler/compiler.mjs" document <ProjectName>` with that copy as cwd, activate its docs environment, `Pkg.resolve(); Pkg.instantiate()`, remove only `:example_block` from the generated `make.jl` warning list, and include `make.jl`. The compiler-only CLI is the exact rc2/a24a224 build. Original handmade `docs/index.md` examples are extracted and executed separately by `docs.jl`; each result is rebuilt and checked with `successful_retcode`, the problem’s actual stop time, and finite states. Notebook scripts are concatenated code cells with `@__DIR__` replaced by the copied scripts path, a concrete selected analysis, and appended result/HTML checks.

Per-project reports link the relevant results and limitations. No generated HTML, generated Julia, snapshots or upstream source modifications are committed by this worker.
