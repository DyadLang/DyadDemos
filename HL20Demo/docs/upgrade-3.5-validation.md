# Dyad 3.5 upgrade validation

Validated with Dyad 3.5.0-rc2 (Julia 1.13.2-dyad), 2026-10-26. Generated Julia comes from the `v3.5.0-rc2` compiler (a24a224), using its compiler-only CLI build. Package manifests were instantiated and remain ignored.

## Migration and research

Pinned DyadInterface 7.5.1, DyadEcosystemDependencies 0.11.20 and Julia 1.13.2. Updated the editor channel and notebook Orchestrator fallback (0.15.0). Read the [DyadInterface changelog](https://github.com/JuliaComputing/DyadInterface.jl/blob/v7.5.1/CHANGELOG.md), including the new analysis system handoff and setup adaptor contract.

The checked-in aerodynamic core referenced an absent `ChallengeComponent` module, and its table helpers were never included. It now calls `HL20Demo` helpers, which load before generated code, and declares their EzXML, Interpolations and Symbolics dependencies. Aerodynamic equations, tables and helper formulas are unchanged. The existing project icon is associated with the core.

## Results

`Pkg.test(; allow_reresolve=false)` passed: 20 assertions cover atmospheric tables, table-index aliases, invalid table names, finite polynomial values at four angles, and construction of `HL20Demo.shared.HL20Aero`.

There are **zero declared analyses** in the checked-in project. The five full-flight analyses described in `assets/shared/hl20_spec.md` are instructions for a future agent-generated simulation; they are not implemented in this checkout and were not run. No training is defined or run.

The original generated test suites contained zero assertions. The old core could not construct in this standalone package because `ChallengeComponent` was undefined. Consequently there is no runnable old full-flight baseline or trajectory comparison to claim.

Initial tests logged a DyadDataCSVExt extension precompile error when CSV was loaded by the generated test harness. Declaring DyadData directly resolved it; the post-review package test rerun passed without that diagnostic.

## Reproduction

```sh
julia +dyad-3.5.0-rc2 --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test(;allow_reresolve=false)'
julia +dyad-3.5.0-rc2 --project=. test/validate_upgrade.jl results.toml
```

`validate_upgrade.jl` discovers declared analyses and produces an empty analysis inventory for this project. Run from the project directory. Use `JULIA_NUM_THREADS=2`, `JULIA_NUM_PRECOMPILE_TASKS=1` and `JULIA_PKG_PRECOMPILE_AUTO=0` for the validation resource limits.
