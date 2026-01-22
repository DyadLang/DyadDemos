# Flat Mesh Visualization for 2D Spatial Models
# 
# This script creates animations of 2D reaction-diffusion and FitzHugh-Nagumo
# models with FLAT mesh geometry (z=constant) where only the color changes
# to represent concentration values.

using MakieWebinar
using GLMakie
using GeometryBasics
using Statistics

# =============================================================================
# Mesh Creation Function
# =============================================================================

"""
    create_flat_mesh_for_frame(concentration_grid, N)

Create a flat triangulated mesh with constant z=0.
Vertices stay at fixed positions, only colors change.

# Arguments
- `concentration_grid`: N×N matrix of concentration values
- `N`: Grid size (N×N)

# Returns
- `mesh`: GeometryBasics.Mesh with all z-coordinates = 0
- `colors`: Vector of Float32 colors for each vertex
"""
function create_flat_mesh_for_frame(concentration_grid, N)
    # Create vertices with CONSTANT z=0 (flat mesh)
    vertices = Point3f[]
    for row in 1:N
        for col in 1:N
            x = Float32(col)
            y = Float32(row)
            z = 0.0f0  # CONSTANT - mesh stays flat
            push!(vertices, Point3f(x, y, z))
        end
    end
    
    # Create triangular faces connecting grid points
    faces = TriangleFace{Int}[]
    for row in 1:(N-1)
        for col in 1:(N-1)
            # Four corners of current cell
            idx_tl = (row - 1) * N + col      # top-left
            idx_tr = (row - 1) * N + col + 1  # top-right
            idx_bl = row * N + col            # bottom-left
            idx_br = row * N + col + 1        # bottom-right
            
            # Two triangles per cell
            push!(faces, TriangleFace(idx_tl, idx_tr, idx_bl))
            push!(faces, TriangleFace(idx_tr, idx_br, idx_bl))
        end
    end
    
    # Create color array from concentration (this is what changes)
    colors = Float32.(vec(concentration_grid))
    
    return GeometryBasics.Mesh(vertices, faces), colors
end

# =============================================================================
# Reaction-Diffusion Animation
# =============================================================================

println("Running reaction-diffusion analysis...")
result_rd = TestReactionGrowth20x20Transient()
sol_rd = result_rd.sol
N = 20

println("  Solved: ", length(sol_rd.t), " time points")

# Find concentration range across all time
println("  Analyzing concentration range...")
C_min = Inf
C_max = -Inf
for t in sol_rd.t
    C_vals = [sol_rd(t, idxs=Symbol("caps⸺$(i)₊C")) for i in 1:400]
    C_min = min(C_min, minimum(C_vals))
    C_max = max(C_max, maximum(C_vals))
end
println("  Concentration range: $(round(C_min, digits=2)) to $(round(C_max, digits=2))")

# Create figure
fig = Figure(size=(1600, 800))

ax_3d = Axis3(fig[1, 1], 
              title="Reaction-Diffusion: 3D View (Flat Mesh)",
              xlabel="X", ylabel="Y", zlabel="Z (constant)")

ax_2d = Axis(fig[1, 2],
             title="Reaction-Diffusion: 2D Heatmap",
             xlabel="X", ylabel="Y",
             aspect=DataAspect())

# Extract initial concentration
C_init = reshape([sol_rd(sol_rd.t[1], idxs=Symbol("caps⸺$(i)₊C")) for i in 1:400], N, N)

# Create mesh geometry ONCE (this never changes)
mesh_geom, colors_init = create_flat_mesh_for_frame(C_init, N)

println("  Mesh geometry created (FIXED throughout animation)")
println("    Z coordinates: ", unique([v[3] for v in coordinates(mesh_geom)]))

# Observable for colors
colors_obs = Observable(colors_init)

# Create plots
mesh_plot = mesh!(ax_3d, mesh_geom, color=colors_obs, colormap=:viridis, colorrange=(C_min, C_max))
heatmap_plot = heatmap!(ax_2d, 1:N, 1:N, C_init, colormap=:viridis, colorrange=(C_min, C_max))

# Set camera angle
ax_3d.elevation[] = π/6
ax_3d.azimuth[] = -π/4

# Colorbar
Colorbar(fig[1, 3], mesh_plot, label="Concentration")

println("  Recording animation...")
@time record(fig, "reaction_diffusion_flat.mp4", eachindex(sol_rd.t); framerate=15) do frame_idx
    t = sol_rd.t[frame_idx]
    
    # Extract concentration at this time
    C_grid = reshape([sol_rd(t, idxs=Symbol("caps⸺$(i)₊C")) for i in 1:400], N, N)
    
    # Get new colors (but DON'T create new mesh)
    _, new_colors = create_flat_mesh_for_frame(C_grid, N)
    
    # Update ONLY colors (geometry stays fixed)
    colors_obs[] = new_colors
    
    # Update heatmap
    heatmap_plot[3] = C_grid
    
    # Update title
    ax_3d.title = "Reaction-Diffusion: Flat Mesh (t = $(round(t, digits=2)) s)"
end

println("✓ Animation saved: reaction_diffusion_flat.mp4")

# =============================================================================
# FitzHugh-Nagumo Animation
# =============================================================================

println("\nRunning FitzHugh-Nagumo analysis...")
result_fhn = TestFHNWave20x20Transient()
sol_fhn = result_fhn.sol

println("  Solved: ", length(sol_fhn.t), " time points")

# Find activator (u) range across all time
println("  Analyzing activator range...")
u_min = Inf
u_max = -Inf
for t in sol_fhn.t
    u_vals = [sol_fhn(t, idxs=Symbol("caps⸺$(i)₊u")) for i in 1:400]
    u_min = min(u_min, minimum(u_vals))
    u_max = max(u_max, maximum(u_vals))
end
println("  Activator range: $(round(u_min, digits=2)) to $(round(u_max, digits=2))")

# Create figure
fig = Figure(size=(1600, 800))

ax_3d = Axis3(fig[1, 1], 
              title="FitzHugh-Nagumo Wave: 3D View (Flat Mesh)",
              xlabel="X", ylabel="Y", zlabel="Z (constant)")

ax_2d = Axis(fig[1, 2],
             title="FitzHugh-Nagumo Wave: 2D Heatmap",
             xlabel="X", ylabel="Y",
             aspect=DataAspect())

# Extract initial activator
u_init = reshape([sol_fhn(sol_fhn.t[1], idxs=Symbol("caps⸺$(i)₊u")) for i in 1:400], N, N)

# Create mesh geometry ONCE (this never changes)
mesh_geom, colors_init = create_flat_mesh_for_frame(u_init, N)

println("  Mesh geometry created (FIXED throughout animation)")
println("    Z coordinates: ", unique([v[3] for v in coordinates(mesh_geom)]))

# Observable for colors
colors_obs = Observable(colors_init)

# Create plots
mesh_plot = mesh!(ax_3d, mesh_geom, color=colors_obs, colormap=:thermal, colorrange=(u_min, u_max))
heatmap_plot = heatmap!(ax_2d, 1:N, 1:N, u_init, colormap=:thermal, colorrange=(u_min, u_max))

# Set camera angle
ax_3d.elevation[] = π/6
ax_3d.azimuth[] = -π/4

# Colorbar
Colorbar(fig[1, 3], mesh_plot, label="Activator (u)")

println("  Recording animation...")
@time record(fig, "fitzhugh_nagumo_flat.mp4", eachindex(sol_fhn.t); framerate=15) do frame_idx
    t = sol_fhn.t[frame_idx]
    
    # Extract activator at this time
    u_grid = reshape([sol_fhn(t, idxs=Symbol("caps⸺$(i)₊u")) for i in 1:400], N, N)
    
    # Get new colors (but DON'T create new mesh)
    _, new_colors = create_flat_mesh_for_frame(u_grid, N)
    
    # Update ONLY colors (geometry stays fixed)
    colors_obs[] = new_colors
    
    # Update heatmap
    heatmap_plot[3] = u_grid
    
    # Update title
    ax_3d.title = "FitzHugh-Nagumo Wave: Flat Mesh (t = $(round(t, digits=2)) s)"
end

println("✓ Animation saved: fitzhugh_nagumo_flat.mp4")

println("\n=== Summary ===")
println("Both animations created with:")
println("  - FIXED flat mesh geometry (z=0 constant)")
println("  - Only color attribute updated each frame")
println("  - Appropriate colorrange based on actual data")
println("  - Side-by-side 3D mesh + 2D heatmap views")
