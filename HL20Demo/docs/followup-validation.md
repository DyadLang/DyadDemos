# Follow-up workflow validation

Validated on 2026-10-26 with Dyad 3.5.0-rc2 (Julia 1.13.2), two Julia threads, one precompile task, `--startup-file=no -O0`, and `GKSwstype=100`. Numerical/plot checks used existing distribution packages. Documentation generation and HTML builds used isolated task-local project copies; generated examples were fatal (`:example_block` removed from the generated template’s `warnonly` list). Cross-reference/missing-docstring warnings were retained. No solver success criteria, HTML size limits, physical horizons, or snapshots were relaxed. No hosted CI result is claimed.

See [the workflow audit](../../followup-workflows.md) for complete commands, coverage, timings, baseline limitations and log locations, and [upstream issue drafts](../../followup-upstream-issues.md). These checks supplement `upgrade-3.5-validation.md`; they do not replace its analysis comparisons.

## Generated documentation

RC2 documentation generation: pass (0.866 s). Full generated HTML build: **fail**, 27.895 s. Documenter 1.19.0 was used.

Generated `shared.HL20Aero` behavior block fails with a cyclic binding for `DLG`. The original 3.4 core instead fails earlier because `ChallengeComponent` is undefined, so this project has no successful original construction/full-flight baseline. The common cycle mechanism is independently reproduced with FIR on both versions.

## Notebook and flight coverage

Orchestrator package loading and analysis discovery completed in 3.272 s; the inventory is empty as expected. The analysis-selection/solution/artifact cells cannot run until the agent prompts create analyses. Added an explicit notebook note and corrected the handwritten page’s claims of an already-completed flight simulator. No full flight, NASA validation maneuver, or training result was invented.

## Limits

This audit does not validate GUI windows, browser interaction, VS Code notebook execution, dashboard controls, interactive sliders, or PID designer operation. Previously recorded analyses/training are not rerun or claimed here unless explicitly listed. Generated-doc failures above remain failures and have draft follow-ups; no upstream issue was filed.
