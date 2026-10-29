# Dyad 3.5 upgrade validation

Current Julia distribution: **dyad-3.5.0**; Dyad CLI target: **3.5.1**. Commands below use the 3.5.0 Julia channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Target: Dyad 3.5.0, tested with distribution `dyad-3.5.0-rc2` (Julia 1.13.2).
Validated library versions: BlockComponents 5.0.0, ThermalComponents 3.0.0,
DyadInterface 7.5.1, DyadData 2.3.0.

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

- HVACSizing (steady state)
- ColdNightSizing (steady state)
- DiurnalOperation (86400 s)

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
| `HVACSizing` / zone 1 (W) | 4274.11411411 | 4274.11411411 | +0 | 0 |
| `HVACSizing` / zone 2 (W) | 1149.80514945 | 1149.80514945 | -2.27374e-13 | 2.27374e-13 |
| `HVACSizing` / zone 3 (W) | 5165.78078078 | 5165.78078078 | +0 | 0 |
| `ColdNightSizing` / zone 1 (W) | 7557.5975976 | 7557.5975976 | +0 | 0 |
| `ColdNightSizing` / zone 2 (W) | 1924.76767819 | 1924.76767819 | -2.27374e-13 | 2.27374e-13 |
| `ColdNightSizing` / zone 3 (W) | 7040.93093093 | 7040.93093093 | +0 | 0 |
| `DiurnalOperation` / zone 1 (K) | 292.731475597 | 292.731477185 | +1.5884e-06 | 0.000787464 |
| `DiurnalOperation` / zone 2 (K) | 293.733159573 | 293.733159788 | +2.15375e-07 | 0.00362527 |
| `DiurnalOperation` / zone 3 (K) | 292.823759533 | 292.823760407 | +8.74072e-07 | 0.00115497 |

Transient observables were compared every 300 s, including 0 and 86400 s.
Steady-state values are heating capacities, the negative of each temperature
source's port heat flow.
Differences are absolute in the units shown. No model parameters, solver
settings, or initialization were changed; these are the observed numerical
differences after upgrading the compiler and runtime.

Compilation passed for all definitions using the 3.5.0-rc2 compiler-only source
build at dyad-lang commit `a24a2240667872d432a3b86c4db1240d77150e35`.
Generated Julia was regenerated with compiler-emitted whitespace preserved, including
the constructor API version checks,
dotted override dictionaries, parameter seeding, and analysis setup adaptors.
Workspace instantiation passed; its ignored manifest was regenerated.

An initial standard-load attempt was stopped during optional Makie
precompilation at about 4.4 GB resident memory, before any analysis ran. The
complete numerical and test runs below used `--compiled-modules=no` and
`OPENBLAS_NUM_THREADS=1` to avoid that optional graphics precompilation.

`test/runtests.jl` passed: 15 analysis assertions. The existing generated
component testset also loaded successfully and contains zero assertions. Tests
check successful solves and full horizons, finite output temperatures, and the
physical bounds or sizing fixtures appropriate to this project.

Re-run the tests from the repository root after instantiation:

```sh
julia +dyad-3.5.0 --startup-file=no --compiled-modules=no -O0 --project=DynamicSteadyState DynamicSteadyState/test/runtests.jl
```

Not run: documentation rendering, graphical dashboards/animation export, or
interactive plotting scripts. Their numerical analyses are covered above.
No training workloads are defined or required for this project.
