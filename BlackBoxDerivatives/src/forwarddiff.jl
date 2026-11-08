# ForwardDiff: Dual-number methods. F, Fx and Fy all get them, so Duals of Duals (Hessians) work.
using ForwardDiff: Dual, value, partials

for (f, fx, fy) in PARTIALS
    @eval function $f(x::Dual{T}, y::Dual{T}) where {T}
        a, b = value(x), value(y)
        return Dual{T}($f(a, b), $fx(a, b) * partials(x) + $fy(a, b) * partials(y))
    end
    @eval $f(x::Dual{T}, y::Float64) where {T} = Dual{T}($f(value(x), y), $fx(value(x), y) * partials(x))
    @eval $f(x::Float64, y::Dual{T}) where {T} = Dual{T}($f(x, value(y)), $fy(x, value(y)) * partials(y))
end
