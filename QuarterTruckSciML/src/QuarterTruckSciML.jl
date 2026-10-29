module QuarterTruckSciML

using Random
using Lux

"""
    iso8608_amplitudes(N, lambda_min, lambda_max, roughness)

Return Vector{Float64} of N amplitudes for ISO 8608 road harmonics,
log-spaced from 1/lambda_max to 1/lambda_min cycles/m.
PSD: G_d(n) = roughness * (n/0.1)^(-2).
"""
function iso8608_amplitudes(N::Integer, lambda_min::Real, lambda_max::Real, roughness::Real)::Vector{Float64}
    n0 = 0.1
    n_min = 1.0 / lambda_max
    n_max = 1.0 / lambda_min
    n_k = exp.(range(log(n_min), log(n_max), length=N))
    dn = zeros(N)
    for i in 1:N
        if i == 1
            dn[i] = n_k[2] - n_k[1]
        elseif i == N
            dn[i] = n_k[N] - n_k[N-1]
        else
            dn[i] = (n_k[i+1] - n_k[i-1]) / 2
        end
    end
    G_k = roughness .* (n_k ./ n0).^(-2)
    return sqrt.(2 .* G_k .* dn)
end

"""
    iso8608_frequencies(N, lambda_min, lambda_max)

Return Vector{Float64} of N spatial frequencies (cycles/m),
log-spaced from 1/lambda_max to 1/lambda_min.
Multiply by speed [m/s] to get temporal frequencies [Hz].
"""
function iso8608_frequencies(N::Integer, lambda_min::Real, lambda_max::Real)::Vector{Float64}
    n_min = 1.0 / lambda_max
    n_max = 1.0 / lambda_min
    return exp.(range(log(n_min), log(n_max), length=N))
end

"""
    iso8608_phases(N)

Return Vector{Float64} of N pseudo-random phases in [0, 2π), seeded for reproducibility.
"""
function iso8608_phases(N::Integer)::Vector{Float64}
    rng = MersenneTwister(42)
    return rand(rng, N) .* 2π
end

include("../generated/module.jl")

end # module QuarterTruckSciML
