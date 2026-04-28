"""
    SVDThermalNetworkAnalysis — Automated ROM construction from CFD spatial data.

Performs the complete pipeline:
1. SVD of spatial snapshots → discover number of dominant modes k
2. Energy-weighted k-means on mode shapes → zone count N and zone assignments
3. Construct and calibrate an N-zone tridiagonal thermal network against CFD data

Zone assignments are data-driven: spatial points are clustered by their
dynamic behavior (SVD mode shape similarity), producing unequal zones that
are finer where the temperature field varies most.

## Usage

```julia
using CFDReducedOrderModeling

result = SVDThermalNetworkAnalysis(data = "cfd_training_data.csv")

result.r.k                        # number of dominant modes
result.r.network.N                # number of zones
result.r.network.zone_members     # which spatial points in each zone
result.r.network.C_per_node       # calibrated per-node capacitance [J/K]
result.r.network.G                # calibrated inter-zone conductances [W/K]
result.r.network.Gc               # coolant conductance [W/K]
result.r.network.zone_rmse        # zone-level RMSE [K]
result.r.network.spatial_rmse     # spatial RMSE [K]

# Dyad analysis interface
artifacts(result)                              # list available artifacts
artifacts(result, :CalibratedNetwork)          # DataFrame of network parameters
artifacts(result, :SVDEnergy)                  # DataFrame of singular values
artifacts(result, :ZoneAssignments)            # DataFrame of zone membership
artifacts(result, :ZoneSizingSummary)          # DataFrame comparing candidate zone counts
artifacts(result, :RawResult)                  # raw SVDThermalNetworkResult struct
```
"""

using DyadInterface
using DyadInterface: AbstractAnalysisSpec, AbstractAnalysisSolution,
    AnalysisSolutionMetadata, ArtifactMetadata, ArtifactType

# ────────────────────────────────────────────────────────────
#  Result type (unchanged)
# ────────────────────────────────────────────────────────────
struct SVDThermalNetworkResult
    "Number of dominant spatial modes"
    k::Int
    "Singular values"
    singular_values::Vector{Float64}
    "Cumulative energy fraction"
    cumulative_energy::Vector{Float64}
    "Dominant mode shapes (M × k)"
    mode_shapes::Matrix{Float64}
    "Candidate zone counts evaluated"
    N_candidates::Vector{Int}
    "Spatial RMSE floor for each candidate N [K]"
    zone_rmse_floors::Vector{Float64}
    "Mode R² for each candidate N (Dict: N => Vector of R² per mode)"
    mode_R2::Dict{Int, Vector{Float64}}
    "Zone members for each candidate N (Dict: N => Vector{Vector{Int}})"
    zone_assignments::Dict{Int, Vector{Vector{Int}}}
    "Calibrated thermal network"
    network::CalibratedThermalNetwork
end

# ────────────────────────────────────────────────────────────
#  Dyad analysis spec
# ────────────────────────────────────────────────────────────
abstract type AbstractSVDThermalNetworkSpec <: AbstractAnalysisSpec end

"""
    SVDThermalNetworkSpec(; data, ...)

Specification for the SVD Thermal Network ROM analysis.
"""
@kwdef struct SVDThermalNetworkSpec <: AbstractSVDThermalNetworkSpec
    name::Symbol = :SVDThermalNetworkAnalysis
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
    maxiter::Int = 20000
    "If non-empty, save the calibrated network to this JSON path"
    output::String = ""
    "Print progress"
    verbose::Bool = true
end

# ────────────────────────────────────────────────────────────
#  Dyad analysis solution
# ────────────────────────────────────────────────────────────

"""
    SVDThermalNetworkSolution

Wraps `SVDThermalNetworkResult` in the Dyad `AbstractAnalysisSolution` interface.
Access the raw result via `result.r`.
"""
struct SVDThermalNetworkSolution <: AbstractAnalysisSolution
    spec::SVDThermalNetworkSpec
    r::SVDThermalNetworkResult
end

# ── Metadata ──────────────────────────────────────────────
const _SVD_NET_ARTIFACT_META = [
    ArtifactMetadata(
        :CalibratedNetwork, ArtifactType.DataFrame,
        "Calibrated Network",
        "Calibrated thermal network parameters: capacitances, conductances, and fit metrics."
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
        :ZoneSizingSummary, ArtifactType.DataFrame,
        "Zone Sizing Summary",
        "Comparison of candidate zone counts with RMSE floors and per-mode R² values."
    ),
    ArtifactMetadata(
        :RawResult, ArtifactType.Native,
        "Raw Result",
        "The underlying SVDThermalNetworkResult struct for programmatic access."
    ),
]

function DyadInterface.AnalysisSolutionMetadata(::SVDThermalNetworkSolution)
    AnalysisSolutionMetadata(_SVD_NET_ARTIFACT_META, Symbol[])
end

# ── Artifact generation ───────────────────────────────────
function DyadInterface.artifacts(sol::SVDThermalNetworkSolution, name::Symbol)
    r = sol.r
    net = r.network

    if name === :CalibratedNetwork
        rows = Dict{String, Any}[]
        push!(rows, Dict("parameter" => "N_zones", "value" => Float64(net.N)))
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
        for z in 1:net.N
            for pt in net.zone_members[z]
                push!(rows, Dict("zone" => z, "spatial_point" => pt,
                                 "zone_size" => length(net.zone_members[z])))
            end
        end
        return DataFrame(rows)

    elseif name === :ZoneSizingSummary
        rows = Dict{String, Any}[]
        for (i, N) in enumerate(r.N_candidates)
            worst_r2 = minimum(r.mode_R2[N])
            sizes = [length(m) for m in r.zone_assignments[N]]
            push!(rows, Dict(
                "N_zones" => N,
                "rmse_floor" => r.zone_rmse_floors[i],
                "worst_mode_R2" => worst_r2,
                "worst_mode_R2_pct" => 100.0 * worst_r2,
                "zone_sizes" => string(sizes),
                "selected" => N == net.N,
            ))
        end
        return DataFrame(rows)

    elseif name === :RawResult
        return r

    else
        error("Unknown artifact: $name. Available: $(first.(getfield.(_SVD_NET_ARTIFACT_META, :name)))")
    end
end

# ────────────────────────────────────────────────────────────
#  run_analysis
# ────────────────────────────────────────────────────────────
function DyadInterface.run_analysis(spec::SVDThermalNetworkSpec)
    r = _run_svd_network_pipeline(;
        data            = spec.data,
        spatial_cols    = spec.spatial_cols,
        input_col       = spec.input_col,
        time_col        = spec.time_col,
        reference_temp  = spec.reference_temp,
        energy_threshold = spec.energy_threshold,
        R2_threshold    = spec.R2_threshold,
        N_candidates    = spec.N_candidates,
        C0_per_node     = spec.C0_per_node,
        G0              = spec.G0,
        Gc0             = spec.Gc0,
        maxiter         = spec.maxiter,
        output          = spec.output,
        verbose         = spec.verbose,
    )
    return SVDThermalNetworkSolution(spec, r)
end

# ────────────────────────────────────────────────────────────
#  Convenience constructor
# ────────────────────────────────────────────────────────────
"""
    SVDThermalNetworkAnalysis(; data, ...) → SVDThermalNetworkSolution

Automated ROM construction: SVD → clustering → calibrated thermal network.
Returns an `SVDThermalNetworkSolution` implementing the Dyad analysis interface.

Access the raw result via `result.r`, or use `artifacts(result, :CalibratedNetwork)`.
"""
function SVDThermalNetworkAnalysis(; kwargs...)
    spec = SVDThermalNetworkSpec(; kwargs...)
    DyadInterface.run_analysis(spec)
end

# ────────────────────────────────────────────────────────────
#  Core pipeline
# ────────────────────────────────────────────────────────────
function _run_svd_network_pipeline(;
    data::String,
    spatial_cols::Union{Nothing, Vector{String}} = nothing,
    input_col::String = "Q_in",
    time_col::String = "time",
    reference_temp::Float64 = 300.0,
    energy_threshold::Float64 = 0.999,
    R2_threshold::Float64 = 0.88,
    N_candidates::Vector{Int} = [2, 3, 4, 5, 6, 8, 10],
    C0_per_node::Float64 = 80.0,
    G0::Float64 = 40.0,
    Gc0::Float64 = 10.0,
    maxiter::Int = 20000,
    output::String = "",
    verbose::Bool = true,
)
    # ── Step 0: Load data ────────────────────────────────────
    cfd = load_cfd_data(data; spatial_cols, input_col, time_col, reference_temp)
    t_data, Q_data, X, M = cfd.t_data, cfd.Q_data, cfd.X, cfd.M
    N_time = length(t_data)

    if verbose
        println("=" ^ 65)
        println("  SVD THERMAL NETWORK — AUTOMATED ROM CONSTRUCTION")
        println("=" ^ 65)
        println("  Spatial DOFs: $M,  Time steps: $N_time")
        println()
    end

    # ── Step 1: SVD → discover k ─────────────────────────────
    F = svd(X')  # M × N_time
    U_modes, S_vals = F.U, F.S
    cum_energy = cumsum(S_vals .^ 2) / sum(S_vals .^ 2)

    k = findfirst(e -> e >= energy_threshold, cum_energy)
    isnothing(k) && (k = length(S_vals))

    modes = U_modes[:, 1:k]  # M × k

    if verbose
        println("  STEP 1: SVD — Mode Discovery")
        println("  ─────────────────────────────")
        n_show = min(k + 2, length(S_vals))
        for i in 1:n_show
            marker = i == k ? " ← k" : ""
            @printf("    Mode %d: σ=%8.2f  energy=%7.4f%%%s\n",
                    i, S_vals[i], 100 * cum_energy[i], marker)
        end
        println("    Threshold $(100*energy_threshold)% → k = $k dominant modes")
        println()
    end

    # ── Step 2: Clustering → choose N and zone assignments ───
    N_opt, zone_members_opt, all_R2, all_members, rmse_floors =
        select_zone_count(modes, S_vals, N_candidates, X; threshold=R2_threshold)
    N_sorted = sort(N_candidates)

    if verbose
        println("  STEP 2: Zone Sizing — Energy-Weighted Clustering")
        println("  ─────────────────────────────────────────────────")
        header = "    N zones │ RMSE floor │"
        for j in 1:k
            header *= " Mode $j R² │"
        end
        header *= " Zone sizes      │ Selected"
        println(header)
        divider = "    ───────┼────────────┼"
        for _ in 1:k
            divider *= "──────────┼"
        end
        divider *= "─────────────────┼─────────"
        println(divider)
        for (i, N) in enumerate(N_sorted)
            sizes = [length(m) for m in all_members[N]]
            line = @sprintf("      %2d   │  %6.3f K  │", N, rmse_floors[i])
            for j in 1:k
                line *= @sprintf("  %5.1f%%  │", 100 * all_R2[N][j])
            end
            line *= @sprintf(" %-16s│", string(sizes))
            line *= N == N_opt ? "    ✓" : ""
            println(line)
        end
        println("    R² threshold: $(100*R2_threshold)% → N = $N_opt zones")
        println()
        println("    Zone assignments:")
        for z in 1:N_opt
            @printf("      Zone %d: points %s (%d points)\n",
                    z, string(zone_members_opt[z]), length(zone_members_opt[z]))
        end
        println()
    end

    # ── Step 3: Calibrate thermal network ────────────────────
    Z_target = zone_averages(X, zone_members_opt)

    if verbose
        println("  STEP 3: Calibrate $N_opt-Zone Thermal Network")
        println("  ─────────────────────────────────────────────")
        print("    Optimizing C_per_node, G₁₂…G_$(N_opt-1)$(N_opt), Gc ... ")
    end

    net = calibrate_thermal_network(zone_members_opt, t_data, Q_data, Z_target, X;
                                    C0_per_node=C0_per_node, G0=G0, Gc0=Gc0,
                                    maxiter=maxiter)

    if verbose
        println("done.")
        println()
        zone_sizes = [length(m) for m in zone_members_opt]
        @printf("    C_per_node = %6.1f J/K\n", net.C_per_node)
        for z in 1:N_opt
            @printf("      Zone %d: C = %.1f J/K (%d nodes × %.1f)\n",
                    z, net.C_per_node * zone_sizes[z], zone_sizes[z], net.C_per_node)
        end
        for i in 1:length(net.G)
            @printf("    G%d%d = %8.2f W/K\n", i, i+1, net.G[i])
        end
        @printf("    Gc  = %8.2f W/K\n", net.Gc)
        println()
        @printf("    Zone-level RMSE:  %6.3f K\n", net.zone_rmse)
        @printf("    Spatial RMSE:     %6.3f K\n", net.spatial_rmse)
        println()
        println("=" ^ 65)
    end

    if !isempty(output)
        mkpath(dirname(output))
        save_network(output, net)
        verbose && println("  Saved network → $output")
    end

    return SVDThermalNetworkResult(
        k, collect(S_vals), collect(cum_energy), modes,
        N_sorted, rmse_floors, all_R2, all_members, net,
    )
end
