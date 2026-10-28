# Dyad 3.5 upgrade validation — PassiveSuspension

Current Julia distribution: **dyad-3.5.0**; Dyad CLI target: **3.5.1**. Commands below use the 3.5.0 Julia channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Validated on 2026-10-26 with Dyad **3.5.0-rc2 / Julia 1.13.2**, against the original project on **Dyad 3.4.0 / Julia 1.12.7**. Both use two Julia threads and one precompile task. The original project and generated sources were preserved before editing. Each environment was instantiated in an isolated project copy to avoid concurrent top-level workspace edits; ignored manifests were regenerated and copied back.

## Migration and source review

Updated the kernel pin to 3.5.0 and editor channel to dyad-3.5.0-rc2 and compat entries to the 3.5 distribution's component versions. Regenerated all Julia outputs with the RC2 compiler from `JuliaComputing/dyad-lang` commit `a24a2240667872d432a3b86c4db1240d77150e35` (compiler-only source build). The earlier packaged RC1 binary was superseded by that RC2 regeneration. Constructors now use API 2 (`__overrides` dictionaries with dotted paths); analyses now emit `__System`, immutable `__Spec`, and `setup_analysis` adaptors. Existing `.dyad` equations and helper functions compile and run through these APIs without source changes.

Reviewed the applicable component changelogs before component migration:

- [BlockComponents changelog](https://github.com/JuliaComputing/BlockComponents/blob/main/CHANGELOG.md)
- [DyadExampleComponents changelog](https://github.com/JuliaComputing/DyadExampleComponents/blob/main/CHANGELOG.md)
- [ElectricalComponents changelog](https://github.com/JuliaComputing/ElectricalComponents/blob/main/CHANGELOG.md)
- [RotationalComponents changelog](https://github.com/JuliaComputing/RotationalComponents/blob/main/CHANGELOG.md)
- [ThermalComponents changelog](https://github.com/JuliaComputing/ThermalComponents/blob/main/CHANGELOG.md)
- [TranslationalComponents changelog](https://github.com/JuliaComputing/TranslationalComponents/blob/main/CHANGELOG.md)
- [DyadInterface 7.5.1 changes](https://github.com/JuliaComputing/DyadInterface.jl/blob/main/CHANGELOG.md): generated analysis setup and `__system` compatibility.
- [DyadOrchestrator 0.15.0 changes](https://github.com/JuliaComputing/DyadOrchestrator.jl/blob/main/CHANGELOG.md): supports the generated `__Spec` suffix; updated notebook setup version accordingly.
- [DyadData 2.0.1 → 2.3.0 history](https://github.com/JuliaComputing/DyadData.jl/compare/v2.0.1...v2.3.0): the repository has no changelog. Plain CSV reads now use DelimitedFiles; optional CSV/Parquet parsers require their extensions. These models do not use custom parser options.
- [DyadEcosystemDependencies 0.11.20 changes](https://github.com/JuliaComputing/DyadEcosystemDependencies.jl/blob/main/CHANGELOG.md): distribution dependency alignment.

## Every defined analysis

Every analysis below passed on both runtimes at its original defaults: successful solver return code, full configured horizon, and finite state samples. No horizon, solver tolerance, equation, initial condition, snapshot, or test tolerance was changed for validation. Errors compare dense solutions on the same **201 equally spaced times**, including both endpoints. Matching uses symbolic state names rather than state-vector position. Maximum and RMS errors are absolute, in each named state's units; these sampled errors are not bounds between sample times.

| Analysis | Stop (s) | 3.4 / 3.5 | Compared states | State with largest absolute difference | Max error | RMS error (same state) |
|---|---:|---|---:|---|---:|---:|
| `ActiveSuspensionTransient` | 10 | PASS / PASS | 7 | `wheel.mass.v` | 3.60711e-13 | 3.30454e-14 |
| `PassiveSuspensionTransient` | 10 | PASS / PASS | 6 | `wheel.mass.v` | 3.22414e-07 | 3.09492e-08 |

Passive wheel velocity differs by at most **3.22414e-7 m/s** (RMS **3.09492e-8 m/s**). Maximum passive seat-position difference is **1.82772e-10 m**. The active reference agrees to **3.60711e-13 m/s** in wheel velocity and **2.97540e-14 m** in seat position. Seven of eight active states match by name; the PID integrator state has an equivalent but different retained symbolic name between library versions. All six passive states match. The two variants keep their original, different road inputs and mass values; they are compared only against their own baselines.

## Existing tests and reproduction

`Pkg.test(; allow_reresolve=false)` **passed: 701 assertions**, using the regenerated code and unchanged snapshots. All project environments instantiated successfully. Project TOML and notebook JSON parsing passed. A second RC2 compilation was byte-identical (all outputs skipped).


Notebook API smoke checks also passed: `DyadOrchestrator.load_package` returned the correct module and `list_analyses` listed every regenerated analysis (one hybrid / two suspension).

The existing 701-assertion suite covers the active reference; the generated passive test file is empty. Both passive and active default analyses were independently run on both runtimes above. The separate docs environment also instantiated successfully.
From this project, using the Dyad 3.5 Julia channel:

```sh
julia +dyad-3.5.0 --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia +dyad-3.5.0 --project=. scripts/validate_upgrade.jl /path/to/results
```

The validation script runs every exported concrete analysis, checks the solver result and stop time, writes `analyses.tsv` plus one sampled state trace per analysis, and exits with an error if any analysis fails. Run the same script against a preserved 3.4 project to reproduce the numerical comparison, matching trace columns by symbolic state name.

No training analyses are defined in this project. No training or parameter optimization was run. Interactive notebook selection/plotting cells, documentation HTML rendering, and manual plotting scripts were not executed; their underlying defined analyses and existing regression suite were exercised as described above. No snapshots were refreshed.
