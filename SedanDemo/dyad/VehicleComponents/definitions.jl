using LinearAlgebra: dot, cross, I
using Symbolics: @register_symbolic

"""
    interp1(xs, ys, x)

Piecewise-linear interpolation of the table `(xs, ys)` at `x`, clamped to the
table's end values outside the grid. `xs` must be sorted ascending. Registered
symbolically so tables can be regular parameter vectors in equations.
"""
function interp1(xs, ys, x)
    n = length(xs)
    isnan(x) && return float(x) # propagate NaN probes instead of indexing out of bounds
    x <= xs[1] && return float(ys[1])
    x >= xs[n] && return float(ys[n])
    i = searchsortedlast(xs, x)
    x1, x2 = xs[i], xs[i + 1]
    y1, y2 = ys[i], ys[i + 1]
    return y1 + (y2 - y1) * (x - x1) / (x2 - x1)
end
@register_symbolic interp1(xs::AbstractVector, ys::AbstractVector, x::Real)

# The TMeasy functions below are ported from Project Chrono's ChTMeasyTire
# (BSD-3-Clause, Copyright (c) 2016, Project Chrono Development Team); see
# LICENSE-Chrono.txt at the root of this demo.

"""
    tmeasy_force(s, df0, sm, fm, ss, fs)

TMeasy tire characteristic: force magnitude as a function of the combined slip
`s`, parameterized by the initial slope `df0`, the maximum force `fm` at slip
`sm`, and the full-sliding force `fs` reached at slip `ss`. Piecewise: a
rational adhesion curve up to `sm`, two blended parabolas (or a cubic fallback)
between `sm` and `ss`, and the constant sliding force beyond `ss`. Registered
symbolically since it is only C1.
"""
function tmeasy_force(s, df0, sm, fm, ss, fs)
    df0loc = sm > 0 ? max(2 * fm / sm, df0) : zero(df0)
    if s > 0 && df0loc > 0
        if s > ss # full sliding
            return float(fs)
        elseif s < sm # adhesion
            p = df0loc * sm / fm - 2
            sn = s / sm
            dn = 1 + (sn + p) * sn
            return df0loc * sm * sn / dn
        else
            a = (fm / sm)^2 / (df0loc * sm)
            sstar = sm + (fm - fs) / (a * (ss - sm))
            if sstar <= ss # two parabolas
                if s <= sstar
                    return fm - a * (s - sm)^2
                else
                    b = a * (sstar - sm) / (ss - sstar)
                    return fs + b * (ss - s)^2
                end
            else # cubic fallback
                sn = (s - sm) / (ss - sm)
                return fm - (fm - fs) * sn^2 * (3 - 2 * sn)
            end
        end
    else
        return zero(float(fs))
    end
end
@register_symbolic tmeasy_force(s::Real, df0::Real, sm::Real, fm::Real, ss::Real, fs::Real)

"""
    tmeasy_alignment_lever(sy_abs, nto0, synto0, syntoE)

TMeasy aligning-torque pseudo lever (normalized by the contact patch length)
as a function of the magnitude of the lateral slip `sy_abs`. `nto0` is the
lever at zero slip, `synto0` the slip where the lever crosses zero, and
`syntoE` the slip where it returns to zero after the negative (counter-steer)
region. Registered symbolically since it is only piecewise smooth.
"""
function tmeasy_alignment_lever(sy_abs, nto0, synto0, syntoE)
    syntoE_loc = max(syntoE, synto0)
    if sy_abs >= syntoE_loc
        return zero(float(nto0))
    end
    wf = synto0 / syntoE_loc
    if sy_abs <= synto0
        sy_n = sy_abs / synto0
        nto1 = nto0 * (1 - sy_n)
        nto2 = nto0 * (1 - (3 - 2 * sy_n) * sy_n^2)
        return (1 - wf) * nto1 + wf * nto2
    else
        sy_n = (syntoE_loc - sy_abs) / (syntoE_loc - synto0)
        return -nto0 * (1 - wf) * (sy_abs - synto0) / synto0 * sy_n^2
    end
end
@register_symbolic tmeasy_alignment_lever(sy_abs::Real, nto0::Real, synto0::Real, syntoE::Real)

"""
    sine_step(x, x1, y1, x2, y2)

Smooth step from `y1` at `x <= x1` to `y2` at `x >= x2` using a half-cosine
blend in between (C1). Registered symbolically due to the clamped ends.
"""
function sine_step(x, x1, y1, x2, y2)
    x <= x1 && return float(y1)
    x >= x2 && return float(y2)
    return y1 + (y2 - y1) * (1 - cos(π * (x - x1) / (x2 - x1))) / 2
end
@register_symbolic sine_step(x::Real, x1::Real, y1::Real, x2::Real, y2::Real)

"""
    align_transform(d0, d)

Transformation matrix of the minimal rotation that turns the unit vector `d0` into
the unit vector `d` (rotation about `d0 × d`). Returned in the convention of
frame orientations: it resolves a vector given in the rotated-from (world) frame in
the reference frame, so `align_transform(d0, d) * d == d0`. Smooth everywhere
except for antiparallel `d0` and `d`.
"""
function align_transform(d0, d)
    d0 = collect(d0); d = collect(d)
    K = MultibodyComponents.skew(cross(d0, d))
    collect(I(3) - K + K * K / (1 + dot(d0, d)))
end

"""
    spin_transform(e, angle)

Transformation matrix of a rotation by `angle` about the unit axis `e`.
"""
function spin_transform(e, angle)
    e = collect(e)
    ee = collect(e * e')
    ee + (I(3) - ee) * cos(angle) - MultibodyComponents.skew(e) * sin(angle)
end
