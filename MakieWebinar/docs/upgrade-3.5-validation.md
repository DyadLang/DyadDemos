# Dyad 3.5 upgrade validation

Current target: Dyad **3.5.1**. Commands below use that channel; recorded results and compiler hashes describe the original RC2 validation and have not been rerun on 3.5.1.

Validated with Dyad 3.5.0-rc2 (Julia 1.13.2-dyad), 2026-10-26. Generated Julia comes from the `v3.5.0-rc2` compiler (a24a224), using its compiler-only CLI build. Package manifests were instantiated and remain ignored.

## Migration and research

Pinned BlockComponents 5.0.0; Electrical, Rotational, Thermal and TranslationalComponents 3.0.0; DyadExampleComponents 2.0.0; DyadControlSystems 2.5.0; DyadData 2.3.0; DyadInterface 7.5.1; Julia 1.13.2. Updated editor and documentation pins. Added the missing `scripts/Project.toml` and moved the script-only DyadControlSystems dependency there. Its release deliberately omits generated model code and cannot satisfy the new constructor API guard when imported as a model-library dependency. The main package now imports only the constructor API 2 libraries it needs; the optional autotuning script uses the scripts workspace member. The shared workspace manifest still resolves its control and optimizer dependencies.

Read the changelogs for [BlockComponents](https://github.com/JuliaComputing/BlockComponents/blob/v5.0.0/CHANGELOG.md), [ElectricalComponents](https://github.com/JuliaComputing/ElectricalComponents/blob/v3.0.0/CHANGELOG.md), [RotationalComponents](https://github.com/JuliaComputing/RotationalComponents/blob/v3.0.0/CHANGELOG.md), [ThermalComponents](https://github.com/JuliaComputing/ThermalComponents/blob/v3.0.0/CHANGELOG.md), [TranslationalComponents](https://github.com/JuliaComputing/TranslationalComponents/blob/v3.0.0/CHANGELOG.md), [DyadExampleComponents](https://github.com/JuliaComputing/DyadExampleComponents/blob/v2.0.0/CHANGELOG.md) and [DyadInterface](https://github.com/JuliaComputing/DyadInterface.jl/blob/v7.5.1/CHANGELOG.md). Also read [DyadData 2.3 release notes](https://github.com/JuliaComputing/DyadData.jl/releases/tag/v2.3.0) and [DyadControlSystems release history](https://github.com/JuliaComputing/DyadControlSystems.jl/compare/v2.4.2...v2.5.0), which have no CHANGELOG.md.

The library major releases require constructor API 2, so all generated code was regenerated together. The no-damping example previously approximated zero gain using `k=Td=1e-10`, which fails initialization in both the original Dyad 3.4 baseline and the first Dyad 3.5 run. It now uses LimPID structural switches to remove the integral and derivative branches and sets proportional gain to exactly zero. The default controlled oscillator remains a full PID. Redundant wrapper initial conditions were removed; the component still specifies displacement 0.5 m and velocity 0 m/s. A regression test checks the undamped analytical solution and energy conservation. All other model equations and physical defaults are unchanged.

## Results

The old comparison uses Dyad 3.4.0 (Julia 1.12.7-dyad) and the original project sources at `49fd57f`. The new runs use Dyad 3.5.0-rc2.

<!-- analysis-results:start -->
All runs use the declared analysis defaults, including horizons and solver tolerances. Each reconstructed trajectory is sampled at 51 evenly spaced times. Adaptive save-grid interpolation can contribute to sampled differences; the endpoint column compares values at the declared stop time. The magnitude columns use each signal’s native units; they are diagnostic maxima, not a norm combining physical units.

| Analysis | New result | Largest final magnitude | Max sampled old/new change | Max endpoint change |
|---|---|---:|---:|---:|
| `CriticallyDampedAnalysis` | pass (20 signals) | 1.71584916e-09 | 1.998401e-15 | 1.858675e-21 |
| `FastChargeAnalysis` | pass (22 signals) | 10 | 3.552714e-15 | 0 |
| `MediumChargeAnalysis` | pass (22 signals) | 10 | 1.776357e-15 | 0 |
| `NoDampingAnalysis` | pass (51 signals) | 43.1159449 | unavailable | unavailable |
| `OverdampedAnalysis` | pass (20 signals) | 0.0622457382 | 5.438205e-12 | 6.001449e-14 |
| `SlowChargeAnalysis` | pass (22 signals) | 10 | 1.776357e-15 | 0 |
| `StrongDampingAnalysis` | pass (67 signals) | 0.495842545 | 6.863874e-12 | 1.774378e-13 |
| `TestDiffusion30x30Transient` | pass (900 signals) | 1.11111514 | 0.002618434 | 8.570091e-08 |
| `TestDiffusion5x5Transient` | pass (25 signals) | 4 | 3.503275e-06 | 2.220446e-14 |
| `TestFHNWave20x20Transient` | pass (800 signals) | 0.000205477892 | 4.308113e-14 | 9.005573e-15 |
| `TestFHNWaveTransient` | pass (50 signals) | 0.00390618189 | 4.776689e-12 | 1.439764e-13 |
| `TestFitzHughNagumoTransient` | pass (50 signals) | 0.0249882138 | 3.174116e-09 | 1.101089e-09 |
| `TestReactionDiffusionTransient` | pass (25 signals) | 0.487739156 | 2.176037e-14 | 8.881784e-16 |
| `TestReactionGrowth20x20Transient` | pass (400 signals) | 38.262257 | 8.775203e-13 | 1.563194e-13 |
| `TestReactionGrowthTransient` | pass (25 signals) | 643.207134 | 1.250555e-12 | 7.958079e-13 |
| `TestSpringMassTransient` | pass (24 signals) | 9.8872681 | 3.996803e-15 | 2.442491e-15 |
| `UnderdampedAnalysis` | pass (20 signals) | 0.823085275 | 1.24345e-14 | 1.665335e-15 |
| `WeakDampingAnalysis` | pass (67 signals) | 0.248417109 | unavailable | unavailable |
| `World` | pass (1 signals) | 299.999991 | 5.684342e-14 | 0 |

- `CriticallyDampedAnalysis`: 2 common signals; largest sampled change is 1.998401e-15 in `circuit₊capacitor₊v(t)`. Largest scaled change is 1.998401e-16, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `FastChargeAnalysis`: 1 common signals; largest sampled change is 3.552714e-15 in `circuit₊capacitor₊v(t)`. Largest scaled change is 3.552875e-16, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `MediumChargeAnalysis`: 1 common signals; largest sampled change is 1.776357e-15 in `circuit₊capacitor₊v(t)`. Largest scaled change is 1.776438e-16, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `NoDampingAnalysis` old baseline: ExtraEquationsSystemException: Initialization system is overdetermined.
- `OverdampedAnalysis`: 2 common signals; largest sampled change is 5.438205e-12 in `circuit₊capacitor₊v(t)`. Largest scaled change is 5.438205e-13, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `SlowChargeAnalysis`: 1 common signals; largest sampled change is 1.776357e-15 in `circuit₊capacitor₊v(t)`. Largest scaled change is 1.776438e-16, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `StrongDampingAnalysis`: 4 common signals; largest sampled change is 6.863874e-12 in `system₊mass₊v(t)`. Largest scaled change is 5.363084e-12, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestDiffusion30x30Transient`: 900 common signals; largest sampled change is 0.002618434 in `var"caps⸺435₊C"(t)`. Largest scaled change is 0.0006319333, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestDiffusion5x5Transient`: 25 common signals; largest sampled change is 3.503275e-06 in `var"caps⸺13₊C"(t)`. Largest scaled change is 4.677256e-07, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestFHNWave20x20Transient`: 800 common signals; largest sampled change is 4.308113e-14 in `var"bounds⸺40₊port₊C"(t)`. Largest scaled change is 4.308113e-14, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestFHNWaveTransient`: 50 common signals; largest sampled change is 4.776689e-12 in `var"caps⸺12₊u"(t)`. Largest scaled change is 4.776689e-12, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestFitzHughNagumoTransient`: 50 common signals; largest sampled change is 3.174116e-09 in `var"caps⸺8₊u"(t)`. Largest scaled change is 3.174116e-09, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestReactionDiffusionTransient`: 25 common signals; largest sampled change is 2.176037e-14 in `var"caps⸺13₊C"(t)`. Largest scaled change is 2.176037e-14, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestReactionGrowth20x20Transient`: 400 common signals; largest sampled change is 8.775203e-13 in `var"caps⸺189₊C"(t)`. Largest scaled change is 2.312272e-14, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestReactionGrowthTransient`: 25 common signals; largest sampled change is 1.250555e-12 in `var"caps⸺10₊C"(t)`. Largest scaled change is 1.944405e-15, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `TestSpringMassTransient`: 2 common signals; largest sampled change is 3.996803e-15 in `system₊mass₊v(t)`. Largest scaled change is 2.527937e-15, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `UnderdampedAnalysis`: 2 common signals; largest sampled change is 1.24345e-14 in `circuit₊capacitor₊v(t)`. Largest scaled change is 1.24345e-15, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.
- `WeakDampingAnalysis` old baseline: ExtraEquationsSystemException: Initialization system is overdetermined.
- `World`: 1 common signals; largest sampled change is 5.684342e-14 in `T(t)`. Largest scaled change is 1.776357e-16, using `max(abs(new-old))/max(1,max(abs(old)))` per signal.

For the old baseline only, the nonexistent scripts workspace entry and the unused DyadControlSystems dependency/import were removed from the temporary comparison copy. The temporary baseline is loaded by inclusion to avoid GUI precompilation in the headless process. Model equations, parameters and initialization were left as checked in. The new no-damping case is additionally checked against the analytical oscillator solution.
<!-- analysis-results:end -->

`Pkg.test(; allow_reresolve=false)` passed all five assertions: two existing generated checks and three analytical oscillator checks. With `saveat=0.1`, maximum position error against `0.5*cos(10t)` was 2.03031e-6 m, maximum velocity error against `-5*sin(10t)` was 2.23020e-5 m/s, and maximum relative energy drift was 4.47140e-6. The uniform save grid avoids comparing the analytical solution with interpolation between sparse serialized solver samples.

The test process reports an optional GLMakie initialization/precompile error because `DISPLAY` is absent, then completes its numerical tests successfully. GUI behavior remains unvalidated in this headless environment.

The optional autotuning script uses the supported `reference_input` sentinel, a unit tracking target (`ref=1.0`), and the `y` analysis point. The original variable paths `set_point.y` and `seat_pos.s` failed the analysis-point linearizer. Its configured `num_frequencies` is 200; with automatic frequency limits the library chooses its own grid.

The scripts environment pins OptimizationMOI 1.4.1, whose [declared compatibility](https://github.com/SciML/Optimization.jl/blob/OptimizationMOI-v1.4.1/lib/OptimizationMOI/Project.toml) supports the distribution’s OptimizationBase 5.7.0. OptimizationMOI 1.6.0 called the absent `OptimizationBase.despecialize` and failed before Ipopt initialization. The [release history](https://github.com/SciML/Optimization.jl/compare/OptimizationMOI-v1.4.1...OptimizationMOI-v1.6.0) and NLP implementation were checked before adding the pin.

The final headless unit-reference PID autotuning run passed with Ipopt `Success` / “Optimal Solution Found.” `run_analysis` took 129.996 s including JIT compilation; its automatic grid contained 567 frequencies. The objective was 0.000232781153; parallel-form parameters `[kp, ki, kd, Tf]` were `[0.010864914347610397, 867462.6795089559, 291114.8333267874, 0.00030251199216164477]`. [The numerical result](upgrade-3.5-autotuning.toml) is retained. This is an additional successful script analysis beyond the 19 declared `.dyad` analyses. No old optimized-controller comparison was run; the original script failed its analysis-point lookup on the new stack.

For headless reproduction, load the model/spec portion of `scripts/05_autotuning_analysis.jl` and call `DyadInterface.run_analysis(spec)` instead of launching the designer. The final attempt completed within its 300 s limit; earlier API checks used a 150 s limit and failed on the errors described above before reaching optimization. A zero-reference diagnostic also converged after the dependency pin; the retained result uses the explicit unit reference.

ControlSystemsMTK emits an upstream warning about the removed `ModelingToolkit.FnType` import. The suspension linearization also warns about its underdetermined initialization and a frequency grid below the Nyquist constraint frequency; these warnings are preserved. The GUI designer was not launched.

No machine-learning training is defined or run. GUI interaction, GLMakie windows, live sliders, video recording and `launch_pid_autotuning_designer` were not run in this headless environment. The 19 declared analyses used by the visualizations are covered above; this does not claim a successful interactive autotuning session.

## Reproduction

```sh
julia +dyad-3.5.1 --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test(;allow_reresolve=false)'
julia +dyad-3.5.1 --project=. test/validate_upgrade.jl results.toml
```

Run from the project directory. The runner discovers analyses from `.dyad` files, preserves default horizons and tolerances, and records solver return codes, finite samples and 51-point state trajectories. Use `JULIA_NUM_THREADS=2`, `JULIA_NUM_PRECOMPILE_TASKS=1` and `JULIA_PKG_PRECOMPILE_AUTO=0` for the validation resource limits.

The compiler emits whitespace-only lines in generated analysis definitions; these are retained to preserve its output. `git diff --check` flags those generated lines. Handwritten changes pass the whitespace check.
