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

Project workers are running the analyses and comparing the old/new outputs.
The completed results are recorded below after all project runs finish.
