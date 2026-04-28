"""
Shared utilities for thermal network ROM construction and calibration.

Zone assignments are determined by energy-weighted k-means clustering on
SVD mode shapes — no assumption about the source mesh structure.

Provides: mode clustering, zone averaging, N-zone ODE simulation,
and parameter calibration against CFD data.
"""

using LinearAlgebra, Statistics, OrdinaryDiffEqDefault, Optim, Printf
using CSV, DataFrames, Clustering, JSON

# ────────────────────────────────────────────────────────────
#  Calibrated thermal network result
# ────────────────────────────────────────────────────────────
struct CalibratedThermalNetwork
    "Number of zones"
    N::Int
    "Zone membership: zone_members[z] lists the spatial point indices in zone z"
    zone_members::Vector{Vector{Int}}
    "Per-node capacitance [J/K] (zone capacitance = C_per_node × zone size)"
    C_per_node::Float64
    "Inter-zone conductances [W/K]: G[i] = conductance between zone i and i+1"
    G::Vector{Float64}
    "Coolant-side conductance [W/K]"
    Gc::Float64
    "Zone-level RMSE [K] against CFD zone averages"
    zone_rmse::Float64
    "Spatial RMSE [K] against full CFD field"
    spatial_rmse::Float64
end

# ────────────────────────────────────────────────────────────
#  Clustering-based zone assignment
# ────────────────────────────────────────────────────────────
"""
    cluster_zones(modes, S, N) → Vector{Vector{Int}}

Assign M spatial points to N zones by energy-weighted k-means clustering
on the SVD mode shapes.

- `modes`: M × k matrix of mode shapes (columns of U from SVD)
- `S`: singular values (used to weight features by energy)
- `N`: number of clusters/zones

Returns `zone_members`, a length-N vector where `zone_members[z]` lists
the spatial point indices belonging to zone z, ordered so zone 1 has the
largest absolute mode-1 values (typically the heat-input end).
"""
function cluster_zones(modes::AbstractMatrix, S::AbstractVector, N::Int)
    k = size(modes, 2)
    # Weight each mode column by its singular value so dominant modes
    # drive the clustering
    modes_weighted = modes .* S[1:k]'

    # k-means: Clustering.jl expects features × points
    result = kmeans(modes_weighted', N; maxiter=300)
    assignments = result.assignments

    # Reorder clusters so zone 1 has the most negative mode-1 centroid
    # (highest absolute temperature deviation = heat-input end)
    centroids_m1 = [result.centers[1, c] for c in 1:N]
    order = sortperm(centroids_m1)
    remap = Dict(order[i] => i for i in 1:N)
    assignments = [remap[a] for a in assignments]

    return [sort(findall(==(z), assignments)) for z in 1:N]
end

# ────────────────────────────────────────────────────────────
#  Zone averaging and reconstruction
# ────────────────────────────────────────────────────────────
"""
    zone_averages(X, zone_members) → Matrix  (N_time × N)

Average spatial field X (N_time × M) into N zones defined by `zone_members`.
"""
function zone_averages(X::AbstractMatrix, zone_members::Vector{Vector{Int}})
    N = length(zone_members)
    Z = zeros(size(X, 1), N)
    for z in 1:N
        Z[:, z] = mean(X[:, zone_members[z]], dims=2)
    end
    return Z
end

"""
    zone_reconstruct(Z, zone_members, M) → Matrix  (N_time × M)

Expand N-zone temperatures Z (N_time × N) to M spatial nodes
using piecewise-constant reconstruction based on `zone_members`.
"""
function zone_reconstruct(Z::AbstractMatrix, zone_members::Vector{Vector{Int}}, M::Int)
    N = size(Z, 2)
    X_recon = zeros(size(Z, 1), M)
    for z in 1:N
        X_recon[:, zone_members[z]] .= Z[:, z]
    end
    return X_recon
end

# ────────────────────────────────────────────────────────────
#  Mode projection R² (clustering-based)
# ────────────────────────────────────────────────────────────
"""
    mode_projection_R2(modes, zone_members) → Vector{Float64}

Compute R² of each spatial mode when projected onto the piecewise-constant
basis defined by `zone_members`.
"""
function mode_projection_R2(modes::AbstractMatrix, zone_members::Vector{Vector{Int}})
    M, k = size(modes)
    R2 = zeros(k)
    for j in 1:k
        mode = modes[:, j]
        recon = zeros(M)
        for z in 1:length(zone_members)
            recon[zone_members[z]] .= mean(mode[zone_members[z]])
        end
        R2[j] = 1.0 - norm(mode - recon)^2 / norm(mode)^2
    end
    return R2
end

"""
    spatial_rmse_floor(X, zone_members) → Float64

Compute the irreducible spatial RMSE for the given zone assignment,
using the true zone-averaged data (perfect dynamics).
"""
function spatial_rmse_floor(X::AbstractMatrix, zone_members::Vector{Vector{Int}})
    M = size(X, 2)
    Z_true = zone_averages(X, zone_members)
    X_recon = zone_reconstruct(Z_true, zone_members, M)
    return sqrt(mean((X .- X_recon) .^ 2))
end

"""
    select_zone_count(modes, S, N_candidates, X; threshold) → (N, zone_members, all_R2, rmse_floors)

For each candidate N, cluster spatial points into N zones using
energy-weighted k-means on the mode shapes, compute mode R² and
spatial RMSE floor.  Select smallest N where worst-mode R² ≥ threshold.
"""
function select_zone_count(modes::AbstractMatrix, S::AbstractVector,
                           N_candidates::AbstractVector{Int},
                           X::AbstractMatrix;
                           threshold::Float64=0.90)
    N_sorted = sort(N_candidates)
    all_R2 = Dict{Int, Vector{Float64}}()
    all_members = Dict{Int, Vector{Vector{Int}}}()
    rmse_floors = Float64[]

    for N in N_sorted
        members = cluster_zones(modes, S, N)
        all_members[N] = members
        all_R2[N] = mode_projection_R2(modes, members)
        push!(rmse_floors, spatial_rmse_floor(X, members))
    end

    # Select smallest N where worst mode R² exceeds threshold
    N_opt = N_sorted[end]
    for N in N_sorted
        if minimum(all_R2[N]) >= threshold
            N_opt = N
            break
        end
    end

    return N_opt, all_members[N_opt], all_R2, all_members, rmse_floors
end

# ────────────────────────────────────────────────────────────
#  N-zone thermal network ODE simulation
# ────────────────────────────────────────────────────────────
"""
    simulate_thermal_network(C_per_node, zone_sizes, G_vec, Gc, t_data, Q_data)

Simulate an N-zone tridiagonal thermal network in deviation coordinates.
Each zone's capacitance is `C_per_node × zone_sizes[z]`.
Heat input Q enters zone 1; coolant loss Gc·θ_N exits zone N.
"""
function simulate_thermal_network(C_per_node::Float64, zone_sizes::Vector{Float64},
                                  G_vec::Vector{Float64}, Gc::Float64,
                                  t_data::Vector{Float64}, Q_data::Vector{Float64})
    N = length(zone_sizes)
    C_zones = C_per_node .* zone_sizes

    function f!(du, u, p, t)
        idx = clamp(searchsortedlast(t_data, t), 1, length(t_data))
        Q = Q_data[idx]
        du[1] = (Q + G_vec[1] * (u[2] - u[1])) / C_zones[1]
        for i in 2:(N-1)
            du[i] = (G_vec[i-1] * (u[i-1] - u[i]) + G_vec[i] * (u[i+1] - u[i])) / C_zones[i]
        end
        du[N] = (G_vec[N-1] * (u[N-1] - u[N]) - Gc * u[N]) / C_zones[N]
    end
    prob = ODEProblem(f!, zeros(N), (t_data[1], t_data[end]))
    sol  = solve(prob; saveat=t_data)
    return hcat([sol.u[i] for i in 1:length(sol.t)]...)'  # N_time × N
end

# ────────────────────────────────────────────────────────────
#  Parameter calibration
# ────────────────────────────────────────────────────────────
"""
    calibrate_thermal_network(zone_members, t_data, Q_data, Z_target, X_full;
                              C0_per_node, G0, Gc0, maxiter) → CalibratedThermalNetwork

Optimize C_per_node, G₁₂…G_{N-1,N}, Gc to minimize zone-level MSE against
`Z_target`.  `X_full` (N_time × M) is used to compute spatial RMSE.
"""
function calibrate_thermal_network(zone_members::Vector{Vector{Int}},
                                   t_data::Vector{Float64},
                                   Q_data::Vector{Float64},
                                   Z_target::Matrix{Float64},
                                   X_full::Matrix{Float64};
                                   C0_per_node::Float64=80.0,
                                   G0::Float64=40.0,
                                   Gc0::Float64=10.0,
                                   maxiter::Int=20000)
    N = length(zone_members)
    M = size(X_full, 2)
    n_G = N - 1
    zone_sizes = Float64[length(m) for m in zone_members]

    function obj(params)
        C_pn = params[1]
        Gv   = params[2:n_G+1]
        Gc   = params[n_G+2]
        (C_pn < 1.0 || any(Gv .< 0.1) || Gc < 0.1) && return 1e12
        try
            Z_sim = simulate_thermal_network(C_pn, zone_sizes, collect(Gv), Gc, t_data, Q_data)
            size(Z_sim, 1) != size(Z_target, 1) && return 1e12
            return sum((Z_sim .- Z_target) .^ 2)
        catch
            return 1e12
        end
    end

    x0 = vcat([C0_per_node], fill(G0, n_G), [Gc0])
    res = optimize(obj, x0, NelderMead(), Optim.Options(iterations=maxiter))
    p_opt = Optim.minimizer(res)

    C_pn_opt = p_opt[1]
    G_opt    = collect(p_opt[2:n_G+1])
    Gc_opt   = p_opt[n_G+2]

    # Compute final metrics
    Z_sim = simulate_thermal_network(C_pn_opt, zone_sizes, G_opt, Gc_opt, t_data, Q_data)
    zone_rmse = sqrt(mean((Z_sim .- Z_target) .^ 2))

    X_recon = zone_reconstruct(Z_sim, zone_members, M)
    spatial_rmse = sqrt(mean((X_full .- X_recon) .^ 2))

    return CalibratedThermalNetwork(N, zone_members, C_pn_opt, G_opt, Gc_opt,
                                    zone_rmse, spatial_rmse)
end

# ────────────────────────────────────────────────────────────
#  Data loading helper
# ────────────────────────────────────────────────────────────
"""
    load_cfd_data(path; spatial_cols, input_col, time_col, reference_temp)

Load CSV, extract spatial deviations X (N_time × M), input Q, time vector.
Auto-detects spatial columns matching `T_\\d+` if not specified.
"""
function load_cfd_data(path::String;
                       spatial_cols::Union{Nothing, Vector{String}}=nothing,
                       input_col::String="Q_in",
                       time_col::String="time",
                       reference_temp::Float64=300.0)
    df = CSV.read(path, DataFrame)
    t_data = Float64.(df[:, time_col])
    Q_data = Float64.(df[:, input_col])

    if isnothing(spatial_cols)
        all_cols = names(df)
        spatial_cols = sort(
            [c for c in all_cols if match(r"^T_\d+$", c) !== nothing],
            by = c -> parse(Int, match(r"(\d+)$", c).captures[1]),
        )
    end

    M = length(spatial_cols)
    X = Float64.(Matrix(df[:, spatial_cols]) .- reference_temp)  # N_time × M

    return (; t_data, Q_data, X, M, spatial_cols)
end


# ────────────────────────────────────────────────────────────
#  JSON persistence
# ────────────────────────────────────────────────────────────
"""
    save_network(path, net::CalibratedThermalNetwork)

Write a calibrated thermal network to a JSON file.
"""
function save_network(path::String, net::CalibratedThermalNetwork)
    d = Dict(
        "N"            => net.N,
        "zone_members" => net.zone_members,
        "C_per_node"   => net.C_per_node,
        "G"            => net.G,
        "Gc"           => net.Gc,
        "zone_rmse"    => net.zone_rmse,
        "spatial_rmse" => net.spatial_rmse,
    )
    open(path, "w") do io
        JSON.print(io, d, 2)  # indent=2 for readability
    end
    return path
end

"""
    load_network(path) → CalibratedThermalNetwork

Read a calibrated thermal network from a JSON file.
"""
function load_network(path::String)
    d = JSON.parsefile(path)
    return CalibratedThermalNetwork(
        d["N"],
        [convert(Vector{Int}, v) for v in d["zone_members"]],
        Float64(d["C_per_node"]),
        convert(Vector{Float64}, d["G"]),
        Float64(d["Gc"]),
        Float64(d["zone_rmse"]),
        Float64(d["spatial_rmse"]),
    )
end
