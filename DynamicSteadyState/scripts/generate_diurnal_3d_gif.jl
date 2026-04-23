#=
generate_diurnal_3d_gif.jl

Generates the animated 3D isometric building visualization with strip charts
for the 24-hour diurnal simulation. Produces `building_diurnal_3d.gif`.

Run from the project root:
    julia --project scripts/generate_diurnal_3d_gif.jl

Requirements: CairoMakie, ColorSchemes, DynamicSteadyState, DyadInterface
=#

using Pkg
Pkg.activate(normpath(@__DIR__, ".."))

using DynamicSteadyState
using DyadInterface: symbolic_container
using CairoMakie
using ColorSchemes
using Printf

# ============================================================
#  1. Run the diurnal analysis and extract solution data
# ============================================================

println("Running DiurnalOperation analysis...")
result = DynamicSteadyState.DiurnalOperation()
sol = result.sol
model = symbolic_container(result)
println("  retcode: ", sol.retcode)

# ============================================================
#  2. Visual constants
# ============================================================

# Zone line colors (Z1=red, Z2=orange, Z3=dark gold)
const C_Z1 = RGBf(0.85, 0.15, 0.15)
const C_Z2 = RGBf(0.90, 0.55, 0.0)
const C_Z3 = RGBf(0.65, 0.58, 0.0)

# Temperature colormap range for 3D zone fill
const T_CMIN = 10.0   # °C
const T_CMAX = 22.0   # °C

# Colormap: blue (cold) → yellow (warm) → red (hot)
const TEMP_CMAP = cgrad(reverse(ColorSchemes.RdYlBu))

"""Map temperature (°C) to a color via the temperature colormap."""
function temp_color(T_celsius)
    frac = clamp((T_celsius - T_CMIN) / (T_CMAX - T_CMIN), 0.0, 1.0)
    return TEMP_CMAP[frac]
end

# ============================================================
#  3. Isometric projection
# ============================================================

# Project 3D world (x=east, y=north, z=up) to 2D screen.
# Camera looks from the south-east: Z3 (north) is front-left, Z1 (south) is back-right.
const ISO_ANGLE = π / 6  # 30°

function iso(x, y, z)
    sx = (x - y) * cos(ISO_ANGLE)
    sy = (x + y) * sin(ISO_ANGLE) + z
    return Point2f(sx, sy)
end

# ============================================================
#  4. Building geometry
# ============================================================

const BW = 6.0        # width (east-west, x-axis)
const BD = 8.0        # depth (north-south, y-axis)
const BH = 2.0        # height (z-axis)
const ZD = BD / 3     # zone depth

# Zone y-ranges (north=0, south=BD)
const Z3_Y0 = 0.0;    const Z3_Y1 = ZD       # Z3 North (front)
const Z2_Y0 = ZD;     const Z2_Y1 = 2 * ZD   # Z2 Core (middle)
const Z1_Y0 = 2 * ZD; const Z1_Y1 = 3 * ZD   # Z1 South (back)

# Ground plane padding
const GP = 1.5

# ============================================================
#  5. Drawing function (architectural outline style)
# ============================================================

function draw_building!(ax, T1, T2, T3, Q1, Q2, Q3)
    c1 = temp_color(T1); c2 = temp_color(T2); c3 = temp_color(T3)

    # Style constants
    wall_stroke = RGBf(0.55, 0.75, 0.90)    # light blue outline
    win_fill    = RGBAf(0.55, 0.78, 0.95, 0.30)
    win_stroke  = RGBf(0.45, 0.65, 0.85)
    roof_fill   = RGBAf(0.75, 0.88, 0.97, 0.06)
    hvac_c      = RGBf(0.15, 0.15, 0.45)    # dark blue HVAC
    hvac_top    = RGBf(0.22, 0.22, 0.55)
    part_color  = RGBf(0.60, 0.60, 0.75)    # partition dashes
    label_bg    = RGBAf(0.92, 0.95, 0.98, 0.90)
    transparent = RGBAf(0, 0, 0, 0)

    # --- Drawing helpers ---
    wall!(corners) = begin
        pts = [iso(c...) for c in corners]
        poly!(ax, pts; color = transparent, strokecolor = wall_stroke, strokewidth = 1.0)
    end
    filled!(corners; color, sc = wall_stroke, sw = 0.8) = begin
        pts = [iso(c...) for c in corners]
        poly!(ax, pts; color = color, strokecolor = sc, strokewidth = sw)
    end
    win!(corners) = begin
        pts = [iso(c...) for c in corners]
        poly!(ax, pts; color = win_fill, strokecolor = win_stroke, strokewidth = 0.8)
    end

    # ---- Ground plane ----
    filled!(
        [(-GP, -GP, -0.05), (BW + GP, -GP, -0.05),
         (BW + GP, BD + GP, -0.05), (-GP, BD + GP, -0.05)];
        color = RGBf(0.88, 0.85, 0.78),
        sc = RGBf(0.72, 0.69, 0.62), sw = 0.8)

    # ================================================================
    #  Z1 South (back) — drawn first (behind everything)
    # ================================================================
    # Floor with temperature tint
    filled!([(0, Z1_Y0, 0), (BW, Z1_Y0, 0), (BW, Z1_Y1, 0), (0, Z1_Y1, 0)];
        color = (c1, 0.30), sc = wall_stroke, sw = 0.5)
    # South exterior wall — outline only
    wall!([(0, Z1_Y1, 0), (BW, Z1_Y1, 0), (BW, Z1_Y1, BH), (0, Z1_Y1, BH)])
    # Window on south wall
    win!([(BW * 0.15, Z1_Y1, BH * 0.25), (BW * 0.85, Z1_Y1, BH * 0.25),
          (BW * 0.85, Z1_Y1, BH * 0.75), (BW * 0.15, Z1_Y1, BH * 0.75)])
    # East wall Z1 — outline only
    wall!([(BW, Z1_Y0, 0), (BW, Z1_Y1, 0), (BW, Z1_Y1, BH), (BW, Z1_Y0, BH)])
    # Window on east wall Z1
    win!([(BW, Z1_Y0 + ZD * 0.15, BH * 0.25), (BW, Z1_Y1 - ZD * 0.15, BH * 0.25),
          (BW, Z1_Y1 - ZD * 0.15, BH * 0.75), (BW, Z1_Y0 + ZD * 0.15, BH * 0.75)])

    # Partition 1-2 (dashed)
    pts_p12 = [iso(c...) for c in
        [(0, Z1_Y0, 0), (BW, Z1_Y0, 0), (BW, Z1_Y0, BH), (0, Z1_Y0, BH), (0, Z1_Y0, 0)]]
    lines!(ax, pts_p12; color = part_color, linewidth = 1.2, linestyle = :dash)

    # ================================================================
    #  Z2 Core (middle)
    # ================================================================
    filled!([(0, Z2_Y0, 0), (BW, Z2_Y0, 0), (BW, Z2_Y1, 0), (0, Z2_Y1, 0)];
        color = (c2, 0.30), sc = wall_stroke, sw = 0.5)
    wall!([(BW, Z2_Y0, 0), (BW, Z2_Y1, 0), (BW, Z2_Y1, BH), (BW, Z2_Y0, BH)])

    # Partition 2-3 (dashed)
    pts_p23 = [iso(c...) for c in
        [(0, Z2_Y0, 0), (BW, Z2_Y0, 0), (BW, Z2_Y0, BH), (0, Z2_Y0, BH), (0, Z2_Y0, 0)]]
    lines!(ax, pts_p23; color = part_color, linewidth = 1.2, linestyle = :dash)

    # ================================================================
    #  Z3 North (front) — drawn last
    # ================================================================
    filled!([(0, Z3_Y0, 0), (BW, Z3_Y0, 0), (BW, Z3_Y1, 0), (0, Z3_Y1, 0)];
        color = (c3, 0.30), sc = wall_stroke, sw = 0.5)
    wall!([(BW, Z3_Y0, 0), (BW, Z3_Y1, 0), (BW, Z3_Y1, BH), (BW, Z3_Y0, BH)])
    win!([(BW, Z3_Y0 + ZD * 0.15, BH * 0.25), (BW, Z3_Y1 - ZD * 0.15, BH * 0.25),
          (BW, Z3_Y1 - ZD * 0.15, BH * 0.75), (BW, Z3_Y0 + ZD * 0.15, BH * 0.75)])
    # North front wall — outline only
    wall!([(0, Z3_Y0, 0), (BW, Z3_Y0, 0), (BW, Z3_Y0, BH), (0, Z3_Y0, BH)])
    win!([(BW * 0.15, Z3_Y0, BH * 0.25), (BW * 0.85, Z3_Y0, BH * 0.25),
          (BW * 0.85, Z3_Y0, BH * 0.75), (BW * 0.15, Z3_Y0, BH * 0.75)])

    # ---- West walls (outline only) ----
    wall!([(0, Z1_Y0, 0), (0, Z1_Y1, 0), (0, Z1_Y1, BH), (0, Z1_Y0, BH)])
    wall!([(0, Z2_Y0, 0), (0, Z2_Y1, 0), (0, Z2_Y1, BH), (0, Z2_Y0, BH)])
    wall!([(0, Z3_Y0, 0), (0, Z3_Y1, 0), (0, Z3_Y1, BH), (0, Z3_Y0, BH)])

    # ---- Roofs (very translucent) ----
    filled!([(0, Z1_Y0, BH), (BW, Z1_Y0, BH), (BW, Z1_Y1, BH), (0, Z1_Y1, BH)];
        color = roof_fill, sc = wall_stroke, sw = 0.8)
    filled!([(0, Z2_Y0, BH), (BW, Z2_Y0, BH), (BW, Z2_Y1, BH), (0, Z2_Y1, BH)];
        color = roof_fill, sc = wall_stroke, sw = 0.8)
    filled!([(0, Z3_Y0, BH), (BW, Z3_Y0, BH), (BW, Z3_Y1, BH), (0, Z3_Y1, BH)];
        color = roof_fill, sc = wall_stroke, sw = 0.8)

    # ================================================================
    #  HVAC units (dark blue 3D blocks, labels above)
    # ================================================================
    hw = 0.8; hd = 0.7; hh = 0.9
    hx0 = BW - hw - 0.2
    for (y_ctr, Q_kw) in [
            (Z1_Y0 + ZD / 2, Q1),
            (Z2_Y0 + ZD / 2, Q2),
            (Z3_Y0 + ZD / 2, Q3)]
        x0 = hx0; x1 = x0 + hw
        y0_h = y_ctr - hd / 2; y1_h = y_ctr + hd / 2
        # Front face
        filled!([(x0, y0_h, 0), (x1, y0_h, 0), (x1, y0_h, hh), (x0, y0_h, hh)];
            color = hvac_c, sc = :gray25, sw = 0.8)
        # Right face
        filled!([(x1, y0_h, 0), (x1, y1_h, 0), (x1, y1_h, hh), (x1, y0_h, hh)];
            color = hvac_c, sc = :gray25, sw = 0.8)
        # Top face
        filled!([(x0, y0_h, hh), (x1, y0_h, hh), (x1, y1_h, hh), (x0, y1_h, hh)];
            color = hvac_top, sc = :gray25, sw = 0.8)
        # Power label above block
        text!(ax, iso(x0 + hw / 2, y_ctr, hh + 0.3);
            text = @sprintf("%.1f kW", Q_kw), fontsize = 10,
            align = (:center, :bottom), color = :gray25, font = :bold)
    end

    # ================================================================
    #  Zone labels (background box + name + temperature)
    # ================================================================
    bw2 = 1.3; bh2 = 0.55   # half-sizes in data coordinates
    for (y0, y1, T_val, label) in [
            (Z1_Y0, Z1_Y1, T1, "Z1 South"),
            (Z2_Y0, Z2_Y1, T2, "Z2 Core"),
            (Z3_Y0, Z3_Y1, T3, "Z3 North")]
        ctr = iso(BW / 2 - 1.0, (y0 + y1) / 2, BH * 0.35)
        box_pts = [
            ctr + Point2f(-bw2, -bh2), ctr + Point2f(bw2, -bh2),
            ctr + Point2f(bw2, bh2),   ctr + Point2f(-bw2, bh2)]
        poly!(ax, box_pts;
            color = label_bg, strokecolor = wall_stroke, strokewidth = 0.8)
        text!(ax, ctr + Point2f(0, 0.15);
            text = label, fontsize = 9,
            align = (:center, :bottom), color = :gray30)
        text!(ax, ctr + Point2f(0, -0.1);
            text = @sprintf("%.1f °C", T_val), fontsize = 12,
            align = (:center, :top), color = temp_color(T_val), font = :bold)
    end

    # ---- Partition labels ----
    text!(ax, iso(BW / 2 - 1.5, Z1_Y0, BH + 0.25);
        text = "part 1-2", fontsize = 8,
        align = (:center, :bottom), color = :gray50)
    text!(ax, iso(BW / 2 - 1.5, Z2_Y0, BH + 0.25);
        text = "part 2-3", fontsize = 8,
        align = (:center, :bottom), color = :gray50)

    # ---- Ground label ----
    text!(ax, iso(-0.8, (Z2_Y0 + Z2_Y1) / 2, 0.0);
        text = "Ground 10 °C", fontsize = 9,
        align = (:right, :center), color = RGBf(0.55, 0.50, 0.30))

    # ---- Compass rose ----
    co = iso(BW + 2.0, -0.5, 0.0)
    o0 = iso(0, 0, 0); arm = 0.7
    n_pt = co + Point2f(iso(0, arm, 0) - o0)
    s_pt = co + Point2f(iso(0, -arm, 0) - o0)
    e_pt = co + Point2f(iso(arm, 0, 0) - o0)
    w_pt = co + Point2f(iso(-arm, 0, 0) - o0)
    lines!(ax, [e_pt, w_pt]; color = :gray55, linewidth = 1.0)
    lines!(ax, [s_pt, n_pt]; color = :gray55, linewidth = 1.0)
    for (pt, lbl) in [(n_pt, "N"), (s_pt, "S"), (e_pt, "E"), (w_pt, "W")]
        text!(ax, pt; text = lbl, fontsize = 9,
              align = (:center, :center), color = :gray45)
    end
end

# ============================================================
#  6. Build figure and animate
# ============================================================

function generate_gif(;
        output_path = joinpath(@__DIR__, "..", "building_diurnal_3d.gif"),
        n_frames = 240,
        fps = 20)

    t_frames = range(0.0, 86400.0; length = n_frames)

    # --- Pre-compute all frame data ---
    println("Pre-computing $n_frames frames of solution data...")
    frame_data = map(t_frames) do t
        T1   = sol(t, idxs = model.building.z1.cap.T)  - 273.15
        T2   = sol(t, idxs = model.building.z2.cap.T)  - 273.15
        T3   = sol(t, idxs = model.building.z3.cap.T)  - 273.15
        Q1   = sol(t, idxs = model.hvac1.Q_delivered)   / 1000.0
        Q2   = sol(t, idxs = model.hvac2.Q_delivered)   / 1000.0
        Q3   = sol(t, idxs = model.hvac3.Q_delivered)   / 1000.0
        Tout = sol(t, idxs = model.outdoor_signal.y)    - 273.15
        occ  = sol(t, idxs = model.occ_schedule.occ)
        (; T1, T2, T3, Q1, Q2, Q3, Tout, occ, t_hr = t / 3600.0)
    end

    # --- Build figure layout ---
    fig = Figure(size = (1400, 900), backgroundcolor = :white)

    # Top: 3D isometric building
    ax_3d = Axis(fig[1, 1:2]; aspect = DataAspect(), backgroundcolor = :white)
    hidedecorations!(ax_3d)
    hidespines!(ax_3d)
    # Fix axis limits so the full building is always visible (not clipped by auto-limits)
    xlims!(ax_3d, -10.5, 9.0)
    ylims!(ax_3d, -2.5, 10.0)

    # Animated text labels
    time_label  = Observable("00:00")
    outdoor_lbl = Observable("Outdoor  -10.0 °C")
    occ_lbl     = Observable("Occupancy 0%")

    Label(fig[1, 1:2, Top()], time_label;
        fontsize = 22, font = :bold, halign = :center, padding = (0, 0, 8, 0))
    Label(fig[1, 1, TopLeft()], outdoor_lbl;
        fontsize = 14, color = RGBf(0.1, 0.4, 0.7),
        halign = :left, padding = (40, 0, 30, 0))
    Label(fig[1, 2, TopRight()], occ_lbl;
        fontsize = 14, color = :gray40,
        halign = :right, padding = (0, 40, 30, 0))

    # Temperature colorbar
    Colorbar(fig[1, 1, Bottom()];
        colormap = TEMP_CMAP, limits = (T_CMIN, T_CMAX),
        label = "", width = 150, height = 12, ticklabelsize = 9,
        ticks = [T_CMIN, T_CMAX],
        tickformat = values -> ["$(Int(v))°C" for v in values],
        vertical = false, halign = :left, flipaxis = false)

    # Bottom left: Zone Temperatures
    ax_temp = Axis(fig[2, 1];
        xlabel = "Time (hours)", ylabel = "Temperature (°C)",
        title = "Zone Temperatures",
        limits = (0, 24, 9, 24), xticks = 0:5:24, yticks = 9:3:24)

    hlines!(ax_temp, [21.0]; color = :gray70, linestyle = :dash,
            linewidth = 1.5, label = "Setpoint 21°C")

    # Animated line data (grow over time)
    t_line  = Observable(Float64[])
    T1_line = Observable(Float64[])
    T2_line = Observable(Float64[])
    T3_line = Observable(Float64[])

    lines!(ax_temp, t_line, T1_line; color = C_Z1, linewidth = 2, label = "Z1 South")
    lines!(ax_temp, t_line, T2_line; color = C_Z2, linewidth = 2, label = "Z2 Core")
    lines!(ax_temp, t_line, T3_line; color = C_Z3, linewidth = 2, label = "Z3 North")

    # Animated dot at current time
    dot_t  = Observable([0.0])
    dot_T1 = Observable([12.0])
    dot_T2 = Observable([12.0])
    dot_T3 = Observable([12.0])

    scatter!(ax_temp, dot_t, dot_T1; color = C_Z1, markersize = 8)
    scatter!(ax_temp, dot_t, dot_T2; color = C_Z2, markersize = 8)
    scatter!(ax_temp, dot_t, dot_T3; color = C_Z3, markersize = 8)

    axislegend(ax_temp; position = :lb, framevisible = true,
               labelsize = 10, patchsize = (20, 3))

    # Bottom right: HVAC Delivered Heating
    ax_hvac = Axis(fig[2, 2];
        xlabel = "Time (hours)", ylabel = "HVAC Power (kW)",
        title = "HVAC Delivered Heating",
        limits = (0, 24, 0, 10), xticks = 0:5:24, yticks = 0:2:10)

    Q1_line = Observable(Float64[])
    Q2_line = Observable(Float64[])
    Q3_line = Observable(Float64[])

    lines!(ax_hvac, t_line, Q1_line; color = C_Z1, linewidth = 2, label = "Z1 South")
    lines!(ax_hvac, t_line, Q2_line; color = C_Z2, linewidth = 2, label = "Z2 Core")
    lines!(ax_hvac, t_line, Q3_line; color = C_Z3, linewidth = 2, label = "Z3 North")

    dot_Q1 = Observable([9.1])
    dot_Q2 = Observable([2.3])
    dot_Q3 = Observable([8.4])

    scatter!(ax_hvac, dot_t, dot_Q1; color = C_Z1, markersize = 8)
    scatter!(ax_hvac, dot_t, dot_Q2; color = C_Z2, markersize = 8)
    scatter!(ax_hvac, dot_t, dot_Q3; color = C_Z3, markersize = 8)

    axislegend(ax_hvac; position = :rt, framevisible = true,
               labelsize = 10, patchsize = (20, 3))

    # Row sizing: 3D view gets more vertical space
    rowsize!(fig.layout, 1, Relative(0.52))

    # --- Accumulator arrays for growing strip chart lines ---
    t_acc  = Float64[]
    T1_acc = Float64[]
    T2_acc = Float64[]
    T3_acc = Float64[]
    Q1_acc = Float64[]
    Q2_acc = Float64[]
    Q3_acc = Float64[]

    # --- Animate ---
    println("Rendering $n_frames frames → $output_path")
    record(fig, output_path, 1:n_frames; framerate = fps) do i
        d = frame_data[i]

        # Grow strip chart data
        push!(t_acc, d.t_hr)
        push!(T1_acc, d.T1); push!(T2_acc, d.T2); push!(T3_acc, d.T3)
        push!(Q1_acc, d.Q1); push!(Q2_acc, d.Q2); push!(Q3_acc, d.Q3)

        t_line[]  = copy(t_acc)
        T1_line[] = copy(T1_acc)
        T2_line[] = copy(T2_acc)
        T3_line[] = copy(T3_acc)
        Q1_line[] = copy(Q1_acc)
        Q2_line[] = copy(Q2_acc)
        Q3_line[] = copy(Q3_acc)

        # Update dots
        dot_t[]  = [d.t_hr]
        dot_T1[] = [d.T1]; dot_T2[] = [d.T2]; dot_T3[] = [d.T3]
        dot_Q1[] = [d.Q1]; dot_Q2[] = [d.Q2]; dot_Q3[] = [d.Q3]

        # Update text annotations
        hrs  = floor(Int, d.t_hr)
        mins = round(Int, (d.t_hr - hrs) * 60)
        time_label[]  = @sprintf("%02d:%02d", hrs, mins)
        outdoor_lbl[] = @sprintf("Outdoor  %.1f °C", d.Tout)
        occ_lbl[]     = @sprintf("Occupancy %d%%", round(Int, d.occ * 100))

        # Redraw 3D building with updated zone colors
        empty!(ax_3d)
        draw_building!(ax_3d, d.T1, d.T2, d.T3, d.Q1, d.Q2, d.Q3)

        if i % 40 == 0 || i == n_frames
            println("  Frame $i / $n_frames  ($(time_label[]))")
        end
    end

    println("Done → $output_path")
    return output_path
end

# ============================================================
#  Run
# ============================================================

generate_gif()
