# Dyad 3.5 upgrade validation

Current target: Dyad **3.5.1**. Commands below use that channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Validated with Dyad 3.5.0-rc2 (Julia 1.13.2-dyad), 2026-10-26. Generated Julia comes from the `v3.5.0-rc2` compiler (a24a224), using its compiler-only CLI build. Package manifests were instantiated and remain ignored.

## Migration and research

Pinned BlockComponents 5.0.0, DiscreteComponents 0.6.0, DyadData 2.3.0, DyadInterface 7.5.1, DyadEcosystemDependencies 0.11.20 and Julia 1.13.2; updated editor and notebook toolchain pins (Orchestrator fallback 0.15.0). The old kernel pin was 3.3.0. Read the [BlockComponents changelog](https://github.com/JuliaComputing/BlockComponents/blob/v5.0.0/CHANGELOG.md), [DiscreteComponents release history](https://github.com/JuliaComputing/DiscreteComponents/compare/v0.2.0...v0.6.0), [DyadData release notes](https://github.com/JuliaComputing/DyadData.jl/releases/tag/v2.3.0) and [DyadInterface changelog](https://github.com/JuliaComputing/DyadInterface.jl/blob/v7.5.1/CHANGELOG.md). DiscreteComponents has no CHANGELOG.md; its history documents the sampler, initialization and constructor API migrations.

Regenerated constructor API 2 and analysis setup adaptors. FIR coefficients, clock interval and signal connections are unchanged. DiscreteComponents 0.6 is required for compatibility with BlockComponents 5. Added the project icon required by the repository conventions. The compiler reports an `invalid-clock-usage` warning inside the dependency's `continuous_discrete.dyad`; compilation succeeds.

## Results

The old comparison uses Dyad 3.4.0 (Julia 1.12.7-dyad) and the original project sources at `49fd57f`; the FIR project originally pinned kernel 3.3.0. The new runs use Dyad 3.5.0-rc2.

<!-- analysis-results:start -->
All runs use the declared analysis defaults, including horizons and solver tolerances. Each reconstructed trajectory is sampled at 51 evenly spaced times. Adaptive save-grid interpolation can contribute to sampled differences; the endpoint column compares values at the declared stop time. The magnitude columns use each signal’s native units; they are diagnostic maxima, not a norm combining physical units.

| Analysis | New result | Largest final magnitude | Max sampled old/new change | Max endpoint change |
|---|---|---:|---:|---:|
| `TestFIRFilterAnalysis` | pass (5 signals) | 0.978340551 | 1.707038e-09 | 7.620127e-12 |
| `World` | pass (1 signals) | 299.999991 | 5.684342e-14 | 0 |

- `TestFIRFilterAnalysis`: 5 common signals; largest sampled change is 1.707038e-09 in `sampler₊u(t)`. Largest scaled change is 1.707038e-09, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `World`: 1 common signals; largest sampled change is 5.684342e-14 in `T(t)`. Largest scaled change is 1.776357e-16, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
<!-- analysis-results:end -->

The ODE analysis inventory omits the hybrid parameter timeseries that carry clocked outputs. These were checked separately through `sol[result."sampler.y"]` and `sol[result."firfilter.realoutput"]`, using `DyadInterface.rebuild_sol(result)`.

The native clock records all 26 ticks from 0 to 6.25 s in 0.25 s steps. The maximum old/new output difference is 2.47940e-11, including the endpoint; the new peak output magnitude is 0.308362699609. The maximum error against the recurrence with coefficients `[-3/16, 31/32, 0, -31/32, 3/16]` and zero initial delay history is 5.55112e-17. [The complete clocked comparison](upgrade-3.5-clocked.csv) is retained with this report.

`Pkg.test(; allow_reresolve=false)` passed all seven assertions: two existing generated checks and five native-clock FIR checks (sample count, finite values, recurrence and nonzero output). The recurrence checks are in `test/clocked_filter.jl` and run as part of the normal test suite.

No training is defined or run. The interactive notebook was not executed; its two underlying declared analyses are covered above.

## Reproduction

```sh
julia +dyad-3.5.1 --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test(;allow_reresolve=false)'
julia +dyad-3.5.1 --project=. test/validate_upgrade.jl results.toml
```

Run from the project directory. The runner discovers analyses from `.dyad` files, preserves default horizons and tolerances, and records solver return codes, finite samples and 51-point trajectories. Use `JULIA_NUM_THREADS=2`, `JULIA_NUM_PRECOMPILE_TASKS=1` and `JULIA_PKG_PRECOMPILE_AUTO=0` for the validation resource limits.

The compiler emits whitespace-only lines in generated analysis definitions; these are retained to preserve its output. `git diff --check` flags those generated lines. Handwritten changes pass the whitespace check.
