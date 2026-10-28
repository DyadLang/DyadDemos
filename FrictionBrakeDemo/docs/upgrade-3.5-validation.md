# Dyad 3.5 upgrade validation — FrictionBrakeDemo

Current target: Dyad **3.5.1**. Commands below use that channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Validated on 2026-10-26 with Dyad **3.5.0-rc2 / Julia 1.13.2**, against the original project on **Dyad 3.4.0 / Julia 1.12.7**. Both use two Julia threads and one precompile task. The original project and generated sources were preserved before editing. Each environment was instantiated in an isolated project copy to avoid concurrent top-level workspace edits; ignored manifests were regenerated and copied back.

## Migration and source review

Updated the kernel pin to 3.5.0 and editor channel to dyad-3.5.0-rc2 and compat entries to the 3.5 distribution's component versions. Regenerated all Julia outputs with the RC2 compiler from `JuliaComputing/dyad-lang` commit `a24a2240667872d432a3b86c4db1240d77150e35` (compiler-only source build). The earlier packaged RC1 binary was superseded by that RC2 regeneration. Constructors now use API 2 (`__overrides` dictionaries with dotted paths); analyses now emit `__System`, immutable `__Spec`, and `setup_analysis` adaptors. Existing `.dyad` equations and helper functions compile and run through these APIs without source changes.

Reviewed the applicable component changelogs before component migration:

- [BlockComponents changelog](https://github.com/JuliaComputing/BlockComponents/blob/main/CHANGELOG.md)
- [RotationalComponents changelog](https://github.com/JuliaComputing/RotationalComponents/blob/main/CHANGELOG.md)
- [ThermalComponents changelog](https://github.com/JuliaComputing/ThermalComponents/blob/main/CHANGELOG.md)
- [TranslationalComponents changelog](https://github.com/JuliaComputing/TranslationalComponents/blob/main/CHANGELOG.md)
- [DyadInterface 7.5.1 changes](https://github.com/JuliaComputing/DyadInterface.jl/blob/main/CHANGELOG.md): generated analysis setup and `__system` compatibility.

## Every defined analysis

Every analysis below passed on both runtimes at its original defaults: successful solver return code, full configured horizon, and finite state samples. No horizon, solver tolerance, equation, initial condition, snapshot, or test tolerance was changed for validation. Errors compare dense solutions on the same **201 equally spaced times**, including both endpoints. Matching uses symbolic state names rather than state-vector position. Maximum and RMS errors are absolute, in each named state's units; these sampled errors are not bounds between sample times.

| Analysis | Stop (s) | 3.4 / 3.5 | Compared states | State with largest absolute difference | Max error | RMS error (same state) |
|---|---:|---|---:|---|---:|---:|
| `BrakeThermalAnalysis_Constant` | 1800 | PASS / PASS | 2 | `brake_thermal.disk_mass.T` | 6.82121e-13 | 2.38418e-13 |
| `BrakeThermalAnalysis_Step` | 5000 | PASS / PASS | 2 | `brake_thermal.disk_mass.T` | 0.0375801 | 0.00474675 |
| `FrictionBrakeTestAnalysis` | 4.75 | PASS / PASS | 2 | `inertia.w` | 2.84217e-13 | 3.93289e-14 |
| `SimpleVehicleTestAnalysis_CoastDown` | 100 | PASS / PASS | 2 | `vehicle.vehicle_mass.s` | 1.36424e-12 | 3.54987e-13 |
| `SimpleVehicleTestAnalysis_Constant` | 100 | PASS / PASS | 2 | `vehicle.vehicle_mass.s` | 3.86535e-12 | 6.36882e-13 |
| `TestDriverAnalysis_Braking` | 12 | PASS / PASS | 2 | `vehicle_speed` | 1.38101e-06 | 2.89321e-07 |
| `TestDriverAnalysis_Constant` | 10 | PASS / PASS | 2 | `driver.speed_pid.derivative.x` | 8.11156e-11 | 1.26362e-11 |
| `TestPowertrainTransient` | 50 | PASS / PASS | 3 | `load.spline_a.tau` | 0.0114744 | 0.00082281 |
| `VehicleCycleAnalysis` | 1000 | PASS / PASS | 6 | `powertrain.torque` | 0.000273395 | 4.33246e-05 |

The heat-cutoff run differs by at most **0.0375801 K** in disk temperature (RMS **0.00474675 K**) and **0.0138473 K** in pad temperature on this grid. The final disk temperature differs by **1.97e-7 K**. The powertrain differs by **0.0114744 N·m** in load flange torque, **0.00103912 rad/s** in speed, and **0.000508906 rad** in angle. The full vehicle cycle differs by **0.000273395 N·m** in powertrain torque and **1.52009e-5 K** in disk temperature. These are observed numerical changes; no tolerance was widened.

The solver retains different equivalent PID state names between versions; BlockComponents' changelog includes state-priority changes. Consequently the driver comparisons include two of three states, and the full vehicle comparison includes six of seven; unmatched internal PID state names are excluded. The physical speed, thermal and torque states remain covered. The regression suite separately compares its declared physical signals, including wheel speed, heat flow and braking torque, against the unchanged snapshots. The full vehicle regression runs **2000 s**, longer than the defined analysis's **1000 s**; the powertrain regression runs **4.75 s**, while its defined analysis runs **50 s**. Both horizons were exercised.

## Existing tests and reproduction

`Pkg.test(; allow_reresolve=false)` **passed: 2121 assertions**, using the regenerated code and unchanged snapshots. All project environments instantiated successfully. Project TOML and notebook JSON parsing passed. A second RC2 compilation was byte-identical (all outputs skipped).

From this project, using the Dyad 3.5 Julia channel:

```sh
julia +dyad-3.5.1 --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia +dyad-3.5.1 --project=. scripts/validate_upgrade.jl /path/to/results
```

The validation script runs every exported concrete analysis, checks the solver result and stop time, writes `analyses.tsv` plus one sampled state trace per analysis, and exits with an error if any analysis fails. Run the same script against a preserved 3.4 project to reproduce the numerical comparison, matching trace columns by symbolic state name.

No training analyses are defined in this project. No training or parameter optimization was run. Interactive notebook selection/plotting cells, documentation HTML rendering, and manual plotting scripts were not executed; their underlying defined analyses and existing regression suite were exercised as described above. No snapshots were refreshed.
