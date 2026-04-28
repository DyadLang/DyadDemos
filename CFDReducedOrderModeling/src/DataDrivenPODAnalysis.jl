"""
    DataDrivenPODAnalysis — POD/DMDc ROM construction purely from spatial field data.

Performs the complete pipeline:
1. SVD of spatial snapshots → discover dominant POD modes (rank k)
2. Project dynamics onto POD basis → reduced coordinates z(t)
3. DMDc via least-squares: fit dz/dt = A z + B u from finite differences
4. Energy-weighted k-means on mode shapes → zone count N and zone assignments
5. Build output matrix C mapping POD coordinates to zone-averaged temperatures

No model equations are needed — only input/output time series.

## Usage

```julia
using CFDReducedOrderModeling

result = DataDrivenPODAnalysis(
    data = "data/cfd_training_data.csv",
    output = "results/pod_dmdc.json",
)

result.r.k                  # number of POD modes
result.r.A                  # k×k dynamics matrix
result.r.B                  # k×1 input matrix
result.r.C                  # N_zones×k output matrix
result.r.zone_members       # which spatial points in each zone
result.r.train_zone_rmse    # zone-level RMSE on training data [K]
result.r.train_spatial_rmse # spatial RMSE on training data [K]

# Dyad analysis interface
artifacts(result)                          # list available artifacts
artifacts(result, :ROMParameters)          # DataFrame of A, B, C matrices
artifacts(result, :SVDEnergy)              # DataFrame of singular values
artifacts(result, :ZoneAssignments)        # DataFrame of zone membership
artifacts(result, :RawResult)              # raw DataDrivenPODResult struct
```
"""

using LinearAlgebra, Statistics, OrdinaryDiffEqDefault, Printf
using DataFrames
using DyadInterface
using DyadInterface: AbstractAnalysisSpec, AbstractAnalysisSolution,
    AnalysisSolutionMetadata, ArtifactMetadata, ArtifactType

# ────────────────────────────────────────────────────────────
#  Result type (unchanged — stores the raw computation output)
# ────────────────────────────────────────────────────────────
struct DataDrivenPODResult
    "Number of POD modes"
    k::Int
    "Singular values"
    singular_values::Vector{Float64}
    "Cumulative energy fraction"
    cumulative_energy::Vector{Float64}
    "Dynamics matrix (k × k)"
    A::Matrix{Float64}
    "Input matrix (k × 1)"
    B::Matrix{Float64}
    "Output matrix (N_zones × k)"
    C::Matrix{Float64}
    "Number of physical zones"
    N_zones::Int
    "Zone membership"
    zone_members::Vector{Vector{Int}}
    "Zone-level RMSE on training data [K]"
    train_zone_rmse::Float64
    "Spatial RMSE on training data [K]"
    train_spatial_rmse::Float64
end

# ────────────────────────────────────────────────────────────
#  Dyad analysis spec
# ────────────────────────────────────────────────────────────
abstract type AbstractDataDrivenPODSpec <: AbstractAnalysisSpec end

"""
    DataDrivenPODSpec(; data, ...)

Specification for the POD/DMDc ROM analysis.  All parameters match the
keyword arguments of the original `DataDrivenPODAnalysis` function.
"""
@kwdef struct DataDrivenPODSpec <: AbstractDataDrivenPODSpec
    name::Symbol = :DataDrivenPODAnalysis
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
    "Cumulative energy threshold for selecting k"
    energy_threshold::Float64 = 0.999
    "If > 0, override automatic k selection"
    k_override::Int = 0
    "Minimum per-mode R² for zone count selection"
    R2_threshold::Float64 = 0.88
    "Candidate zone counts"
    N_candidates::Vector{Int} = [2, 3, 4, 5, 6, 8, 10]
    "If non-empty, save the ROM to this JSON path"
    output::String = ""
    "Print progress"
    verbose::Bool = true
end

# ────────────────────────────────────────────────────────────
#  Dyad analysis solution
# ────────────────────────────────────────────────────────────

"""
    DataDrivenPODSolution

Wraps `DataDrivenPODResult` in the Dyad `AbstractAnalysisSolution` interface,
providing artifacts and metadata.

Access the raw result via `result.r`.
"""
struct DataDrivenPODSolution <: AbstractAnalysisSolution
    spec::DataDrivenPODSpec
    r::DataDrivenPODResult
end

# ── Metadata: declare available artifacts ─────────────────
const _POD_ARTIFACT_META = [
    ArtifactMetadata(
        :ROMParameters, ArtifactType.DataFrame,
        "ROM Parameters",
        "A, B, C matrices and scalar parameters of the identified POD/DMDc ROM."
    ),
    ArtifactMetadata(
        :SVDEnergy, ArtifactType.DataFrame,
        "SVD Energy",
        "Singular values and cumulative energy fraction from the snapshot SVD."
    ),
    ArtifactMetadata(
        :ZoneAssignments, ArtifactType.DataFrame,
        "Zone Assignments",
        "Data-driven zone membership from energy-weighted k-means on SVD mode shapes."
    ),
    ArtifactMetadata(
        :RawResult, ArtifactType.Native,
        "Raw Result",
        "The underlying DataDrivenPODResult struct for programmatic access."
    ),
]

function DyadInterface.AnalysisSolutionMetadata(::DataDrivenPODSolution)
    AnalysisSolutionMetadata(_POD_ARTIFACT_META, Symbol[])
end

# ── Artifact generation ───────────────────────────────────
function DyadInterface.artifacts(sol::DataDrivenPODSolution, name::Symbol)
    r = sol.r
    if name === :ROMParameters
        rows = Dict{String, Any}[]
        # A matrix
        for i in 1:r.k, j in 1:r.k
            push!(rows, Dict("matrix" => "A", "row" => i, "col" => j, "value" => r.A[i, j]))
        end
        # B matrix
        for i in 1:r.k
            push!(rows, Dict("matrix" => "B", "row" => i, "col" => 1, "value" => r.B[i, 1]))
        end
        # C matrix
        for i in 1:r.N_zones, j in 1:r.k
            push!(rows, Dict("matrix" => "C", "row" => i, "col" => j, "value" => r.C[i, j]))
        end
        # Scalars
        push!(rows, Dict("matrix" => "scalar", "row" => 0, "col" => 0, "value" => Float64(r.k)),)
        push!(rows, Dict("matrix" => "scalar_Nzones", "row" => 0, "col" => 0, "value" => Float64(r.N_zones)))
        push!(rows, Dict("matrix" => "zone_rmse", "row" => 0, "col" => 0, "value" => r.train_zone_rmse))
        push!(rows, Dict("matrix" => "spatial_rmse", "row" => 0, "col" => 0, "value" => r.train_spatial_rmse))
        return DataFrame(rows)

    elseif name === :SVDEnergy
        n = length(r.singular_values)
        return DataFrame(
            mode = 1:n,
            singular_value = r.singular_values,
            cumulative_energy = r.cumulative_energy,
            cumulative_energy_pct = 100.0 .* r.cumulative_energy,
        )

    elseif name === :ZoneAssignments
        rows = Dict{String, Any}[]
        for z in 1:r.N_zones
            for pt in r.zone_members[z]
                push!(rows, Dict("zone" => z, "spatial_point" => pt,
                                 "zone_size" => length(r.zone_members[z])))
            end
        end
        return DataFrame(rows)

    elseif name === :RawResult
        return r

    else
        error("Unknown artifact: $name. Available: $(first.(getfield.(_POD_ARTIFACT_META, :name)))")
    end
end

# ────────────────────────────────────────────────────────────
#  Simulation helper
# ────────────────────────────────────────────────────────────
"""
    simulate_pod_rom(A, B, C, t_data, Q_data) → Matrix (N_time × N_zones)

Simulate the POD/DMDc ROM in deviation coordinates.
Returns zone-averaged temperature deviations (θ = T − T_ref).
"""
function simulate_pod_rom(A::Matrix{Float64}, B::Matrix{Float64},
                          C::Matrix{Float64},
                          t_data::Vector{Float64}, Q_data::Vector{Float64})
    k = size(A, 1)
    function f!(dz, z, p, t)
        idx = clamp(searchsortedlast(t_data, t), 1, length(t_data))
        u = Q_data[idx]
        dz .= A * z .+ B[:, 1] .* u
    end
    prob = ODEProblem(f!, zeros(k), (t_data[1], t_data[end]))
    sol = solve(prob; saveat=t_data)
    N_time = length(sol.t)
    N_zones = size(C, 1)
    Y = zeros(N_time, N_zones)
    for i in 1:N_time
        Y[i, :] = C * sol.u[i]
    end
    return Y
end

# ────────────────────────────────────────────────────────────
#  JSON persistence
# ────────────────────────────────────────────────────────────
"""
    save_pod_rom(path, result::DataDrivenPODResult)

Write a POD/DMDc ROM to a JSON file.
"""
function save_pod_rom(path::String, result::DataDrivenPODResult)
    d = Dict(
        "k"                  => result.k,
        "A"                  => [collect(result.A[i, :]) for i in 1:size(result.A, 1)],
        "B"                  => [collect(result.B[i, :]) for i in 1:size(result.B, 1)],
        "C"                  => [collect(result.C[i, :]) for i in 1:size(result.C, 1)],
        "N_zones"            => result.N_zones,
        "zone_members"       => result.zone_members,
        "train_zone_rmse"    => result.train_zone_rmse,
        "train_spatial_rmse" => result.train_spatial_rmse,
    )
    open(path, "w") do io
        JSON.print(io, d, 2)
    end
    return path
end

"""
    load_pod_rom(path) → NamedTuple

Read a POD/DMDc ROM from a JSON file.
"""
function load_pod_rom(path::String)
    d = JSON.parsefile(path)
    A = vcat([Float64.(d["A"][i])' for i in 1:length(d["A"])]...)
    B = vcat([Float64.(d["B"][i])' for i in 1:length(d["B"])]...)
    C = vcat([Float64.(d["C"][i])' for i in 1:length(d["C"])]...)
    zone_members = [convert(Vector{Int}, v) for v in d["zone_members"]]
    return (
        k = d["k"],
        A = A,
        B = B,
        C = C,
        N_zones = d["N_zones"],
        zone_members = zone_members,
        train_zone_rmse = Float64(d["train_zone_rmse"]),
        train_spatial_rmse = Float64(d["train_spatial_rmse"]),
    )
end

# ────────────────────────────────────────────────────────────
#  run_analysis — the Dyad entry point
# ────────────────────────────────────────────────────────────
function DyadInterface.run_analysis(spec::DataDrivenPODSpec)
    r = _run_pod_pipeline(;
        data            = spec.data,
        spatial_cols    = spec.spatial_cols,
        input_col       = spec.input_col,
        time_col        = spec.time_col,
        reference_temp  = spec.reference_temp,
        energy_threshold = spec.energy_threshold,
        k_override      = spec.k_override,
        R2_threshold    = spec.R2_threshold,
        N_candidates    = spec.N_candidates,
        output          = spec.output,
        verbose         = spec.verbose,
    )
    return DataDrivenPODSolution(spec, r)
end

# ────────────────────────────────────────────────────────────
#  Convenience constructor (preserves existing call signature)
# ────────────────────────────────────────────────────────────
"""
    DataDrivenPODAnalysis(; data, ...) → DataDrivenPODSolution

Data-driven POD/DMDc ROM construction from spatial field data.
Returns a `DataDrivenPODSolution` implementing the Dyad analysis interface.

Access the raw result via `result.r`, or use `artifacts(result, :ROMParameters)`.
"""
function DataDrivenPODAnalysis(; kwargs...)
    spec = DataDrivenPODSpec(; kwargs...)
    DyadInterface.run_analysis(spec)
end

# ────────────────────────────────────────────────────────────
#  Core pipeline (extracted from original function)
# ────────────────────────────────────────────────────────────
function _run_pod_pipeline(;
    data::String,
    spatial_cols::Union{Nothing, Vector{String}} = nothing,
    input_col::String = "Q_in",
    time_col::String = "time",
    reference_temp::Float64 = 300.0,
    energy_threshold::Float64 = 0.999,
    k_override::Int = 0,
    R2_threshold::Float64 = 0.88,
    N_candidates::Vector{Int} = [2, 3, 4, 5, 6, 8, 10],
    output::String = "",
    verbose::Bool = true,
)
    # ── Step 0: Load data ────────────────────────────────────
    cfd = load_cfd_data(data; spatial_cols, input_col, time_col, reference_temp)
    t_data, Q_data, X, M = cfd.t_data, cfd.Q_data, cfd.X, cfd.M
    N_time = length(t_data)

    if verbose
        println("=" ^ 65)
        println("  DATA-DRIVEN POD/DMDc — ROM FROM SNAPSHOTS")
        println("=" ^ 65)
        println("  Spatial DOFs: $M,  Time steps: $N_time")
        println()
    end

    # ── Step 1: SVD → POD modes ──────────────────────────────
    F = svd(X')  # M × N_time
    U_modes, S_vals = F.U, F.S
    V_time = F.Vt'  # N_time × n (right singular vectors)
    cum_energy = cumsum(S_vals .^ 2) / sum(S_vals .^ 2)

    if k_override > 0
        k = k_override
    else
        k = findfirst(e -> e >= energy_threshold, cum_energy)
        isnothing(k) && (k = length(S_vals))
    end

    U_k = U_modes[:, 1:k]  # M × k (POD spatial modes)

    if verbose
        println("  STEP 1: SVD → POD Modes")
        println("  ───────────────────────")
        n_show = min(k + 2, length(S_vals))
        for i in 1:n_show
            marker = i == k ? " ← k" : ""
            @printf("    Mode %d: σ=%8.2f  energy=%7.4f%%%s\n",
                    i, S_vals[i], 100 * cum_energy[i], marker)
        end
        println("    → k = $k POD modes")
        println()
    end

    # ── Step 2: Project onto POD basis → reduced coordinates ──
    Z = X * U_k  # N_time × k (reduced coordinates)

    # ── Step 3: DMDc — fit dz/dt = A z + B u ─────────────────
    dt_vec = diff(t_data)
    dZ = diff(Z, dims=1) ./ dt_vec  # (N_time-1) × k

    Z_mid = Z[1:end-1, :]           # (N_time-1) × k
    U_mid = Q_data[1:end-1]         # (N_time-1)

    Omega = hcat(Z_mid, U_mid)'     # (k+1) × (N_time-1)
    AB = dZ' * pinv(Omega)          # k × (k+1)

    A_c = AB[:, 1:k]               # k × k
    B_c = AB[:, k+1:k+1]           # k × 1

    if verbose
        println("  STEP 2: DMDc — Continuous-Time Dynamics")
        println("  ────────────────────────────────────────")
        eigs = eigvals(A_c)
        @printf("    A: %d×%d, max Re(λ) = %.4f (stable: %s)\n",
                k, k, maximum(real.(eigs)),
                all(real.(eigs) .< 0) ? "yes" : "NO")
        @printf("    B: %d×1\n", k)
        println()
    end

    # ── Step 4: Zone clustering ───────────────────────────────
    modes = U_k  # M × k
    N_opt, zone_members_opt, all_R2, _, _ =
        select_zone_count(modes, S_vals, N_candidates, X; threshold=R2_threshold)

    C_mat = zeros(N_opt, k)
    for j in 1:N_opt
        C_mat[j, :] = mean(U_k[zone_members_opt[j], :], dims=1)
    end

    if verbose
        println("  STEP 3: Zone Clustering")
        println("  ───────────────────────")
        N_sorted = sort(N_candidates)
        for N in N_sorted
            worst_r2 = minimum(all_R2[N])
            marker = N == N_opt ? " ← selected" : ""
            @printf("    N=%2d: worst mode R²=%5.1f%%%s\n", N, 100*worst_r2, marker)
        end
        println("    → N = $N_opt zones")
        for j in 1:N_opt
            @printf("      Zone %d: points %s (%d points)\n",
                    j, string(zone_members_opt[j]), length(zone_members_opt[j]))
        end
        println()
    end

    # ── Step 5: Validate on training data ─────────────────────
    Z_sim = simulate_pod_rom(A_c, B_c, C_mat, t_data, Q_data)
    Z_true = zone_averages(X, zone_members_opt)
    zone_rmse = sqrt(mean((Z_sim .- Z_true) .^ 2))

    k_dim = size(A_c, 1)
    function sim_z!(dz, z, p, t)
        idx = clamp(searchsortedlast(t_data, t), 1, length(t_data))
        u = Q_data[idx]
        dz .= A_c * z .+ B_c[:, 1] .* u
    end
    prob_z = ODEProblem(sim_z!, zeros(k_dim), (t_data[1], t_data[end]))
    sol_z = solve(prob_z; saveat=t_data)
    X_recon = hcat([U_k * sol_z.u[i] for i in 1:length(sol_z.t)]...)'  # N_time × M
    spatial_rmse = sqrt(mean((X .- X_recon) .^ 2))

    if verbose
        println("  STEP 4: Validation")
        println("  ──────────────────")
        @printf("    Zone-level RMSE:  %6.3f K\n", zone_rmse)
        @printf("    Spatial RMSE:     %6.3f K\n", spatial_rmse)
        println()
        println("=" ^ 65)
    end

    result = DataDrivenPODResult(
        k, collect(S_vals), collect(cum_energy),
        A_c, B_c, C_mat, N_opt, zone_members_opt,
        zone_rmse, spatial_rmse,
    )

    if !isempty(output)
        mkpath(dirname(output))
        save_pod_rom(output, result)
        verbose && println("  Saved ROM → $output")
    end

    return result
end
