# Symbolics: `@register_derivative f(x, y) i ∂f` says "the derivative of f with respect to
# argument i is ∂f". Registering the partials' own partials gives second derivatives.
# Without these rules, Symbolics treats F's derivatives as zero.
Symbolics.@register_derivative F(x, y) 1 Fx(x, y)
Symbolics.@register_derivative F(x, y) 2 Fy(x, y)
Symbolics.@register_derivative Fx(x, y) 1 Fxx(x, y)
Symbolics.@register_derivative Fx(x, y) 2 Fxy(x, y)
Symbolics.@register_derivative Fy(x, y) 1 Fxy(x, y)
Symbolics.@register_derivative Fy(x, y) 2 Fyy(x, y)
