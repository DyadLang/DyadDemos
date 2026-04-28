"""
    LatentNeuralODEAnalysis — Automatic ROM order discovery from spatial field data.

Trains an Encoder → Neural ODE → Decoder pipeline for a sweep of latent
dimensions k, then selects the optimal order from the reconstruction error curve.
After discovering k, performs SVD mode projection to determine the physical zone
count N and calibrates a tridiagonal thermal network.

## Architecture

    Encoder:  R^M → R^k      (compress spatial snapshot to latent state)
    Dynamics: dz/dt = f(z, u)  (Euler-discretised Neural ODE in latent space)
    Decoder:  R^k → R^M      (reconstruct spatial field from latent state)

Training minimises ‖Decoder(z(tᵢ)) − x(tᵢ)‖² over multiple-shooting windows,
with gradients flowing through the recurrence via Zygote.

## Usage

```julia
using CFDReducedOrderModeling

result = LatentNeuralODEAnalysis(
    data = "cfd_training_data.csv",
    latent_dims = [1, 2, 3, 4, 5, 6],
    n_epochs = 300,
)

result.r.best_k               # discovered ROM order (latent dimensions)
result.r.train_rmse           # RMSE for each k
result.r.network              # calibrated N-zone thermal network
result.r.network.N            # number of physical zones
result.r.network.zone_members # which spatial points in each zone

# Dyad analysis interface
artifacts(result)                              # list available artifacts
artifacts(result, :CalibratedNetwork)          # DataFrame of network parameters
artifacts(result, :LatentDimSweep)             # DataFrame of RMSE per latent dim
artifacts(result, :ZoneAssignments)            # DataFrame of zone membership
artifacts(result, :RawResult)                  # raw LatentNeuralODEResult struct
```
"""

using CSV, DataFrames, Statistics, Printf, LinearAlgebra
using Lux, ComponentArrays, Zygote, Optimisers, Random
using DyadInterface
using DyadInterface: AbstractAnalysisSpec, AbstractAnalysisSolution,
    AnalysisSolutionMetadata, ArtifactMetadata, ArtifactType

# ────────────────────────────────────────────────────────────
#  Result type (unchanged)
# ────────────────────────────────────────────────────────────
struct LatentNeuralODEResult
    "Latent dimensions tested"
    latent_dims::Vector{Int}
    "Reconstruction RMSE (K) for each latent dimension"
    train_rmse::Vector{Float64}
    "Discovered ROM order (knee of the RMSE curve)"
    best_k::Int
    "Trained parameters for the best k"
    best_params::Any
    "Encoder network (Lux Chain)"
    encoder::Any
    "Dynamics network (Lux Chain)"
    dynamics::Any
    "Decoder network (Lux Chain)"
    decoder::Any
    "Normalisation scale"
    x_scale::Float32
    "Network states"
    states::Any
    "Number of physical zones (from mode projection)"
    N_zones::Int
    "Mode R² for each candidate N (Dict: N => Vector of R² per mode)"
    mode_R2::Dict{Int, Vector{Float64}}
    "Calibrated thermal network"
    network::CalibratedThermalNetwork
end

# ────────────────────────────────────────────────────────────
#  Dyad analysis spec
# ────────────────────────────────────────────────────────────
abstract type AbstractLatentNeuralODESpec <: AbstractAnalysisSpec end

"""
    LatentNeuralODESpec(; data, ...)

Specification for the Latent Neural ODE ROM analysis.
"""
@kwdef struct LatentNeuralODESpec <: AbstractLatentNeuralODESpec
    name::Symbol = :LatentNeuralODEAnalysis
    "Path to CSV with time, spatial field, and input columns"
    data::String
    "Spatial DOF column names (nothing = auto-detect T_\\d+)"
    spatial_cols::Union{Nothing, Vector{String}} = nothing
    "External input column name"
    input_col::String = "Q_in"
    "Time column name"
    time_col::String = "time"
    "Reference temperature for deviation coordinates"
    reference_temp::Float64 = 300.0
    "Latent dimensions to sweep"
    latent_dims::Vector{Int} = [1, 2, 3, 4, 5, 6]
    "Hidden-layer width in encoder"
    hidden_enc::Int = 64
    "Hidden-layer width in dynamics network"
    hidden_dyn::Int = 32
    "Hidden-layer width in decoder"
    hidden_dec::Int = 64
    "Training epochs per (k, seed) pair"
    n_epochs::Int = 300
    "Adam learning rate"
    lr::Float64 = 5e-4
    "Number of multiple-shooting windows"
    n_shooting::Int = 15
    "Steps per shooting window"
    window_len::Int = 15
    "Random seeds tried per k (best kept)"
    n_seeds::Int = 3
    "Minimum per-mode R² for zone count selection"
    R2_threshold::Float64 = 0.88
    "Candidate zone counts"
    N_candidates::Vector{Int} = [2, 3, 4, 5, 6, 8, 10]
    "Initial guess for per-node capacitance [J/K]"
    C0_per_node::Float64 = 80.0
    "Initial guess for inter-zone conductance [W/K]"
    G0::Float64 = 40.0
    "Initial guess for coolant conductance [W/K]"
    Gc0::Float64 = 10.0
    "Maximum calibration optimizer iterations"
    maxiter::Int = 10000
    "If non-empty, save the calibrated network to this JSON path"
    output::String = ""
    "Print progress"
    verbose::Bool = true
end

# ────────────────────────────────────────────────────────────
#  Dyad analysis solution
# ────────────────────────────────────────────────────────────

"""
    LatentNeuralODESolution

Wraps `LatentNeuralODEResult` in the Dyad `AbstractAnalysisSolution` interface.
Access the raw result via `result.r`.
"""
struct LatentNeuralODESolution <: AbstractAnalysisSolution
    spec::LatentNeuralODESpec
    r::LatentNeuralODEResult
end

# ── Metadata ──────────────────────────────────────────────
const _NODE_ARTIFACT_META = [
    ArtifactMetadata(
        :CalibratedNetwork, ArtifactType.DataFrame,
        "Calibrated Network",
        "Calibrated thermal network parameters: capacitances, conductances, and fit metrics."
    ),
    ArtifactMetadata(
        :LatentDimSweep, ArtifactType.DataFrame,
        "Latent Dimension Sweep",
        "Reconstruction RMSE for each candidate latent dimension, with improvement ratios."
    ),
    ArtifactMetadata(
        :ZoneAssignments, ArtifactType.DataFrame,
        "Zone Assignments",
        "Data-driven zone membership from energy-weighted k-means on SVD mode shapes."
    ),
    ArtifactMetadata(
        :RawResult, ArtifactType.Native,
        "Raw Result",
        "The underlying LatentNeuralODEResult struct for programmatic access."
    ),
]

function DyadInterface.AnalysisSolutionMetadata(::LatentNeuralODESolution)
    AnalysisSolutionMetadata(_NODE_ARTIFACT_META, Symbol[])
end

# ── Artifact generation ───────────────────────────────────
function DyadInterface.artifacts(sol::LatentNeuralODESolution, name::Symbol)
    r = sol.r
    net = r.network

    if name === :CalibratedNetwork
        rows = Dict{String, Any}[]
        push!(rows, Dict("parameter" => "N_zones", "value" => Float64(net.N)))
        push!(rows, Dict("parameter" => "best_k", "value" => Float64(r.best_k)))
        push!(rows, Dict("parameter" => "C_per_node", "value" => net.C_per_node))
        for z in 1:net.N
            push!(rows, Dict("parameter" => "C_zone_$z",
                             "value" => net.C_per_node * length(net.zone_members[z])))
        end
        for i in 1:length(net.G)
            push!(rows, Dict("parameter" => "G_$(i)_$(i+1)", "value" => net.G[i]))
        end
        push!(rows, Dict("parameter" => "Gc", "value" => net.Gc))
        push!(rows, Dict("parameter" => "zone_rmse", "value" => net.zone_rmse))
        push!(rows, Dict("parameter" => "spatial_rmse", "value" => net.spatial_rmse))
        return DataFrame(rows)

    elseif name === :LatentDimSweep
        n = length(r.latent_dims)
        ratios = Vector{Float64}(undef, n)
        ratios[1] = NaN
        for i in 2:n
            ratios[i] = r.train_rmse[i-1] / r.train_rmse[i]
        end
        return DataFrame(
            latent_dim = r.latent_dims,
            rmse_K = r.train_rmse,
            improvement_ratio = ratios,
            selected = [k == r.best_k for k in r.latent_dims],
        )

    elseif name === :ZoneAssignments
        rows = Dict{String, Any}[]
        for z in 1:net.N
            for pt in net.zone_members[z]
                push!(rows, Dict("zone" => z, "spatial_point" => pt,
                                 "zone_size" => length(net.zone_members[z])))
            end
        end
        return DataFrame(rows)

    elseif name === :RawResult
        return r

    else
        error("Unknown artifact: $name. Available: $(first.(getfield.(_NODE_ARTIFACT_META, :name)))")
    end
end

# ────────────────────────────────────────────────────────────
#  run_analysis
# ────────────────────────────────────────────────────────────
function DyadInterface.run_analysis(spec::LatentNeuralODESpec)
    r = _run_neural_ode_pipeline(;
        data            = spec.data,
        spatial_cols    = spec.spatial_cols,
        input_col       = spec.input_col,
        time_col        = spec.time_col,
        reference_temp  = spec.reference_temp,
        latent_dims     = spec.latent_dims,
        hidden_enc      = spec.hidden_enc,
        hidden_dyn      = spec.hidden_dyn,
        hidden_dec      = spec.hidden_dec,
        n_epochs        = spec.n_epochs,
        lr              = spec.lr,
        n_shooting      = spec.n_shooting,
        window_len      = spec.window_len,
        n_seeds         = spec.n_seeds,
        R2_threshold    = spec.R2_threshold,
        N_candidates    = spec.N_candidates,
        C0_per_node     = spec.C0_per_node,
        G0              = spec.G0,
        Gc0             = spec.Gc0,
        maxiter         = spec.maxiter,
        output          = spec.output,
        verbose         = spec.verbose,
    )
    return LatentNeuralODESolution(spec, r)
end

# ────────────────────────────────────────────────────────────
#  Convenience constructor
# ────────────────────────────────────────────────────────────
"""
    LatentNeuralODEAnalysis(; data, ...) → LatentNeuralODESolution

Discover ROM order via Latent Neural ODE, then calibrate a thermal network.
Returns a `LatentNeuralODESolution` implementing the Dyad analysis interface.

Access the raw result via `result.r`, or use `artifacts(result, :CalibratedNetwork)`.
"""
function LatentNeuralODEAnalysis(; kwargs...)
    spec = LatentNeuralODESpec(; kwargs...)
    DyadInterface.run_analysis(spec)
end

# ────────────────────────────────────────────────────────────
#  Core pipeline
# ────────────────────────────────────────────────────────────
function _run_neural_ode_pipeline(;
    data::String,
    spatial_cols::Union{Nothing, Vector{String}} = nothing,
    input_col::String = "Q_in",
    time_col::String = "time",
    reference_temp::Float64 = 300.0,
    latent_dims::Vector{Int} = [1, 2, 3, 4, 5, 6],
    hidden_enc::Int = 64,
    hidden_dyn::Int = 32,
    hidden_dec::Int = 64,
    n_epochs::Int = 300,
    lr::Float64 = 5e-4,
    n_shooting::Int = 15,
    window_len::Int = 15,
    n_seeds::Int = 3,
    R2_threshold::Float64 = 0.88,
    N_candidates::Vector{Int} = [2, 3, 4, 5, 6, 8, 10],
    C0_per_node::Float64 = 80.0,
    G0::Float64 = 40.0,
    Gc0::Float64 = 10.0,
    maxiter::Int = 10000,
    output::String = "",
    verbose::Bool = true,
)
    # ── Load & prepare data ──────────────────────────────────
    cfd = load_cfd_data(data; spatial_cols, input_col, time_col, reference_temp)
    t_data, Q_data, X_full, M = cfd.t_data, cfd.Q_data, cfd.X, cfd.M

    X_raw   = Float32.(X_full')  # M × N_time
    Q_input = Float32.(Q_data)
    N_time  = length(t_data)

    x_scale = maximum(abs.(X_raw)) + 1.0f-8
    X_norm  = X_raw ./ x_scale
    q_scale = maximum(abs.(Q_input)) + 1.0f-8
    Q_norm  = Q_input ./ q_scale
    dt_data = Float32.(diff(Float32.(t_data)))

    # Multiple-shooting windows
    stride = max((N_time - window_len) ÷ n_shooting, 1)
    window_starts = collect(1:stride:(N_time - window_len))
    if length(window_starts) > n_shooting
        window_starts = window_starts[1:n_shooting]
    end

    if verbose
        println("=" ^ 65)
        println("  LATENT NEURAL ODE — ROM ORDER DISCOVERY + CALIBRATION")
        println("=" ^ 65)
        println("  Spatial DOFs: $M,  Time steps: $N_time")
        println("  Shooting: $(length(window_starts)) windows × $window_len steps")
        println("  Training: $n_epochs epochs, $n_seeds seeds, lr=$lr")
        println()
        println("  PHASE 1: Neural ODE Latent Dimension Sweep")
        println("  ──────────────────────────────────────────")
        println("  k │ RMSE (K)   │ vs k-1 │ Params")
        println("  ──┼────────────┼────────┼───────")
    end

    # ── Phase 1: Sweep latent dimensions ─────────────────────
    results_rmse = Float64[]
    all_trained  = NamedTuple[]

    for k in latent_dims
        best_k_rmse = Inf
        best_k_data = nothing

        for seed_idx in 1:n_seeds
            rng = Random.Xoshiro(seed_idx * 42 + k)

            enc     = Lux.Chain(Lux.Dense(M => hidden_enc, tanh),
                                Lux.Dense(hidden_enc => k))
            dyn_net = Lux.Chain(Lux.Dense(k + 1 => hidden_dyn, tanh),
                                Lux.Dense(hidden_dyn => k))
            dec_net = Lux.Chain(Lux.Dense(k => hidden_dec, tanh),
                                Lux.Dense(hidden_dec => M))

            ps_e,  st_e  = Lux.setup(rng, enc)
            ps_d,  st_d  = Lux.setup(rng, dyn_net)
            ps_dc, st_dc = Lux.setup(rng, dec_net)

            ps_all = ComponentArray(enc = ps_e, dyn = ps_d, dec = ps_dc)
            st_all = (enc = st_e, dyn = st_d, dec = st_dc)
            opt    = Optimisers.setup(Optimisers.Adam(Float32(lr)), ps_all)

            _enc, _dyn, _dec, _st = enc, dyn_net, dec_net, st_all

            function loss_f(ps)
                total = 0.0f0
                for ws in window_starts
                    z, _ = _enc(X_norm[:, ws], ps.enc, _st.enc)
                    for j in 0:(window_len - 1)
                        ti = ws + j
                        ti > N_time && break
                        x_hat, _ = _dec(z, ps.dec, _st.dec)
                        total += sum((x_hat .- X_norm[:, ti]) .^ 2)
                        if ti < N_time
                            inp    = vcat(z, [Q_norm[ti]])
                            dz, _  = _dyn(inp, ps.dyn, _st.dyn)
                            z      = z .+ dt_data[ti] .* dz
                        end
                    end
                end
                return total / (length(window_starts) * window_len * M)
            end

            for _ in 1:n_epochs
                g = Zygote.gradient(loss_f, ps_all)[1]
                isnothing(g) && break
                gn = norm(g)
                gn > 10.0f0 && (g = g .* (10.0f0 / gn))
                opt, ps_all = Optimisers.update(opt, ps_all, g)
            end

            rmse = sqrt(Float64(loss_f(ps_all))) * Float64(x_scale)
            if rmse < best_k_rmse
                best_k_rmse = rmse
                best_k_data = (
                    ps  = deepcopy(ps_all),
                    st  = deepcopy(_st),
                    enc = _enc,
                    dyn = _dyn,
                    dec = _dec,
                )
            end
        end  # seeds

        push!(results_rmse, best_k_rmse)
        push!(all_trained, (k = k, rmse = best_k_rmse, data = best_k_data))

        if verbose
            np = Lux.parameterlength(best_k_data.enc) +
                 Lux.parameterlength(best_k_data.dyn) +
                 Lux.parameterlength(best_k_data.dec)
            ratio = length(results_rmse) > 1 ?
                    results_rmse[end-1] / best_k_rmse : NaN
            rs = isnan(ratio) ? "  —  " : @sprintf("%4.1f×", ratio)
            @printf("  %d │  %8.4f  │  %s │ %d\n", k, best_k_rmse, rs, np)
        end
    end  # k sweep

    # ── Knee detection ───────────────────────────────────────
    if length(results_rmse) > 1
        ratios  = [results_rmse[i] / results_rmse[i+1]
                   for i in 1:(length(results_rmse) - 1)]
        knee_k  = latent_dims[argmax(ratios) + 1]
    else
        knee_k = latent_dims[1]
    end

    best = all_trained[argmin([r.rmse for r in all_trained])]

    if verbose
        println()
        println("  ► Discovered latent order (knee): k = $knee_k")
        println("  ► Best RMSE: $(round(best.rmse; digits=4)) K at k=$(best.k)")
        println()
    end

    # ── Phase 2: SVD mode clustering → zone count ──────────
    if verbose
        println("  PHASE 2: SVD Mode Clustering → Zone Count")
        println("  ──────────────────────────────────────────")
    end

    F = svd(X_full')  # M × N_time
    U_modes, S_vals = F.U, F.S
    modes = U_modes[:, 1:knee_k]

    N_opt, zone_members_opt, all_R2, all_members, _ =
        select_zone_count(modes, S_vals, N_candidates, X_full; threshold=R2_threshold)

    if verbose
        N_sorted = sort(N_candidates)
        for N in N_sorted
            worst_r2 = minimum(all_R2[N])
            sizes = [length(m) for m in all_members[N]]
            marker = N == N_opt ? " ← selected" : ""
            @printf("    N=%2d: worst mode R²=%5.1f%%, zones=%s%s\n",
                    N, 100*worst_r2, string(sizes), marker)
        end
        println("    R² threshold: $(100*R2_threshold)% → N = $N_opt zones")
        println()
        for z in 1:N_opt
            @printf("      Zone %d: points %s (%d points)\n",
                    z, string(zone_members_opt[z]), length(zone_members_opt[z]))
        end
        println()
    end

    # ── Phase 3: Calibrate thermal network ───────────────────
    if verbose
        println("  PHASE 3: Calibrate $N_opt-Zone Thermal Network")
        println("  ─────────────────────────────────────────────")
        print("    Optimizing parameters ... ")
    end

    Z_target = zone_averages(X_full, zone_members_opt)
    net = calibrate_thermal_network(zone_members_opt, t_data, Q_data, Z_target, X_full;
                                    C0_per_node=C0_per_node, G0=G0, Gc0=Gc0,
                                    maxiter=maxiter)

    if verbose
        println("done.")
        zone_sizes = [length(m) for m in zone_members_opt]
        @printf("    C_per_node = %6.1f J/K\n", net.C_per_node)
        for i in 1:length(net.G)
            @printf("    G%d%d = %8.2f W/K\n", i, i+1, net.G[i])
        end
        @printf("    Gc  = %8.2f W/K\n", net.Gc)
        @printf("    Zone RMSE:    %6.3f K\n", net.zone_rmse)
        @printf("    Spatial RMSE: %6.3f K\n", net.spatial_rmse)
        println()
        println("=" ^ 65)
    end

    if !isempty(output)
        mkpath(dirname(output))
        save_network(output, net)
        verbose && println("  Saved network → $output")
    end

    return LatentNeuralODEResult(
        latent_dims, results_rmse, knee_k,
        best.data.ps, best.data.enc, best.data.dyn,
        best.data.dec, x_scale, best.data.st,
        N_opt, all_R2, net,
    )
end
