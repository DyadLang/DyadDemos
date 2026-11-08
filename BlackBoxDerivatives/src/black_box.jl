# The black box: a tire force F(slip, load) and its partial derivatives, as a closed library
# would ship them. Float64 in, Float64 out, and every value leaves through raw bytes (as from a
# file or a C library), so no AD tool can look inside.
#
# Don't "fix" AD by adding `F(x::Real, y::Real)` that strips its arguments down to Float64
# (e.g. with `ForwardDiff.value`): it runs, and silently returns zero derivatives.

q(x) = 1.3 * atan(6x)
dq(x) = 7.8 / (1 + 36x^2)
ddq(x) = -561.6x / (1 + 36x^2)^2
"The plain formula, for checking only: every AD tool can trace this one."
tire(x, y) = y^0.8 * sin(q(x))

F(x::Float64, y::Float64) = through_bytes(tire(x, y))
Fx(x::Float64, y::Float64) = through_bytes(y^0.8 * cos(q(x)) * dq(x))
Fy(x::Float64, y::Float64) = through_bytes(0.8y^-0.2 * sin(q(x)))
Fxx(x::Float64, y::Float64) = through_bytes(y^0.8 * (cos(q(x)) * ddq(x) - sin(q(x)) * dq(x)^2))
Fxy(x::Float64, y::Float64) = through_bytes(0.8y^-0.2 * cos(q(x)) * dq(x))
Fyy(x::Float64, y::Float64) = through_bytes(-0.16y^-1.2 * sin(q(x)))

# (f, ∂f/∂x, ∂f/∂y): every rule file loops over this table.
const PARTIALS = ((:F, :Fx, :Fy), (:Fx, :Fxx, :Fxy), (:Fy, :Fxy, :Fyy))

const CALLS = Ref(0)  # black-box evaluations, to compare costs
through_bytes(v::Float64) = (CALLS[] += 1; io = IOBuffer(); write(io, v); read(seekstart(io), Float64))
"Run `f()`; return its named tuple plus the number of black-box calls it made."
counted(f) = (CALLS[] = 0; r = f(); (; r..., calls = CALLS[]))
