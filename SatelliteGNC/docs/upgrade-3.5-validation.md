# Dyad 3.5 upgrade validation

Current Julia distribution: **dyad-3.5.0**; Dyad CLI target: **3.5.1**. Commands below use the 3.5.0 Julia channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Validated with Dyad 3.5.0-rc2 (Julia 1.13.2-dyad), 2026-10-26. Generated Julia comes from the `v3.5.0-rc2` compiler (a24a224), using its compiler-only CLI build. Package manifests were instantiated and remain ignored.

## Migration and research

Pinned DyadEcosystemDependencies 0.11.20, DyadInterface 7.5.1 and Julia 1.13.2; updated editor, documentation and notebook toolchain pins (Orchestrator fallback 0.15.0). Read the [DyadInterface changelog](https://github.com/JuliaComputing/DyadInterface.jl/blob/v7.5.1/CHANGELOG.md), including the new immutable analysis specs, analysis system handoff and setup adaptors. Regenerated constructor API 2 and derived analyses; the dynamics, controller and trajectory formulas are unchanged.

## Results

The old comparison uses Dyad 3.4.0 (Julia 1.12.7-dyad) and the original project sources at `49fd57f`. The new runs use Dyad 3.5.0-rc2.

<!-- analysis-results:start -->
All runs use the declared analysis defaults, including horizons and solver tolerances. Each reconstructed trajectory is sampled at 51 evenly spaced times. Adaptive save-grid interpolation can contribute to sampled differences; the endpoint column compares values at the declared stop time. The magnitude columns use each signal’s native units; they are diagnostic maxima, not a norm combining physical units.

| Analysis | New result | Largest final magnitude | Max sampled old/new change | Max endpoint change |
|---|---|---:|---:|---:|
| `TestAllocatorJetsSim` | pass (110 signals) | 0.2307692 | 4.336809e-19 | 4.336809e-19 |
| `TestFullGNC6DOFSim` | pass (185 signals) | 6764045.79 | 0.01479602 | 0.01479602 |
| `TestFullGNCSim` | pass (60 signals) | 0.523618805 | 0.0001622002 | 9.202383e-07 |
| `TestOrbitPropagationSim` | pass (30 signals) | 6770999.91 | 1.466912e-05 | 1.466912e-05 |
| `TestSatelliteClosedLoopSim` | pass (33 signals) | 0.261821931 | 1.834765e-08 | 1.157681e-08 |
| `TestSatelliteOpenLoopSim` | pass (15 signals) | 0.5 | 0 | 0 |
| `TestSingleJetSim` | pass (11 signals) | 0.5 | 0 | 0 |

- `TestAllocatorJetsSim`: 110 common signals; largest sampled change is 4.336809e-19 in `jet6₊tz_out(t)`. Largest scaled change is 4.336809e-19, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestFullGNC6DOFSim`: 18 common signals; largest sampled change is 0.01479602 in `sat₊pos_y(t)`. Largest scaled change is 8.166457e-05, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestFullGNCSim`: 12 common signals; largest sampled change is 0.0001622002 in `sat₊wz(t)`. Largest scaled change is 0.0001622002, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestOrbitPropagationSim`: 12 common signals; largest sampled change is 1.466912e-05 in `sat₊pos_y(t)`. Largest scaled change is 2.170729e-12, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestSatelliteClosedLoopSim`: 6 common signals; largest sampled change is 1.834765e-08 in `ctrl₊wx_meas(t)`. Largest scaled change is 1.834765e-08, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestSatelliteOpenLoopSim`: 6 common signals; largest sampled change is 0 in `sat₊wz(t)`. Largest scaled change is 0, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestSingleJetSim`: 11 common signals; largest sampled change is 0 in `jet₊tz_out(t)`. Largest scaled change is 0, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
<!-- analysis-results:end -->

The existing `Pkg.test(; allow_reresolve=false)` suite passed; it contains zero model assertions. The separate validation runner executed every one of the seven declared analyses, checked successful solver returns and finite results, and sampled each state at 51 evenly spaced times. For algebraic-only jet and allocator cases, it sampled all observable outputs instead. No training is defined or run.

Initial tests logged a DyadDataCSVExt extension precompile error when CSV was loaded by the generated test harness. Declaring DyadData directly resolved it; the post-review package test rerun passed without that diagnostic.

## Reproduction

```sh
julia +dyad-3.5.0 --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test(;allow_reresolve=false)'
julia +dyad-3.5.0 --project=. test/validate_upgrade.jl results.toml
```

Run from the project directory. The runner discovers analyses from `.dyad` files, preserves default horizons and tolerances, and writes sampled trajectories and errors to TOML. Use `JULIA_NUM_THREADS=2`, `JULIA_NUM_PRECOMPILE_TASKS=1` and `JULIA_PKG_PRECOMPILE_AUTO=0` for the validation resource limits.

The compiler emits whitespace-only lines in generated analysis definitions; these are retained to preserve its output. `git diff --check` flags those generated lines. Handwritten changes pass the whitespace check.
