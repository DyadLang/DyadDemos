# Follow-up workflow validation

Validated on 2026-10-26 with Dyad 3.5.0-rc2 (Julia 1.13.2), two Julia threads, one precompile task, `--startup-file=no -O0`, and `GKSwstype=100`. Numerical/plot checks used existing distribution packages. Documentation generation and HTML builds used isolated task-local project copies; generated examples were fatal (`:example_block` removed from the generated template’s `warnonly` list). Cross-reference/missing-docstring warnings were retained. No solver success criteria, HTML size limits, physical horizons, or snapshots were relaxed. No hosted CI result is claimed.

See [the workflow audit](../../followup-workflows.md) for complete commands, coverage, timings, baseline limitations and log locations, and [upstream issue drafts](../../followup-upstream-issues.md). These checks supplement `upgrade-3.5-validation.md`; they do not replace its analysis comparisons.

## Handwritten documentation example

Executed the `docs/index.md` example block(s): `TestFullGNCSim`, solver `Success`, full 40 s horizon, finite state samples. Initial measured example execution: 3.516 s (includes JIT and plotting; shared-session examples reuse imports).

## Generated documentation

RC2 documentation generation: pass (3.722 s). Full generated HTML build: **fail**, 23.080 s. Documenter 1.19.0 was used.

The strict build reports **seven** failed generated behavior blocks:

| Component | First cycle parameter | Identical block on original 3.4 model |
|---|---|---|
| `AttitudeController` | `Kp_x` | pass (initial audit) |
| `LuenbergerObserver` | `Ixx` | pass (initial audit) |
| `ReactionJet` | `rx` | pass (initial audit) |
| `SatelliteBody` | `Ixx` | pass (review follow-up) |
| `SatelliteBody6DOF` | `Ixx` | pass (review follow-up) |
| `ThrusterAllocator` | `F_max` | pass (review follow-up) |
| `TrapezoidalProfile` | `target_angle` | pass (review follow-up) |

The initial report listed only the first three. The remaining four exact rc2-emitted
Julia blocks were extracted from the generated pages and executed without catches
against the preserved original `.task/flight-baseline/SatelliteGNC` model on 3.4.
All four pass (5.078403 s process time, exit 0); no model was regenerated for the
baseline. The harness is `.task/workflows/review-satellite-remaining-baseline.jl`,
with command, output and time in `jobs-review-satellite-baseline.json`,
`review-satellite-remaining-baseline.log` and `results.jsonl`. This checks symbolic
construction and equations, not a trajectory or a complete old documentation build.

The existing docs environment omitted its `Documenter` dependency even though generated `make.jl` imports it. Added `Documenter` with compat `1`. The same missing dependency is present in the pre-upgrade docs environments; the 3.4 CoffeeMug environment reproduced the import error in 1.468 s.

## Notebook

Executed notebook code with `TestFullGNCSim` selected, using the package’s actual Orchestrator load/discovery/run/symbol/artifact APIs. Result: `Success`, full 40 s horizon, finite states, 60 listed symbols, and a predefined Plotly artifact. Numerical/artifact run: 7.883 s; HTML serialization run: 7.636 s. The script substitutes the task-local package path for notebook `@__DIR__`; the original placeholder was a selection template, not a solver failure. The checked-in notebook now supplies this working default and allows choosing another listed analysis. Browser interaction is unvalidated.

The notebook now includes its own validation cell immediately after
`run_analysis`, before symbol discovery or artifact production. It rebuilds the
actual analysis result with `DyadInterface.rebuild_sol`, requires
`successful_retcode`, nonempty samples, the exact problem stop time, and finite
time/state samples, and raises explicit errors on failure. These gates are
shipped in the notebook; the initial measurements above used appended harness
checks. The [review rerun](../../followup-workflows.md#review-follow-up-notebook-gates)
executes the checked-in cells against this checkout without appended solver
validation. Browser/frontend interaction remains unvalidated.

## Limits

This audit does not validate GUI windows, browser interaction, VS Code notebook execution, dashboard controls, interactive sliders, or PID designer operation. Previously recorded analyses/training are not rerun or claimed here unless explicitly listed. Generated-doc failures above remain failures and have draft follow-ups; no upstream issue was filed.
