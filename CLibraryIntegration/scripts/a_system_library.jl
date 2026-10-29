# Stage 2. Start Julia with LD_LIBRARY_PATH=csrc/build (DYLD_LIBRARY_PATH on macOS).
using Libdl
p = Ref((10.0, 1.3, 1.0, 0.97))
fy = @ccall "libtiremodel".tm_mf_fy(0.05::Cdouble, 4000.0::Cdouble,
    p::Ref{NTuple{4, Cdouble}})::Cdouble

path = Libdl.find_library(["libtiremodel"])
handle = Libdl.dlopen(path)
try
    f = Libdl.dlsym(handle, :tm_mf_fy)
    dynamic_fy = @ccall $f(0.05::Cdouble, 4000.0::Cdouble,
        p::Ref{NTuple{4, Cdouble}})::Cdouble
    @assert fy == dynamic_fy
    println("system library: Fy = $fy N")
finally
    Libdl.dlclose(handle)
end
