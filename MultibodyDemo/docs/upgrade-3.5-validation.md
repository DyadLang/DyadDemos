# Dyad 3.5 migration validation

The demo targets the repository's Dyad 3.5 stack: JuliaHub distribution
`dyad-3.5.0` (Julia 1.13.2), DyadInterface 7.5.1,
MultibodyComponents 0.3.0, and the version 5/3 component libraries.
The repository targets CLI 3.5.1, but that release was unavailable at
validation time. The stable CLI used here is **3.5.0 (483d92b)**, downloaded
from the `v3.5.0` release and verified against its `SHA256SUMS.txt`.

## Changes

- Merge current main, retaining every main demo row and adding MultibodyDemo.
- Update the project and editor distribution pins, component compatibility
  bounds, and ecosystem dependency to the 3.5 stack.
- Mark the pendulum as a top-level example, add its diagram placements and
  simulation test, and explicitly qualify the built-in transient analysis.
- Regenerate Julia code with the stable 3.5 compiler.
- Exercise every declared analysis, with numerical checks for pendulum geometry,
  damped spring motion, bounded robot tilt, and vehicle movement.

All four local components are top-level examples. Their constituent components
use icons supplied by the component libraries; there are no local reusable
components requiring additional icons. The demo's `assets/icon.svg` is retained.

## Reproduction

With `dyad-3.5.0` and a Dyad 3.5 compiler on PATH, from `MultibodyDemo/`:

```sh
julia +dyad-3.5.0 --project=. -e 'using Pkg; Pkg.instantiate()'
dyad compile .
julia +dyad-3.5.0 --startup-file=no --compiled-modules=no --project=. -e 'using MultibodyDemo'
GKSwstype=100 julia +dyad-3.5.0 --startup-file=no --compiled-modules=no --project=. \
  -e 'using Pkg; Pkg.test(;julia_args=["--startup-file=no", "--compiled-modules=no"])'
```

Private JuliaHub dependencies require credentials. Validation uses task-local
Julia/depot/toolchain directories and reuses existing credentials without
changing the host juliaup configuration. The load and test checks disable package
precompilation with `--compiled-modules=no` to avoid the lengthy optional
extension precompile. The ordinary precompiled package load was interrupted
during that precompilation; it was not validated to completion.

## Results

Validated on 2026-10-29:

- Dependency resolution and instantiation: passed.
- Dyad CLI compilation: passed; generated files are unmodified compiler output.
- Package load: passed on Julia 1.13.2 with MultibodyComponents 0.3.0 and
  DyadInterface 7.5.1, using `--compiled-modules=no`.
- `Pkg.test`: **31/31 assertions passed**, comprising three generated simulation
  tests (74.5 s) and 28 numerical assertions for the declared analyses (10.2 s).

| Declared analysis | Stop time | Solver result | Additional checks |
|---|---:|---|---|
| `PendulumTransient` | 3 s | `Success` | Horizontal initial angle, swinging motion, fixed 1 m radius. |
| `SpringDamperSystemTestAnalysis` | 10 s | `Success` | Initial position and damped settling to the static spring deflection. |
| `DyadBalans2DAnalysis` | 10 s | `Success` | Initial tilt and bounded tilt during controlled motion. |
| `TwoTrackModelTestAnalysis` | 10 s | `Success` | Initial position and nonzero vehicle displacement. |

Every analysis also checks both time endpoints and finite state values. The
original robot and car generated tests retain their longer 50 s and 20 s
runs; the pendulum adds a 3 s generated test.

Registry refresh emitted expired-token/401 warnings after token renewal returned
HTTP 500. Instantiation and tests completed using the available registry cache,
bundled distribution packages/artifacts, and existing package cache. A fresh
online private-registry authentication was not verified.

The compiler emits trailing spaces on eight generated blank lines. These are
retained to preserve exact compiler output; the handwritten changes pass
`git diff --check` when generated files are excluded.

Interactive GLMakie windows, notebook interaction, and video rendering are
outside the headless numerical validation.
