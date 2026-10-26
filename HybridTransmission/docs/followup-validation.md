# Follow-up workflow validation

Validated on 2026-10-26 with Dyad 3.5.0-rc2 (Julia 1.13.2), two Julia threads, one precompile task, `--startup-file=no -O0`, and `GKSwstype=100`. Numerical/plot checks used existing distribution packages. Documentation generation and HTML builds used isolated task-local project copies; generated examples were fatal (`:example_block` removed from the generated template’s `warnonly` list). Cross-reference/missing-docstring warnings were retained. No solver success criteria, HTML size limits, physical horizons, or snapshots were relaxed. No hosted CI result is claimed.

See [the workflow audit](../../followup-workflows.md) for complete commands, coverage, timings, baseline limitations and log locations, and [upstream issue drafts](../../followup-upstream-issues.md). These checks supplement `upgrade-3.5-validation.md`; they do not replace its analysis comparisons.

## Generated documentation

RC2 documentation generation: pass (3.222 s). Full generated HTML build: **fail**, 74.039 s. Documenter 1.19.0 was used.

Generated `ECMSController` and `HybridBattery` behavior blocks fail with cyclic parameter bindings (`s_base`, `V_nom`). The identical blocks pass against the 3.4 baseline.

## Notebook

Executed notebook code with `TestPowerSplitHybrid` selected, using the package’s actual Orchestrator load/discovery/run/symbol/artifact APIs. Result: `Success`, full 765 s horizon, finite states, 59 listed symbols, and a predefined Plotly artifact. Numerical/artifact run: 12.749 s; HTML serialization run: 12.248 s. The script substitutes the task-local package path for notebook `@__DIR__`; the original placeholder was a selection template, not a solver failure. The checked-in notebook now supplies this working default and allows choosing another listed analysis. Browser interaction is unvalidated.

## Limits

This audit does not validate GUI windows, browser interaction, VS Code notebook execution, dashboard controls, interactive sliders, or PID designer operation. Previously recorded analyses/training are not rerun or claimed here unless explicitly listed. Generated-doc failures above remain failures and have draft follow-ups; no upstream issue was filed.
