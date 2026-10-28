# Upstream follow-up drafts

These are draft reports, not filed issues. Tested 2026-10-26 with the exact
3.5.0-rc2/a24a224 compiler, Julia 1.13.2, and the preserved original 3.4 projects
under Julia 1.12.7. See [workflow evidence](followup-workflows.md) for commands,
limits and project reports. Correct model physics is preserved.

## Existing dyad-lang #1958: inherited structural timeseries becomes symbolic

**Suggested supplemental title:** Calibration analysis `data::DyadTimeseries`
becomes a symbolic UnionAll parameter in rc2 `__System`.

The existing open report is
[JuliaComputing/dyad-lang #1958](https://github.com/JuliaComputing/dyad-lang/issues/1958),
“`structural` for parameters in analyses seems ignored.” Its body was read via
`gh api repos/JuliaComputing/dyad-lang/issues/1958`; this is a concrete calibration
reproduction of the structural-parameter problem, not a new issue filing.

`DyadModelOptimizer/dyad/calibration.dyad:42` declares:

```dyad
structural parameter data::DyadData.DyadTimeseries
```

The inherited `data` member of Driveline's analysis nevertheless generates:

```julia
append!(__params, @parameters (data::DyadData.DyadTimeseries))
__initial_conditions[data] = __local__data
```

Calling `DrivelineStage1CalibrationAnalysis__System(; name=:repro)` fails before
initialization or optimization:

```text
MethodError: Cannot convert an object of type Type{DyadTimeseries}
to an object of type DataType
```

The stack passes through SymbolicUtils `Storage#Sym` and the generated
`@parameters` line. `DyadTimeseries` is a parametric/UnionAll type; this data
configuration should remain ordinary Julia structural data, not become a
symbolic state/parameter. The rc2 analysis IR partitions ordinary vs symbolic
parameters using `member.final`; the structural qualifier is not respected by
that partition. This matches the upstream issue's analysis of the dropped
variability field.

**Reproduction without touching another worker's source:** copy DrivelineSciML
into a task-local directory, activate that copy with the rc2 runtime, regenerate
with `.toolchain/compiler-build/dyad compile <copy>`, and do not run the demo's
codegen-fix script. The recorded copy is
`.task/workflows/annotation/DrivelineSciML`. The exact argv is in
`.task/workflows/jobs-annotation.json`; unpatched failure output is retained in
`annotation-3.5.0-rc2.log`.

```julia
using DyadInterface, ModelingToolkit, DyadData
include(joinpath(copy_root, "src/DrivelineSciML.jl"))
DrivelineSciML.DrivelineStage1CalibrationAnalysis__System(; name=:repro)
```

**Old/new distinction:** the original 3.4 generated
`DrivelineStage1CalibrationAnalysisSpec()` constructs successfully (2.621428 s),
including its concrete `DyadTimeseries` and model. The new generated system
fails in 0.242543 s. Old generated code stores `data` as an ordinary Julia spec
field; it does not create this symbolic parameter. This comparison checks
construction only; it makes no claim that a baseline calibration converges.

**Task-local diagnostic:** replacing only the generated annotation with
`data::typeof(__local__data)` allows construction in 3.097058 s. That diagnostic
supports the UnionAll failure diagnosis, but it does not repair the compiler's
structural/non-symbolic contract. No upstream source or concurrent SciML project
was modified by this worker. Both original failure and diagnostic logs remain.

**Expected fix/test:** preserve structural variability through inherited analysis
properties/IR; do not emit symbolic declarations or initial-condition entries
for structural data. Include an inherited structural UnionAll data member and a
plain structural scalar in compiler/runtime regression coverage. Do not mask
failed optimizer statuses when verifying the eventual calibration.

## New draft: generated behavior examples create self-referential bindings

**Suggested target/title:** dyad-lang constructor/docs generation — rc2 generated
`full_equations` examples fail with cyclic parameter bindings.

The docs generator emits external symbolic variables having the same names as
the component parameters and passes them back to the generated constructor:

```julia
using FIRFilterComponents, ModelingToolkit
@variables T_inf T0 h A m c_p
@named sys = FIRFilterComponents.Hello(
    T_inf=T_inf, T0=T0, h=h, A=A, m=m, c_p=c_p)
full_equations(sys)
```

This is the verbatim behavior block from
`docs/src/components/Hello.md` after rc2 `dyad document FIRFilterComponents`.
On 3.5 it throws:

```text
The bindings for parameters were found to have at least one cycle
involving the follow parameters:
T_inf
```

The stack enters `ModelingToolkitBase.ParameterBindingsGraph`, `get_ir_info`,
and `full_equations`. The rc2 constructor declares the new symbolic parameter
and calls `__dyad_seed_parameter!` with the externally supplied same-name symbol;
that generated handoff produces the cyclic binding. Ownership between constructor
seeding and documentation symbol generation needs upstream investigation. The
numerical `Hello` analysis at its physical defaults remains successful.

**Old/new distinction:** the same block against the preserved original 3.4 FIR
model returns
`Differential(t,1)(T(t))*c_p*m ~ A*(-T(t)+T_inf)*h` (1.038771 s). The rc2 block
fails (0.427529 s). Use `.task/workflows/behavior.jl` with
`--project=.task/flight-baseline/FIRFilterComponents +dyad-3.4.0` and then
`--project=DyadDemos/FIRFilterComponents +dyad-3.5.0-rc2`; exact correctly ordered
argv is in `jobs-issues.json`.

The same new-cycle failure occurs in generated behavior blocks for:

| Project | Component | First cycle parameter | Original 3.4 block |
|---|---|---|---|
| HybridTransmission | ECMSController | `s_base` | passes |
| HybridTransmission | HybridBattery | `V_nom` | passes |
| PassiveSuspension | ISO8608RoadC | `v` | passes |
| SatelliteGNC | AttitudeController | `Kp_x` | passes |
| SatelliteGNC | LuenbergerObserver | `Ixx` | passes |
| SatelliteGNC | ReactionJet | `rx` | passes |
| SatelliteGNC | SatelliteBody | `Ixx` | passes (review follow-up) |
| SatelliteGNC | SatelliteBody6DOF | `Ixx` | passes (review follow-up) |
| SatelliteGNC | ThrusterAllocator | `F_max` | passes (review follow-up) |
| SatelliteGNC | TrapezoidalProfile | `target_angle` | passes (review follow-up) |
| HL20Demo | shared.HL20Aero | `DLG` | fails earlier on missing `ChallengeComponent` |
| MakieWebinar | Hello | `T_inf` | passes (0.289241 s in-block) |

SatelliteGNC has seven failed generated blocks, rather than the three initially
listed. The remaining four exact emitted blocks pass against the original 3.4
sources in 5.078403 s (exit 0), without catching errors. See
[SatelliteGNC validation](SatelliteGNC/docs/followup-validation.md#generated-documentation)
for the retained harness and logs. This extends the symbolic old/new comparison;
it does not establish a successful complete old documentation build.

No successful original HL20 construction is claimed. Its new cycle is the same
mechanism independently isolated by FIR, while its standalone helper bug had
already been fixed during the upgrade.

**Expected behavior:** generated documentation should execute with the generated
constructors and display meaningful equations. Regression coverage should run
`dyad document`, execute the emitted behavior blocks, and render a site with
example errors fatal. The current compiler template includes `:example_block`
in `warnonly`, so a process exit of zero does not establish working examples.
The audit removed that warning downgrade in task copies and observed the
reported failures. No behavior block or model was deleted to get a green build.

## Draft: inline SVG makes an otherwise executable generated site fail HTML limits

**Suggested target/title:** dyad-lang documentation renderer — large embedded
component SVG exceeds Documenter's default HTML size threshold.

`dyad document FrictionBrakeDemo` embeds the 731703-byte asset
`FrictionBrakeDemo/assets/brake_caliper.svg` in
`docs/src/components/FrictionBrake.md`. The resulting page is 744.67 KiB and
Documenter 1.19.0 rejects it with `HTMLSizeThresholdError` at its default 200 KiB
limit. Every generated example in this project completed before HTML rendering
failed. The compiler's source documentation page contains 749725 bytes; its
rendered HTML has 762540 bytes.

A minimal page containing only that generated SVG also fails under the 3.4
runtime (722.04 KiB, 40.616872 s process time). This is not evidence of an
upgrade-specific numerical defect. It is a documentation integration limit
that also affects the old runtime with the same SVG content. An independent
3.4 compiler documentation-generation run was not performed. The original icon
asset/model was preserved.

**Self-contained reproduction from this checkout:** the committed
[`reproduce_inline_svg.jl`](FrictionBrakeDemo/docs/reproduce_inline_svg.jl) reads
`FrictionBrakeDemo/assets/brake_caliper.svg` directly, creates a temporary
Documenter site with one raw-HTML SVG block, and calls `makedocs` with the default
`Documenter.HTML()` limits. It requires only Documenter and the checked-in asset;
no compiler, model, generated docs or task-local harness is needed.

```sh
julia --project=FrictionBrakeDemo/docs -e 'using Pkg; Pkg.instantiate()'
julia --project=FrictionBrakeDemo/docs FrictionBrakeDemo/docs/reproduce_inline_svg.jl
```

Expected result: a nonzero exit with `HTMLSizeThresholdError` for `index.html`,
above the default 200 KiB threshold. The temporary fixture path and exact asset
size are printed. For a standalone Julia environment independent of the Dyad
project, install Documenter 1.19.0 in a task-local environment and run the same
script with that environment. The earlier 3.4 fixture used the generated SVG
content (`jobs-svg-baseline.json`); it did not run the old compiler. The full rc2
generated-site build failed after 102.219274 s.

The committed source-asset fixture was also run on both runtimes with Documenter
1.19.0: rc2 exits 1 with `HTMLSizeThresholdError` (720.27 KiB, 5.577645 s), as does
3.4 (720.28 KiB, 4.274072 s). This minimal source-asset page differs from the
earlier generated-content fixture; both exceed the unchanged 200 KiB limit.
See [the review rerun](followup-workflows.md#review-follow-up-notebook-gates) for
commands and logs. No complete old generated site is claimed.

**Expected direction:** retain the icon but emit large SVG assets as external
files/references, or compact SVG without changing the visible icon. Do not raise
or disable HTML size limits merely to classify the build as passing.

## Optional rendering diagnostics: observations, no new issue filed

GLMakie 0.13.16 fails direct import on both runtimes because the worker has no
DISPLAY (`GLFWError(65550, "X11: The DISPLAY environment variable is missing")`).
This is expected environment behavior, not a rendering-library bug report.

Earlier SciML test logs include a different diagnostic:
`Cannot load module Makie into module Render ... package Render does not have
Makie in its dependencies`, at bundled `MultibodyComponents/ext/Render.jl:2`.
That dependency/extension diagnostic is distinct from absent DISPLAY.
MultibodyComponents 0.3.0 declares Makie as a weak dependency and
`Render = ["Makie"]`, so simply adding an unrelated display server would not
explain that dependency error.

A fresh rc2 probe in `MakieWebinar/scripts` performed:

```julia
using MultibodyComponents, Makie
@show pkgversion(MultibodyComponents) pkgversion(Makie)
@show Base.get_extension(MultibodyComponents, :Render)
Base.retry_load_extensions()
```

It completed in 4.986513 s, with versions 0.3.0/0.24.16 and extension `Render`.
The earlier dependency diagnostic was not reproduced. The 3.4 distribution
returns `nothing` from `Base.identify_package("MultibodyComponents")`, so no old
extension comparison is possible. A future upstream report should attach the
failing `Pkg.test` sandbox's manifest/load-path and precompile context, plus a
reproduction of that exact dependency error; the successful explicit-import
probe does not validate GUI rendering or dismiss the earlier log.

The initial multi-environment `--compiled-modules=no` documentation probe also
encountered a Julia world-age `ComputePipeline` import error in CairoMakie.
Fresh-process imports and the final Cairo SVG export succeeded. That abandoned
shared-session diagnostic is not counted as a persistent demo failure.

MakieWebinar generated docs were initially blocked by an HTTP 403 when
fetching DyadDAQP_jll 0.10.3 from
`https://github.com/JuliaComputing/DyadDAQP_jll.jl/releases/download/DyadDAQP-v0.10.3+0/DyadDAQP.v0.10.3.x86_64-linux-gnu.tar.gz`.
That attempt was an artifact-access limitation; it was not a missing-DISPLAY or
numerical analysis defect. The handwritten Cairo examples and SVG export passed.

The task's subsequent `github.com` access grant was followed by an unchanged
document-generation retry. It failed after 13.352420 s (exit 1) with the same
HTTP 403 CONNECT-tunnel error at the exact DyadDAQP release URL above. This
was still an access limitation at that point, with generation and HTML execution unvalidated;
it supplies no additional evidence of a compiler/library regression. The retry
log is `.task/workflows/document-MakieWebinar-access-retry.log`.

### Release-assets grant resolved artifact access

With subsequent task access to `release-assets.githubusercontent.com`, unchanged
MakieWebinar documentation generation passed in **24.378873 s** (exit **0**).
The strict-example build then failed in **73.975772 s** (exit **1**) on its
emitted Hello block with the same `T_inf` cycle described in the constructor/docs
draft above. This supersedes the earlier access blockage. The generated
`warnonly` downgrade for `:example_block` was removed only in the task copy;
Documenter terminates before HTML rendering and no successful site is claimed.

For this newly exposed failure, all twelve generated component behavior blocks
were independently executed against the preserved original 3.4 model and rc2.
All twelve pass on 3.4 (**6.627891 s** process time); eleven pass on rc2 and Hello
fails (**6.929902 s** process time). Hello itself passes in **0.289241 s** on 3.4
and fails in **0.212930 s** on rc2. This confirms an upgrade regression in
symbolic example construction rather than a GUI prerequisite or failed
numerical analysis. The original model is preserved. No new issue was filed.
Exact commands, old/new logs and limits are linked from the
[workflow report](followup-workflows.md#release-assets-access-retry-generation-completed-example-regression-exposed).
