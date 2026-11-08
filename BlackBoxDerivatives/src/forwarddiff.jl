# ForwardDiff: Dual-number methods. F, Fx and Fy all get them, so Duals of Duals (Hessians) work.
using ForwardDiff: Dual, value, partials

for (f, fx, fy) in ((:F, :Fx, :Fy), (:Fx, :Fxx, :Fxy), (:Fy, :Fxy, :Fyy))  # (f, ∂f/∂x, ∂f/∂y)
    @eval function $f(x::Dual{T}, y::Dual{T}) where {T}
        a, b = value(x), value(y)
        return Dual{T}($f(a, b), $fx(a, b) * partials(x) + $fy(a, b) * partials(y))
    end
    @eval $f(x::Dual{T}, y::Float64) where {T} = Dual{T}($f(value(x), y), $fx(value(x), y) * partials(x))
    @eval $f(x::Float64, y::Dual{T}) where {T} = Dual{T}($f(x, value(y)), $fy(x, value(y)) * partials(y))
    @eval $f(x::Dual, y::Dual) = $f(promote(x, y)...)  # different tags (nested derivatives)
end
