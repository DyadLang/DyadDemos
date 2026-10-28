# Dyad 3.5 upgrade

The demos target Dyad **3.5.1**, using the `dyad-3.5.1` JuliaHub channel.
This is a text-only update from the RC2 stack: generated code and manifests
have not been regenerated. The results below record the original RC2 validation,
not a new 3.5.1 test run.

## Toolchain

Use a task-local juliaup installation and depot:

```sh
export JULIAUP_DEPOT_PATH="$PWD/.toolchain/juliaup"
export JULIAUP_SERVER=https://juliahub.com/juliabin
export JULIA_DEPOT_PATH="$PWD/.toolchain/depot"
juliaup add dyad-3.5.1
export JULIA_EXECUTABLE="julia +dyad-3.5.1"
```

Private Dyad packages require the existing JuliaHub credentials. Keep credentials
outside tracked files. For local use, install the Dyad 3.5.1 CLI separately
and put `dyad` on PATH (or set `DYAD_CLI_PATH`), as required by DyadHarness.
CI explicitly downloads the Linux x64 CLI and checksums from the `v3.5.1`
GitHub release of `JuliaComputing/dyad-lang`, verifies the checksum and
`dyad --version`, and sets `DYAD_CLI_PATH` to that verified executable.
The self-hosted runner needs GitHub CLI credentials with access to that private
repository. There is no fallback to its preinstalled CLI. The temporary RC2-only
compiler source build has been removed.

At the time of this update, the 3.5.1 CLI release and JuliaHub runtime channel
are not published. CI will fail at provisioning until they become available.

CI selects the 3.5.1 distribution, compiles before testing, and fails if any
project's validation fails while continuing to check the other projects.
It no longer requires patch-release compiler output to match RC2 snapshots
byte for byte. The analysis annotation correction below remains until its
necessity with the new compiler can be checked.

Project compatibility bounds allow compatible library and Julia patch releases.
The OptimizationMOI pin remains for the documented optimizer API regression.

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
| [HybridTransmission](HybridTransmission/docs/upgrade-3.5-validation.md) | 1 | Pass; final fuel +0.0453073 g (0.00351%); controller speed changes up to 16.4933 rad/s at transitions at the shipped reltol=1e-3. |
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
render/GLMakie extension diagnostics are documented in the project reports.
The CSV extension diagnostics found during review were resolved by declaring
DyadData directly in the four affected projects; their package tests pass
without those diagnostics. DynamicSteadyState used `--compiled-modules=no` to avoid costly optional
graphics precompilation. CI setup, compiler compilation/documentation smoke
checks, and CI environment instantiation passed locally; the full hosted CI job
has not yet run.

Two projects require a reproducible RC2 generated-code correction after each
compilation: run `scripts/fix_analysis_codegen.jl` in DrivelineSciML and
QuarterTruckSciML. These replace the generated UnionAll dataset annotation with
the concrete `typeof(__local__data)` type; CI applies the same correction before
testing. Regression tests cover construction of the affected analyses. This is
the upstream [analysis structural-parameter issue](https://github.com/JuliaComputing/dyad-lang/issues/1958).
Dyad Studio recompiles on save: after every such recompile, rerun the script
before using either project's calibration or training analyses. The workaround
is specific to the pinned RC2 compiler and must be reassessed when upgrading it.

An independent Claude review regenerated all 14 projects and reran four package
test suites. It found no result-changing correctness defect and recommended a
draft PR with the training and optimizer limitations above kept explicit.
The follow-up fixes restore consistent compatibility bounds, preserve compiler
output, check regenerated files in CI, declare the missing test dependencies,
and keep local caches ignored. All 22 affected project/docs/scripts environments
resolved and instantiated; all 14 generated trees were verified against the
pinned compiler and the two documented annotation corrections.
Seven affected package test suites passed again after the fixes.
