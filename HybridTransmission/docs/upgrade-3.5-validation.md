# Dyad 3.5 upgrade validation — HybridTransmission

Current Julia distribution: **dyad-3.5.0**; Dyad CLI target: **3.5.1**. Commands below use the 3.5.0 Julia channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Validated on 2026-10-26 with Dyad **3.5.0-rc2 / Julia 1.13.2**, against the original project on **Dyad 3.4.0 / Julia 1.12.7**. Both use two Julia threads and one precompile task. The original project and generated sources were preserved before editing. Each environment was instantiated in an isolated project copy to avoid concurrent top-level workspace edits; ignored manifests were regenerated and copied back.

## Migration and source review

Updated the kernel pin to 3.5.0 and editor channel to dyad-3.5.0-rc2 and compat entries to the 3.5 distribution's component versions. Regenerated all Julia outputs with the RC2 compiler from `JuliaComputing/dyad-lang` commit `a24a2240667872d432a3b86c4db1240d77150e35` (compiler-only source build). The earlier packaged RC1 binary was superseded by that RC2 regeneration. Constructors now use API 2 (`__overrides` dictionaries with dotted paths); analyses now emit `__System`, immutable `__Spec`, and `setup_analysis` adaptors. Existing `.dyad` equations and helper functions compile and run through these APIs without source changes.

Reviewed the applicable component changelogs before component migration:

- [BlockComponents changelog](https://github.com/JuliaComputing/BlockComponents/blob/main/CHANGELOG.md)
- [RotationalComponents changelog](https://github.com/JuliaComputing/RotationalComponents/blob/main/CHANGELOG.md)
- [DyadInterface 7.5.1 changes](https://github.com/JuliaComputing/DyadInterface.jl/blob/main/CHANGELOG.md): generated analysis setup and `__system` compatibility.
- [DyadOrchestrator 0.15.0 changes](https://github.com/JuliaComputing/DyadOrchestrator.jl/blob/main/CHANGELOG.md): supports the generated `__Spec` suffix; updated notebook setup version accordingly.
- [DyadData 2.0.1 → 2.3.0 history](https://github.com/JuliaComputing/DyadData.jl/compare/v2.0.1...v2.3.0): the repository has no changelog. Plain CSV reads now use DelimitedFiles; optional CSV/Parquet parsers require their extensions. These models do not use custom parser options.

## Every defined analysis

Every analysis below passed on both runtimes at its original defaults: successful solver return code, full configured horizon, and finite state samples. No horizon, solver tolerance, equation, initial condition, snapshot, or test tolerance was changed for validation. Errors compare dense solutions on the same **201 equally spaced times**, including both endpoints. Matching uses symbolic state names rather than state-vector position. Maximum and RMS errors are absolute, in each named state's units; these sampled errors are not bounds between sample times.

| Analysis | Stop (s) | 3.4 / 3.5 | Compared states | State with largest absolute difference | Max error | RMS error (same state) |
|---|---:|---|---:|---|---:|---:|
| `TestPowerSplitHybrid` | 765 | PASS / PASS | 7 | `mg1.flange.phi` | 50.1855 | 29.8949 |

The default analysis retains its original `reltol=1e-3`, `abstol=1e-6`, `saveat=0.5`, and 765 s horizon. Key physical comparisons (201 common sample times):

| State | 3.4 final | 3.5 final | Maximum absolute difference | RMS difference |
|---|---:|---:|---:|---:|
| `battery.SOC` | 0.399176851386 | 0.399176582228 | 0.000287799 | 3.7743e-05 |
| `battery.energy_discharged` | 391.605139797 | 391.605664656 | 0.561208 | 0.0735989 |
| `controller.engine_omega` | 288.039203555 | 288.039521208 | 16.4933 | 1.25881 |
| `engine.fuel_consumed` | 1291.93937216 | 1291.98467943 | 0.138568 | 0.036084 |
| `mg1.flange.phi` | 651259.734866 | 651309.92036 | 50.1855 | 29.8949 |
| `mg2.flange.phi` | 51369.9153626 | 51365.5962018 | 4.33036 | 2.90113 |
| `vehicle.omega_wheel` | 62.9500638763 | 62.9500704525 | 0.141862 | 0.017511 |

Fuel consumption ends at **1291.984679 g**, versus **1291.939372 g** before the upgrade (**+0.0453073 g**, about **0.00351%**). Final battery SOC changes by **-2.69158e-7**, with maximum trajectory difference **0.000287799**. The MG1 angle is an accumulated angle: its 50.1855 rad difference is about **0.00771%** of the 651260 rad baseline endpoint. Controller engine speed differs by up to **16.4933 rad/s** around transitions at the shipped analysis tolerances. These differences are reported without altering solver settings. The existing regression suite independently solves at `reltol=abstol=1e-6` and checks its unchanged physical-signal snapshots and endpoints.

## Existing tests and reproduction

`Pkg.test(; allow_reresolve=false)` **passed: 407 assertions**, using the regenerated code and unchanged snapshots. All project environments instantiated successfully. Project TOML and notebook JSON parsing passed. A second RC2 compilation was byte-identical (all outputs skipped).


Notebook API smoke checks also passed: `DyadOrchestrator.load_package` returned the correct module and `list_analyses` listed every regenerated analysis (one hybrid / two suspension).
From this project, using the Dyad 3.5 Julia channel:

```sh
julia +dyad-3.5.0 --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia +dyad-3.5.0 --project=. scripts/validate_upgrade.jl /path/to/results
```

The validation script runs every exported concrete analysis, checks the solver result and stop time, writes `analyses.tsv` plus one sampled state trace per analysis, and exits with an error if any analysis fails. Run the same script against a preserved 3.4 project to reproduce the numerical comparison, matching trace columns by symbolic state name.

No training analyses are defined in this project. No training or parameter optimization was run. Interactive notebook selection/plotting cells, documentation HTML rendering, and manual plotting scripts were not executed; their underlying defined analyses and existing regression suite were exercised as described above. No snapshots were refreshed.
