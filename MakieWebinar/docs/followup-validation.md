# Follow-up workflow validation

Validated on 2026-10-26 with Dyad 3.5.0-rc2 (Julia 1.13.2), two Julia threads, one precompile task, `--startup-file=no -O0`, and `GKSwstype=100`. Numerical/plot checks used existing distribution packages. Documentation generation and HTML builds used isolated task-local project copies; generated examples were fatal (`:example_block` removed from the generated template’s `warnonly` list). Cross-reference/missing-docstring warnings were retained. No solver success criteria, HTML size limits, physical horizons, or snapshots were relaxed. No hosted CI result is claimed.

See [the workflow audit](../../followup-workflows.md) for complete commands, coverage, timings, baseline limitations and log locations, and [upstream issue drafts](../../followup-upstream-issues.md). These checks supplement `upgrade-3.5-validation.md`; they do not replace its analysis comparisons.

## Handwritten documentation example

Executed the `docs/index.md` example block(s): `Hello, both CairoMakie blocks`, solver `Success`, full 10 s horizon, finite state samples. Initial measured example execution: 47.091 s (includes JIT and plotting; shared-session examples reuse imports).

## Generated documentation

RC2 documentation generation: blocked (162.263 s). Full generated HTML build: **blocked during generation (DyadDAQP artifact download)**, 9.344 s. Documenter 1.19.0 was used.

`dyad document` could not instantiate its copied workspace: the DyadDAQP_jll 0.10.3 artifact download returned HTTP 403 from the configured proxy. A complete generated-document build is not claimed. Both handwritten CairoMakie example blocks did execute.

The existing docs environment omitted its `Documenter` dependency even though generated `make.jl` imports it. Added `Documenter` with compat `1`. The same missing dependency is present in the pre-upgrade docs environments; the 3.4 CoffeeMug environment reproduced the import error in 1.468 s.

## Cairo export and optional backends

Both handwritten documentation blocks plus solver/finite-state checks and actual SVG export: 50.202 s (status: 0). The resulting SVG has 31013 bytes.

Direct GLMakie import fails for missing DISPLAY on both 3.4 and rc2, using GLMakie 0.13.16; that is a headless environment limitation. A fresh rc2 probe explicitly loaded MultibodyComponents 0.3.0 and Makie 0.24.16 from the scripts environment, obtained `Base.get_extension(MultibodyComponents, :Render) == Render`, and successfully ran `Base.retry_load_extensions()` (4.986513 s). The earlier Render/Makie dependency diagnostic was not reproduced by this probe. MultibodyComponents is absent from the 3.4 distribution. No GUI rendering claim follows from extension loading.

## Limits

This audit does not validate GUI windows, browser interaction, VS Code notebook execution, dashboard controls, interactive sliders, or PID designer operation. Previously recorded analyses/training are not rerun or claimed here unless explicitly listed. Generated-doc failures above remain failures and have draft follow-ups; no upstream issue was filed.

## Artifact access retry

After task access to `github.com` was granted, the unchanged task-local
`dyad document MakieWebinar` workflow was retried. It still failed during
workspace instantiation after **13.352420 s** (process exit **1**) with
`HTTP/1.1 403 Forbidden (CONNECT tunnel failed, response 403)` at:

```text
https://github.com/JuliaComputing/DyadDAQP_jll.jl/releases/download/DyadDAQP-v0.10.3+0/DyadDAQP.v0.10.3.x86_64-linux-gnu.tar.gz
```

The grant did not make this download reachable. Generation did not reach
example execution or HTML rendering; no new solver, residual, accuracy or
HTML-success claim follows. Existing successful handwritten Cairo results
above remain the covered workflow. No package version, workspace dependency,
model, or success check was changed to bypass the download.

With the environment recorded in the shared workflow report, the exact retry
was:

```sh
python3 .task/workflows/jobs.py .task/workflows/jobs-access-retry.json
```

The job invokes `node "$repo/.ci/compiler/compiler.mjs" document MakieWebinar`
with cwd `.task/workflows/copies/MakieWebinar`. The full output is retained in
`.task/workflows/document-MakieWebinar-access-retry.log`; exact argv, cwd and
300 s process limit are in `jobs-access-retry.json`, and measured wall time and
exit status are appended to `results.jsonl`. No additional 3.4 numerical
comparison is appropriate for this unchanged network-access failure.
