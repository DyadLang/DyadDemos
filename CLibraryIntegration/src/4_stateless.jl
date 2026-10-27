# Stage 4: an opaque symbolic operation, with two distinct derivative bridges.
struct MFParams
    B::Cdouble
    C::Cdouble
    D::Cdouble
    E::Cdouble
end

function mf_fy(alpha::Real, Fz::Real, B::Real, C::Real, D::Real, E::Real)
    p = Ref(MFParams(B, C, D, E))
    @ccall libtiremodel.tm_mf_fy(alpha::Cdouble, Fz::Cdouble, p::Ref{MFParams})::Cdouble
end
function mf_dfy_dalpha(alpha::Real, Fz::Real, B::Real, C::Real, D::Real, E::Real)
    p = Ref(MFParams(B, C, D, E))
    @ccall libtiremodel.tm_mf_dfy_dalpha(alpha::Cdouble, Fz::Cdouble, p::Ref{MFParams})::Cdouble
end

# Registration prevents Symbolics from tracing through the foreign call.
@register_symbolic mf_fy(alpha, Fz, B, C, D, E)
@register_symbolic mf_dfy_dalpha(alpha, Fz, B, C, D, E)
Symbolics.@register_derivative mf_fy(alpha, Fz, B, C, D, E) 1 mf_dfy_dalpha(alpha, Fz, B, C, D, E)

# Solver AD is numerical, independent of symbolic differentiation. Only alpha
# varies here: Fz and the four coefficients are fixed model parameters.
function mf_fy(alpha::ForwardDiff.Dual{T}, Fz::Real, B::Real, C::Real, D::Real, E::Real) where {T}
    a = ForwardDiff.value(alpha)
    value = mf_fy(a, Fz, B, C, D, E)
    slope = mf_dfy_dalpha(a, Fz, B, C, D, E)
    ForwardDiff.Dual{T}(value, slope * ForwardDiff.partials(alpha))
end

# Used for initialization and independent reference simulations, never by case 1.
function julia_mf(alpha, Fz, B=10.0, C=1.3, D=1.0, E=0.97)
    x = B * alpha
    D * Fz * sin(C * atan(x - E * (x - atan(x))))
end
