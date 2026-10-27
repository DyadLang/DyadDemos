# Stage 3. The JLL owns runtime loading; no loader-path environment is needed.
using TireModel_jll
p = Ref((10.0, 1.3, 1.0, 0.97))
fy = @ccall TireModel_jll.libtiremodel.tm_mf_fy(0.05::Cdouble, 4000.0::Cdouble,
    p::Ref{NTuple{4, Cdouble}})::Cdouble
println("local JLL: Fy = $fy N")
