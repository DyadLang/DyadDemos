# Dyad 3.5 upgrade

The demos previously targeted Dyad 3.4.0. This upgrade uses the newest available
3.5 release candidate channel, **`dyad-3.5.0-rc2`**, based on **Julia 1.13.2**.
The compiler source is tag `v3.5.0-rc2`, commit
`a24a2240667872d432a3b86c4db1240d77150e35`.
The comparison distribution is `dyad-3.4.0` (Julia 1.12.7).

## Toolchain

Install juliaup into a local directory and select JuliaHub's distribution server:

```sh
export JULIAUP_DEPOT_PATH="$PWD/.toolchain/juliaup"
export JULIAUP_SERVER=https://juliahub.com/juliabin
export JULIA_DEPOT_PATH="$PWD/.toolchain/depot"
export JULIA_PKG_USE_CLI_GIT=true
export JULIA_NUM_THREADS=2
export JULIA_NUM_PRECOMPILE_TASKS=1
# Use the juliaup executable from your local installation:
juliaup list
juliaup add dyad-3.5.0-rc2
export JULIA_EXECUTABLE="julia +dyad-3.5.0-rc2"
```

Private Dyad Julia packages and the compiler source require the existing
JuliaHub/GitHub credentials. Keep credentials outside tracked files.

The rc2 tag has no prebuilt GitHub release asset. The pinned compiler-only build
in `.ci/compiler` uses the original compiler and documentation code with public
npm dependencies. It avoids the private layout, data CLI, and agent-resource
packages needed by the full CLI, without changing compiler semantics.
Node.js 22 or newer and npm are required:

```sh
.ci/compiler/setup.sh
export DYAD_CLI_PATH="$PWD/.ci/compiler/dyad"
"$DYAD_CLI_PATH" --version
"$DYAD_CLI_PATH" compile "$PWD/CoffeeMugDemo"
julia +dyad-3.5.0-rc2 --project=CoffeeMugDemo -e 'using Pkg; Pkg.test()'
```

The wrapper supports `compile [directory]`, `document [library]`, and `--version`.
For other commands, install the full Dyad CLI separately. CI builds this pinned
compiler, selects the rc2 distribution, regenerates before testing, and fails
if any project's validation fails while continuing to check the other projects.

## Migration research

The [3.5 project migration](https://github.com/JuliaComputing/dyad-studio/blob/main/src/migrations/upgrade-3.5.0.ts)
and the [distribution package set](https://github.com/JuliaComputing/DyadEcosystemDependencies.jl)
were checked before editing, together with the component-library changelogs
linked in each project's validation notes. The relevant library majors are
BlockComponents 5, ElectricalComponents 3, RotationalComponents 3,
TranslationalComponents 3, ThermalComponents 3, and MultibodyComponents 0.3.

The [compiler changes since 3.4](https://github.com/JuliaComputing/dyad-lang/compare/v3.4.0...v3.5.0-rc2)
include generated analysis systems and immutable analysis specifications, dotted
constructor override dictionaries, and stricter checks on inherited names and
placements. Regeneration updates the generated Julia interfaces; project sources
and custom Julia analyses must follow the new interfaces. Per-project notes
record the concrete changes and numerical comparisons.

## Validation results

All 14 projects instantiate and their package tests pass (3412 assertions in
total). Manifests were resolved with the new distribution and remain ignored,
as in the original repository. All 74 concrete declared analyses were exercised;
partial analysis declarations are excluded. The table distinguishes successful
solves from optimizer limits and incomplete training. Numerical differences
are sampled comparisons, not continuous error bounds. Follow each project link
for every analysis, metrics, baseline adjustments, and reproduction commands.

| Project / detailed results | Analyses | Result and observed old/new changes |
|---|---:|---|
| [CoffeeMugDemo](CoffeeMugDemo/docs/upgrade-3.5-validation.md) | 2 | Both pass; maximum sampled temperature change 3.25e-9 °C. |
| [TurkeyDemo](TurkeyDemo/docs/upgrade-3.5-validation.md) | 1 | Pass; maximum sampled temperature change 1.33e-6 K. |
| [ThermalHouseDemo](ThermalHouseDemo/docs/upgrade-3.5-validation.md) | 2 | Both pass; maximum sampled change 1.05e-8 K / 1.19e-4 W. |
| [DynamicSteadyState](DynamicSteadyState/docs/upgrade-3.5-validation.md) | 3 | All pass; transient change up to 0.00363 K, sizing change up to 2.28e-13 W. |
| [FrictionBrakeDemo](FrictionBrakeDemo/docs/upgrade-3.5-validation.md) | 9 | All pass; disk-temperature change up to 0.0375801 K, final change 1.97e-7 K. |
| [HybridTransmission](HybridTransmission/docs/upgrade-3.5-validation.md) | 1 | Pass; final fuel +0.0453073 g (0.00351%); controller speed changes up to 16.4933 rad/s at transitions. |
| [PassiveSuspension](PassiveSuspension/docs/upgrade-3.5-validation.md) | 2 | Both pass; maximum passive wheel-velocity change 3.22414e-7 m/s. |
| [DrivelineSciML](DrivelineSciML/docs/upgrade-3.5-validation.md) | 7 | Five transients pass; stage 1 calibration retains `Infeasible` on both versions, stage 2 succeeds. Largest speed change 0.01421 rad/s. Chained fit and held-out plot export complete. |
| [QuarterTruckSciML](QuarterTruckSciML/docs/upgrade-3.5-validation.md) | 8 | Five transients pass; physical calibration reaches its 100-iteration limit on both versions. Adam/LBFGS validated only at 25/10 limits; short-run final objective is 28.3% higher on 3.5. Full 5000/200 retraining remains unvalidated. |
| [MotorTemperatureSciML](MotorTemperatureSciML/docs/upgrade-3.5-validation.md) | 11 | Free-running solves pass; shipped-fit RMS-error drift ≤0.001544 °C. Quick training completes its declared six Adam steps with `ConvergenceFailure` on both versions; objective changes +0.152%. Newly trained weights reload successfully. |
| [HL20Demo](HL20Demo/docs/upgrade-3.5-validation.md) | 0 | Aerodynamic core constructs and all 20 tests pass. Full-flight analyses in the design brief are not implemented; the old standalone core did not construct. |
| [SatelliteGNC](SatelliteGNC/docs/upgrade-3.5-validation.md) | 7 | All pass; maximum sampled 6-DOF position change 0.014796 m. |
| [MakieWebinar](MakieWebinar/docs/upgrade-3.5-validation.md) | 19 | All pass; two old oscillator initialization failures repaired. Largest sampled diffusion change 0.002618434. Additional headless PID tuning succeeds (objective 0.000232781). |
| [FIRFilterComponents](FIRFilterComponents/docs/upgrade-3.5-validation.md) | 2 | Both pass; native clocked-output change ≤2.4794e-11 across all 26 ticks, recurrence error ≤5.56e-17. |

The full QuarterTruck training attempts were interrupted after roughly 23 minutes
on 3.5 and 17 minutes on 3.4, without a returned result. Its default training
budgets and committed pretrained weights are preserved. Motor's standalone
longer training scripts and PyTorch trainer were not run; all its declared
analyses, including quick training, were run. Non-success optimizer statuses
above are retained explicitly rather than treated as convergence.

GUI dashboards, interactive notebooks, animation rendering, and a complete
documentation HTML build were not validated. Numerical analyses underlying
them were exercised, and several headless plot exporters were checked. Optional
upstream CSV/render/GLMakie extension diagnostics are documented in the project
reports. DynamicSteadyState used `--compiled-modules=no` to avoid costly optional
graphics precompilation. CI setup, compiler compilation/documentation smoke
checks, and CI environment instantiation passed locally; the full hosted CI job
has not yet run.

Two projects require a reproducible RC2 generated-code correction after each
compilation: run `scripts/fix_analysis_codegen.jl` in DrivelineSciML and
QuarterTruckSciML. These replace the generated UnionAll dataset annotation with
the concrete `typeof(__local__data)` type; CI applies the same correction before
testing. Regression tests cover construction of the affected analyses.
