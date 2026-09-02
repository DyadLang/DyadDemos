using Lux: Lux

"""
    conductance_chain()

Lux chain for the `ConductanceNet` sub-network: `Dense(14 → 15, sigmoid)`.

A single linear layer followed by a sigmoid activation. Weights are initialised
with a small scaling factor so the network starts close to `sigmoid(0) = 0.5` —
conductances begin at mid-range and the NN contributes little until training
moves it off zero.
"""
function conductance_chain()
    return Lux.Chain(
        Lux.Dense(14, 15, Lux.sigmoid;
            init_weight = scaled_kaiming(1e-8),
            init_bias = Lux.zeros32),
    )
end

"""
    power_loss_chain()

Lux chain for the `PowerLossNet` sub-network:
`Dense(14 → 16, tanh) → Dense(16 → 4, abs)`.

The final `abs` enforces non-negative outputs (power loss ≥ 0). It lives inside
the chain rather than at the Dyad boundary because a sub-component's indexed
vector port (`nn.outputs[j]`) can only appear inside `connect(...)`, not inside
a general expression — the Dyad compiler rewrites it to a scalar field access
that `NeuralNetworkBlock` does not expose. To swap for a smooth alternative
later, replace the final layer's activation `abs` with `softplus` (keeps
non-negativity, differentiable at 0).
"""
function power_loss_chain()
    return Lux.Chain(
        Lux.Dense(14, 16, tanh; init_bias = Lux.zeros32),
        Lux.Dense(16, 4, abs;
            init_weight = scaled_kaiming(1e-8),
            init_bias = Lux.zeros32),
    )
end

scaled_kaiming(scale) = (rng, a...) -> scale * Lux.kaiming_uniform(rng, a...)
