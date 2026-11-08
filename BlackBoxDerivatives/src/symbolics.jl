# Symbolics (always loaded: the Dyad model needs F registered). `@register_derivative f(x, y) i ∂f`
# says "the derivative of f with respect to argument i is ∂f"; registering the partials' own
# partials gives second derivatives.
for f in (:F, :Fx, :Fy, :Fxx, :Fxy, :Fyy)
    @eval @register_symbolic $f(x, y)
end
for (f, fx, fy) in PARTIALS
    @eval Symbolics.@register_derivative $f(x, y) 1 $fx(x, y)
    @eval Symbolics.@register_derivative $f(x, y) 2 $fy(x, y)
end
