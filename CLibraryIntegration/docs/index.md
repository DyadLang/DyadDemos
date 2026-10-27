# Integrating a C tire library

Follow the six stages in [the demo README](../README.md): C API, system
loading, local JLL, stateless derivatives, stateful callbacks, Dyad models.

The two analyses use the same sliding mass and steering input. One tire is
instantaneous; the other owns a relaxation state in C and communicates
through a held force every 5 ms.

```julia
using CLibraryIntegration
stateless = CLibraryIntegration.StatelessTransient()
stateful = CLibraryIntegration.StatefulTransient()
```

Use `Pkg.test()` to check against independent Julia references. The C API
and its parameters are defined in `csrc/tiremodel.h`.
