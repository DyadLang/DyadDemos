# Follow-up workflow validation

Validated on 2026-10-26 with Dyad 3.5.0-rc2 (Julia 1.13.2), two Julia threads, one precompile task, `--startup-file=no -O0`, and `GKSwstype=100`. Numerical/plot checks used existing distribution packages. Documentation generation and HTML builds used isolated task-local project copies; generated examples were fatal (`:example_block` removed from the generated template’s `warnonly` list). Cross-reference/missing-docstring warnings were retained. No solver success criteria, HTML size limits, physical horizons, or snapshots were relaxed. No hosted CI result is claimed.

See [the workflow audit](../../followup-workflows.md) for complete commands, coverage, timings, baseline limitations and log locations, and [upstream issue drafts](../../followup-upstream-issues.md). These checks supplement `upgrade-3.5-validation.md`; they do not replace its analysis comparisons.

## Handwritten documentation example

Executed the `docs/index.md` example block(s): `VehicleCycleTest with Rodas5P`, solver `Success`, full 2000 s horizon, finite state samples. Initial measured example execution: 8.557 s (includes JIT and plotting; shared-session examples reuse imports).

## Generated documentation

RC2 documentation generation: pass (10.991 s). Full generated HTML build: **fail**, 102.219 s. Documenter 1.19.0 was used.

All generated example blocks completed, but the embedded SVG makes `components/FrictionBrake.md` 744.67 KiB of rendered HTML, exceeding Documenter’s unchanged 200 KiB limit. A source-only SVG fixture also exceeds that limit under 3.4 (722.04 KiB). This is an existing documentation/asset integration limit, not a failed numerical analysis.

The existing docs environment omitted its `Documenter` dependency even though generated `make.jl` imports it. Added `Documenter` with compat `1`. The same missing dependency is present in the pre-upgrade docs environments; the 3.4 CoffeeMug environment reproduced the import error in 1.468 s.

## Headless scripts and accuracy

Executed all three `simulate_*.jl` scripts. Brake thermal: 5.476 s; coast-down: 4.775 s; corrected vehicle cycle: 10.642 s. All return `Success`, reach 1800/100/2000 s respectively, have finite states, and execute every plot expression.

The original 2000 s example uses the default `ODEAlg.AutoImplicit()` and exhausts its step budget on both versions: 3.4 `MaxIters` at 1988.295559006552 s (11.458388 s solve), 3.5 `MaxIters` at 1988.3492485237687 s (10.303583 s solve). Rodas5P is appropriate for the fast PID/thermal dynamics and completes the unchanged 2000 s horizon. The script also referenced `heat_disk.Q` and `heat_pad.Q`, which do not exist on either version; the valid heat-port field is `Q_flow`. Both defects predate the upgrade.

Compared the corrected Rodas5P solve (unchanged `abstol=reltol=1e-6`) with Rodas5P at `abstol=1e-10`, `reltol=1e-9` on 2001 times from 0 through 2000 s. Both returned Success. The paired solves and comparison took 4.454549 s (9.685455 s process time).

| Signal | Maximum absolute difference | RMS difference | Final value | Reference final |
|---|---:|---:|---:|---:|
| Vehicle speed (m/s) | 1.940567710079222e-6 | 3.241691118318694e-7 | 14.856923322056137 | 14.856923319672438 |
| Disk temperature (K) | 9.81024085149329e-5 | 4.174393607995609e-5 | 387.87752035392 | 387.8774726975928 |
| Pad temperature (K) | 2.707962630665861e-5 | 7.417755549379355e-6 | 421.7815009105919 | 421.78150822580693 |

These are sampled accuracy diagnostics, not residual bounds between sample times. No model physics or tolerances were changed for the shipped example.

Existing `test/runtests.jl` also passed **21/21 assertions** in 58.562517 s process time (56.4 s testset time), with unchanged generated regression checks.

## Limits

This audit does not validate GUI windows, browser interaction, VS Code notebook execution, dashboard controls, interactive sliders, or PID designer operation. Previously recorded analyses/training are not rerun or claimed here unless explicitly listed. Generated-doc failures above remain failures and have draft follow-ups; no upstream issue was filed.
