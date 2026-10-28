# C library integration

A small tire library, called from Julia and used by two Dyad sliding-axle
models. Read the six stages in order. The C model is a teaching stand-in,
not a validated tire model. Requires Dyad **3.5.0-rc2**, Julia **1.13.2**,
a C compiler and `make`.

Run commands from this directory. Start with:

```sh
julia +dyad-3.5.0-rc2 --project -e 'using Pkg; Pkg.instantiate()'
```

## 1. Write and build the C API

[`csrc/tiremodel.h`](csrc/tiremodel.h) is the contract; the implementation is
MIT licensed. `tm_mf_fy` evaluates the Magic Formula; `tm_mf_dfy_dalpha`
provides its analytic slope. Slip is in radians, load and force in newtons;
`D` is a friction coefficient, so peak force scales with `D * Fz`.
The opaque `tm_tire` also holds lagged slip, time and force.

```sh
make -C csrc
```

The result is `csrc/build/libtiremodel.so` (`.dylib` on macOS).
No binaries are committed.
[`scripts/build.jl`](scripts/build.jl) also installs it for the local JLL.

## 2. Load a system library

[`scripts/a_system_library.jl`](scripts/a_system_library.jl) first uses
`@ccall "libtiremodel".tm_mf_fy(...)`, then repeats the call through
`Libdl.find_library`, `dlopen` and `dlsym`.

```sh
LD_LIBRARY_PATH="$PWD/csrc/build" julia +dyad-3.5.0-rc2 --project scripts/a_system_library.jl
```

Set the loader path **before Julia starts** (`DYLD_LIBRARY_PATH` on macOS).
Match the C ABI exactly: our 4-tuple of `Cdouble` has the same layout as
the C parameter struct.
A package must acquire `dlopen` handles/function pointers in `__init__`,
never cache live pointers during precompilation. Stage 3 does that for us.

## 3. Load through a local JLL

[`TireModel_jll/`](TireModel_jll/) is a JLLWrappers package, selected through
the main project's `[sources]` path. It builds into its development
`override/lib/` directory before loading, including on a fresh clone.
Its `__init__` opens the library; Julia wrappers call the library product.

```sh
julia +dyad-3.5.0-rc2 --project scripts/b_local_jll.jl
```

JLLWrappers 1.8 needs `Artifacts.toml` to select a wrapper even
with an override directory. This local package uses a lazy entry for the
empty artifact tree; the actual library always comes from the source build.
Real JLLs ship one wrapper per platform triplet; this one builds locally
for the host.
A different installed binary can be selected in **LocalPreferences.toml**:

```toml
[TireModel_jll]
libtiremodel_path = "/absolute/path/to/libtiremodel.so"
```

Restart Julia after changing it. A published JLL packages platform binaries
as artifacts and handles their dependency paths. BinaryBuilder/Yggdrasil is
the next step, outside this example.

## 4. Make a stateless C call usable by Julia solvers

Read [`src/4_stateless.jl`](src/4_stateless.jl). Three pieces serve different
purposes:

| Piece | Why it exists | Without it |
|---|---|---|
| `@register_symbolic` | Keep the C call opaque when building equations | `Float64(::Num)` fails |
| `@register_derivative` | Supply the C slope to the symbolic Jacobian | An unknown derivative remains; strict expansion raises `DerivativeNotDefinedError` |
| `ForwardDiff.Dual` method | Carry the C slope through numerical solver AD | `Float64(::ForwardDiff.Dual)` fails |

Only slip varies in this demo. Load and coefficients are fixed parameters;
parameter sensitivities and higher derivatives need additional rules.

## 5. Own and step a clocked handle

Read [`src/5_stateful.jl`](src/5_stateful.jl). Dyad connects a `Sampler`,
a clocked `RelaxationTire` and a `ZeroOrderHold`; the tire owns `Clock(dt)`
with a default period of 5 ms. Compile the clocked model with:

```julia
mtkcompile(model; additional_passes=[SynchToolkit.compile_lustre])
```

One registered tick function reads `Fy`, then advances the C lag with the
sampled inputs over `[t, t+dt]`. Output-then-update preserves the force at
the current communication point; updating first would expose next-step state.
Clock affects run only at accepted solver steps, so rejected trials and AD
probes never advance C. The continuous RHS reads only the held force.

An `InitClock` equation frees and recreates the C session before the first
tick, including after `remake` or `reinit!`. A finalize-only hook frees it
after the solve; a Julia finalizer is the backstop. Problems built from one
compiled system share the synchronous runtime; run them sequentially
([shared runtime](https://github.com/JuliaComputing/SynchToolkit.jl/issues/265)).

Use `t` for timestamps: `SampleTime()` is the period.
An aligned final time does not tick.
Use zero-start sessions: fresh nonzero starts can miss the initial tick
([clock start timing](https://github.com/SciML/ModelingToolkit.jl/issues/5334)).

Stage 5 is 73 lines versus 83 in PR #43. Output-then-update removes the
cached previous inputs; both versions keep C ownership, snapshot calls
and finalization.

## 6. Use the wrappers from Dyad

[`dyad/`](dyad/) contains the two tires, two sliding axles and two analyses.
Both axles use `alpha = delta - atan(vy/U)` and `m * der(vy) = Fy`.
`MagicFormulaTire` calls the registered function. `RelaxationTire` is an
external component implemented by stage 5.

```sh
dyad compile .
julia +dyad-3.5.0-rc2 --project -e 'using Pkg; Pkg.test()'
dyad document CLibraryIntegration
```

The tests compare with pure Julia force/derivative and simulation references,
check implicit-solver AD, discrete stepping and its first-order continuous
limit, and exercise loading, preferences, snapshots and handle cleanup.
