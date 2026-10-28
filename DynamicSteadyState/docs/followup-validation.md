# Follow-up workflow validation

Validated on 2026-10-26 with Dyad 3.5.0-rc2 (Julia 1.13.2), two Julia threads, one precompile task, `--startup-file=no -O0`, and `GKSwstype=100`. Numerical/plot checks used existing distribution packages. Documentation generation and HTML builds used isolated task-local project copies; generated examples were fatal (`:example_block` removed from the generated template’s `warnonly` list). Cross-reference/missing-docstring warnings were retained. No solver success criteria, HTML size limits, physical horizons, or snapshots were relaxed. No hosted CI result is claimed.

See [the workflow audit](../../followup-workflows.md) for complete commands, coverage, timings, baseline limitations and log locations, and [upstream issue drafts](../../followup-upstream-issues.md). These checks supplement `upgrade-3.5-validation.md`; they do not replace its analysis comparisons.

## Handwritten documentation example

Executed the `docs/index.md` example block(s): `DiurnalOperation`, solver `Success`, full 86400 s horizon, finite state samples. Initial measured example execution: 13.768 s (includes JIT and plotting; shared-session examples reuse imports).

## Generated documentation

RC2 documentation generation: pass (14.449 s). Full generated HTML build: **pass**, 13.704 s. Documenter 1.19.0 was used.

The existing docs environment omitted its `Documenter` dependency even though generated `make.jl` imports it. Added `Documenter` with compat `1`. The same missing dependency is present in the pre-upgrade docs environments; the 3.4 CoffeeMug environment reproduced the import error in 1.468 s.

## Notebook

Executed notebook code with `DiurnalOperation` selected, using the package’s actual Orchestrator load/discovery/run/symbol/artifact APIs. Result: `Success`, full 86400 s horizon, finite states, 191 listed symbols, and a predefined Plotly artifact. Numerical/artifact run: 7.834 s; HTML serialization run: 7.432 s. The script substitutes the task-local package path for notebook `@__DIR__`; the original placeholder was a selection template, not a solver failure. The checked-in notebook now supplies this working default and allows choosing another listed analysis. Browser interaction is unvalidated.

The notebook now includes its own validation cell immediately after
`run_analysis`, before symbol discovery or artifact production. It rebuilds the
actual analysis result with `DyadInterface.rebuild_sol`, requires
`successful_retcode`, nonempty samples, the exact problem stop time, and finite
time/state samples, and raises explicit errors on failure. These gates are
shipped in the notebook; the initial measurements above used appended harness
checks. The [review rerun](../../followup-workflows.md#review-follow-up-notebook-gates)
executes the checked-in cells against this checkout without appended solver
validation. Browser/frontend interaction remains unvalidated.

## Animated export

Full 240-frame, 20 fps GIF script: 204.705 s (status: 0). It retains the complete 86400 s simulation. The first two attempts hit 180/240 s process limits and are not counted as successful exports. A task-local `XDG_CACHE_HOME` avoids read-only host font caches. Baseline export smoke (two frames over the same full-day physical simulation): 60.473 s (status: 0). The final GIF was independently parsed: 240 image records, complete trailer, 2711329 bytes. The old smoke artifact has two image records and a complete trailer (148477 bytes). A complete old 240-frame export is not claimed.

## Limits

This audit does not validate GUI windows, browser interaction, VS Code notebook execution, dashboard controls, interactive sliders, or PID designer operation. Previously recorded analyses/training are not rerun or claimed here unless explicitly listed. Generated-doc failures above remain failures and have draft follow-ups; no upstream issue was filed.
