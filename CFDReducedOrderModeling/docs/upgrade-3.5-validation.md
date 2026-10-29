# Dyad 3.5 migration and validation

This demo now uses the `dyad-3.5.0` distribution (Julia 1.13.2), kernel 3.5.0,
BlockComponents 5, DyadData 2.3, and DyadInterface 7.5.1, matching the repository's
3.5 stack. The distribution also provides CSV 1.1, HTTP 2.9, JSON 1.10, and
Optim 2.3; compatibility bounds now permit those versions. Unused dependencies
on the old control, optimizer, discovery, thermal, and plotting libraries were
removed. The custom ROM construction algorithms and shipped fit coefficients
are preserved. The repository's test-only ecosystem dependency is retained,
and Plots is a test dependency because the 3.5 compiler's generated test helper
imports it even when no snapshot plots are requested. OptimizationBase is
also explicit in the test environment: without that declaration, Julia cannot
resolve the MLDataDevices weak dependency when precompiling its bundled
OptimizationMLDataDevicesExt as Lux is loaded.

The repository targets CLI 3.5.1, but that release was unavailable on 2026-10-29.
Validation uses the published **3.5.0 (483d92b)** Linux CLI. Its release asset was
checked against `SHA256SUMS.txt`. This is not a 3.5.1 compiler validation.

The visible thermal/ROM/source components now have SVG icons and connector
placements. The demo has a gallery icon and a root README entry. Generated
Julia files are regenerated with the released compiler.

Runner specifications are immutable, and their default input paths resolve
relative to the installed package rather than the process working directory.
Unknown artifact errors now list the available symbol names. The dashboard
imports its solver explicitly and only starts its server when run as a script,
so its handlers can be tested directly.

## Independent-review corrections

Zone ordering now sorts mode-1 cluster centroids by decreasing absolute
magnitude. SVD column signs are arbitrary; sorting signed centroids could
reverse the network and move heat input and coolant loss to the wrong spatial
ends. Regressions cover all four sign combinations of two synthetic modes with
interleaved spatial indices, plus a dominant-mode sign flip on the bundled CFD
data. The CFD check also verifies that spatial point 1 remains in the first
(heated) zone and point 20 in the last (coolant) zone.

The neural analysis now returns the trained model at the selected knee
dimension. Previously `best_k`, the artifacts, and the SVD zone-count phase used
the knee, but the returned parameters, networks, and states came from the
minimum-error dimension. Keeping the knee model preserves the documented
`best_k` API and makes all returned fields agree. A short `[1, 2]` sweep checks
the case where dimension 1 has lower error while dimension 2 is selected. Its
returned parameters match an independently trained dimension-2 model; encoder,
dynamics, decoder, and artifact checks verify the exposed dimensions.

## Reproduction

Use a task-local Juliaup installation and writable depot, with existing private
JuliaHub credentials available. Do not modify a shared Juliaup installation.

```sh
export JULIAUP_DEPOT_PATH="$PWD/.toolchain/juliaup"
export JULIAUP_SERVER=https://juliahub.com/juliabin
export JULIA_DEPOT_PATH="$PWD/.toolchain/depot:"
juliaup add dyad-3.5.0

# From CFDReducedOrderModeling, with the verified 3.5.0 CLI on PATH:
julia +dyad-3.5.0 --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate()'
dyad compile .
julia +dyad-3.5.0 --startup-file=no --project=. -e 'using CFDReducedOrderModeling'
julia +dyad-3.5.0 --startup-file=no --project=. -e 'using Pkg; Pkg.test()'
```

The trailing colon in `JULIA_DEPOT_PATH` retains the distribution's bundled
system depots and artifacts. The verification environment used an equivalent
explicit depot list with the writable task depot first and the extracted
distribution's `local/share/julia` and `share/julia` depots next. Its runtime
was extracted from the distribution archive and registered with task-local
`juliaup link dyad-3.5.0 /path/to/distribution/bin/julia` after a single-stream
download failed. Existing private credentials expired during setup, but
instantiation completed using bundled packages and cached registries. No new
private access was required.

The review corrections were validated by sourcing the existing
`.task-tools/env.sh` in the PR worktree and reusing its cached distribution,
CLI, and depot. No distribution was downloaded again and no authentication
workaround was used. From that worktree:

```sh
source .task-tools/env.sh
"$DYAD_CLI_PATH" compile CFDReducedOrderModeling
julia +dyad-3.5.0 --startup-file=no --project=CFDReducedOrderModeling -e 'using CFDReducedOrderModeling'
julia +dyad-3.5.0 --startup-file=no --project=CFDReducedOrderModeling -e 'using Pkg; Pkg.offline(true); Pkg.test()'
```

## Coverage and limits

The tests exercise all five declared transient analyses. The two 20-node truth
model analyses are compared with all 20 node columns of the committed CFD CSVs
at 1000 sample times. ROM tests check successful solves, finite temperatures,
zero initial deviations, and positive heated final states.

The POD construction pipeline runs on the bundled training data and checks
stable dynamics and fit errors below 1 K. Both thermal-network construction
pipelines run with 10 calibration iterations; the neural pipeline uses one
training epoch, one seed, narrow hidden layers, and two shooting windows, with
both a dimension-2 reference run and a `[1, 2]` sweep. These are execution and
consistency checks, not convergence or full training validation. The default
training budgets and committed fits are retained.

Tests also check network/POD JSON round trips and analysis artifacts, then
call the dashboard training and all three validation handlers without opening
a listening socket. Browser rendering, the interactive notebook, and the full
default neural training sweep are outside this validation.

## Results (2026-10-29)

- Dyad CLI `3.5.0 (483d92b)` compiled the project successfully. A second
  compilation skipped every generated file as byte identical, as did the
  compilation after the review corrections.
- `using CFDReducedOrderModeling` succeeded on Julia 1.13.2 for Dyad.
- `Pkg.test()` completed successfully after the review corrections:
  **119 assertions**, up from 103 (51 transients, 13 data/persistence,
  7 SVD zone orientation, 29 construction/artifacts, 19 dashboard handlers).
  The successful invocation after instantiation was:
  `julia +dyad-3.5.0 --startup-file=no --project=. -e 'using Pkg; Pkg.offline(true); Pkg.test()'`.
  Offline resolution reused the instantiated packages and cached registries.
  The test setup still emitted JuliaHub-token refresh HTTP 500 warnings and
  a registry HTTP 401 warning, but required no new private downloads and
  completed. The earlier optional
  OptimizationMLDataDevicesExt error was resolved by the explicit test dependency.
- Maximum sampled absolute differences from the committed truth-model CSVs:
  training **0.0122855471 K**, validation **0.00102721402 K**. Both comparisons
  cover all 20 nodes at the 1000 original sample times. The numerical
  minimum-temperature check allows 0.001 K of integration noise around 300 K,
  consistent with the shipped relative tolerance of `1e-6`.
- Dashboard validation RMS errors on the held-out ramp: SVD network
  **0.1715 K**, neural network **0.1689 K**, POD/DMDc **0.1233 K**.

These are sampled comparisons with the committed data, not continuous error
bounds or a rerun of the original Dyad 2.3 environment. Compiler-generated files
retain the compiler's own whitespace; authored files pass whitespace checks.
