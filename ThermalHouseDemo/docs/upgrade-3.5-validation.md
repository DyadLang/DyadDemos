# Dyad 3.5 upgrade validation

Current Julia distribution: **dyad-3.5.0**; Dyad CLI target: **3.5.1**. Commands below use the 3.5.0 Julia channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Target: Dyad 3.5.0, tested with distribution `dyad-3.5.0-rc2` (Julia 1.13.2).
Validated library versions: BlockComponents 5.0.0, ThermalComponents 3.0.0,
DyadInterface 7.5.1.

## Research and migration

Read before editing:

- [ThermalComponents changelog](https://github.com/JuliaComputing/ThermalComponents/blob/v3.0.0/CHANGELOG.md), including the 2.0.6 → 3.0.0 changes.
- [BlockComponents changelog](https://github.com/JuliaComputing/BlockComponents/blob/v5.0.0/CHANGELOG.md), including the 4.6.0 → 5.0.0 changes.
- [DyadInterface 7.5.1 changelog](https://github.com/JuliaComputing/DyadInterface.jl/blob/v7.5.1/CHANGELOG.md).
- [DyadData 2.3 release notes](https://github.com/JuliaComputing/DyadData.jl/releases/tag/v2.3.0).

The component libraries' major updates change generated constructor overrides to
`__overrides` dictionaries with dotted paths. Their Dyad component definitions
remain unchanged between the preceding minor release and the new major release.
Regeneration is required to propagate nested parameter, initial-value and guess
overrides through the new constructors. Analyses now use generated `__System`
and immutable `__Spec` types, with setup adaptors; exported analysis functions
remain callable as before. BlockComponents 4.6.1 also adds state priorities.
The existing component names, port names, and Dyad analysis declarations compile
without source changes. DyadData's CSV extension changes do not require model
changes here. Model physics and solver settings are
preserved unless noted below. Project, documentation/script dependency bounds,
and editor Julia channel pins were updated.

## Analysis inventory

- TestHouseWinterDesign (7200 s)
- TestControlledHouseWinterDesign (7200 s)

No training analyses are defined. Existing generated component test bodies are
empty; `test/analyses.jl` adds end-to-end checks for every analysis above.

## Execution results

Validated on 2026-10-26 with two Julia threads and one precompile task, using
`--startup-file=no -O0`. Baseline: Dyad 3.4.0 / Julia 1.12.7,
BlockComponents 4.6.0, ThermalComponents 2.0.6, DyadInterface 7.3.0,
DyadData 2.0.1, against an unmodified project copy from commit `6e485bc`.

All listed analyses returned `Success` on both versions. Every transient reached
its declared final time. The 3.5 analyses were run once for the comparison and
again by the added tests; no shortened horizons or solver substitutions were used.

| Analysis / observable | 3.4 final | 3.5 final | Final change (3.5 − 3.4) | Maximum sampled absolute difference |
|---|---:|---:|---:|---:|
| `TestHouseWinterDesign` / indoor (K) | 301.165778263 | 301.165778263 | +7.38964e-11 | 2.76879e-09 |
| `TestControlledHouseWinterDesign` / indoor (K) | 294.259309799 | 294.259309799 | +7.50049e-10 | 1.04858e-08 |
| `TestControlledHouseWinterDesign` / heater (W) | 3478.31126279 | 3478.31127748 | +1.46932e-05 | 0.000119324 |

Transient observables were compared every 60 s, including both endpoints.
Differences are absolute in the units shown. No model parameters, solver
settings, or initialization were changed; these are the observed numerical
differences after upgrading the compiler and runtime.

Compilation passed for all definitions using the 3.5.0-rc2 compiler-only source
build at dyad-lang commit `a24a2240667872d432a3b86c4db1240d77150e35`.
Generated Julia was regenerated with compiler-emitted whitespace preserved, including
the constructor API version checks,
dotted override dictionaries, parameter seeding, and analysis setup adaptors.
Workspace instantiation passed; its ignored manifest was regenerated.

Both versions emitted the existing small-initial-timestep warning for the
controlled analysis and selected `dt = 1e-6`; both completed successfully.

`test/runtests.jl` passed: 11 analysis assertions. The existing generated
component testset also loaded successfully and contains zero assertions. Tests
check successful solves and full horizons, finite output temperatures, and the
physical bounds or sizing fixtures appropriate to this project.

Re-run the tests from the repository root after instantiation:

```sh
julia +dyad-3.5.0 --startup-file=no -O0 --project=ThermalHouseDemo ThermalHouseDemo/test/runtests.jl
```

Not run: documentation rendering, graphical dashboards/animation export, or
interactive plotting scripts. Their numerical analyses are covered above.
No training workloads are defined or required for this project.
