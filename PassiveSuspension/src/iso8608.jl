# ISO 8608 road profile generation helpers
# Used by the ISO8608RoadC Dyad component

"""
    iso8608_frequencies(f_min, f_max, N)

Return N center frequencies uniformly spaced between f_min and f_max (Hz).
"""
function iso8608_frequencies(f_min, f_max, N)
    Δf = (f_max - f_min) / N
    return Float64[f_min + (i - 0.5) * Δf for i in 1:N]
end

"""
    iso8608_amplitudes_base(Gd_n0, n0, f_min, f_max, N)

Compute velocity-independent part of ISO 8608 sinusoidal amplitudes.

Returns A_base[i] = √(2 · Gd(n0) · n0² · Δf / fᵢ²).
Multiply by √v to get the final amplitude at vehicle speed v.
"""
function iso8608_amplitudes_base(Gd_n0, n0, f_min, f_max, N)
    Δf = (f_max - f_min) / N
    freqs = iso8608_frequencies(f_min, f_max, N)
    return Float64[sqrt(2.0 * Gd_n0 * n0^2 * Δf / f^2) for f in freqs]
end

"""
    iso8608_phases(N)

Return N deterministic phase offsets in [0, 2π) using golden-angle spacing.
"""
function iso8608_phases(N)
    golden_angle = 2π * (sqrt(5.0) - 1.0) / 2.0
    return Float64[mod(i * golden_angle, 2π) for i in 1:N]
end
