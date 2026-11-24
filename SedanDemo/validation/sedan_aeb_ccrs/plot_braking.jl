# Slide figure: full braking from about 80 km/h with and without the brakes' slip
# limiters (ABS). Reads the traces and record written by brake_spike.jl and stops
# if the two disagree. Writes braking_abs.png and braking_abs.pdf next to this file.
#
#   julia --project=validation/sedan_aeb_ccrs validation/sedan_aeb_ccrs/plot_braking.jl
using CairoMakie, DelimitedFiles, TOML, Printf
include(joinpath(@__DIR__, "ccrs_analysis.jl"))
using .CCRsAnalysis: butter_filtfilt

const HERE = @__DIR__
const R_WHEEL = 0.3266                       # TMeasy wheel radius of SedanCorner
const MESH = joinpath(HERE, "..", "..", "assets", "sedan", "sedan_chassis_vis.obj")
const CASES = ("noabs_full", "abs_full")
const NAME = Dict("noabs_full" => "No ABS", "abs_full" => "ABS")

const INK, MUTED, LINE, BG = colorant"#17181f", colorant"#5d6070", colorant"#dcdee6", colorant"#fbfbfd"
const ROAD, SKID = colorant"#e9ebf1", colorant"#2b2d38"
const COLOR = Dict("noabs_full" => colorant"#e0692b", "abs_full" => colorant"#5b3fd1")
const MONO = "Menlo"

record = TOML.parsefile(joinpath(HERE, "brake_spike.toml"))
conduct = TOML.parsefile(joinpath(HERE, "protocol.toml"))["conduct"]

# --- traces -----------------------------------------------------------------
raw, header = readdlm(joinpath(HERE, "brake_traces.csv"), ','; header = true)
col = Dict(Symbol(h) => j for (j, h) in enumerate(vec(header)))
function load_case(name)
    rows = findall(==(name), raw[:, col[:case]])
    isempty(rows) && error("brake_traces.csv has no rows for $name")
    get(s) = Float64.(raw[rows, col[s]])
    t = get(:t_s)
    i0 = findfirst(==(0.0), t)
    i0 === nothing && error("$name: no sample at brake onset (t_s = 0)")
    v = get(:v_mps)
    istop = findfirst(i -> t[i] >= 0 && v[i] <= 0.1, eachindex(t))
    istop === nothing && error("$name: the car does not stop within the trace")
    x0 = get(:x_m)[i0]
    x = get(:x_m) .- x0
    corners = Dict(c => (x = get(Symbol("x_$(c)_m")), z = get(Symbol("z_$(c)_m")),
        w = get(Symbol("w_$(c)_radps"))) for c in ("fl", "fr", "rl", "rr"))
    # Deceleration: central difference of speed, then the protocol's acceleration
    # filter (phaseless Butterworth).
    a = similar(v)
    for i in eachindex(v)
        lo, hi = max(i - 1, firstindex(v)), min(i + 1, lastindex(v))
        a[i] = (v[hi] - v[lo]) / (t[hi] - t[lo])
    end
    decel = -butter_filtfilt(t, a; fc_hz = conduct["accel_filter_cutoff_hz"],
        poles = conduct["accel_filter_order"])
    return (; t, v, x, x0, z = get(:z_m), i0, istop, corners, decel)
end
data = Dict(name => load_case(name) for name in CASES)

# Numbers on the figure come from the record; the traces must reproduce them.
for name in CASES
    d, r = data[name], record["cases"][name]
    abs(3.6d.v[d.i0] - r["v0_kmh"]) < 0.01 || error("$name: onset speed differs from the record")
    abs(d.x[d.istop] - r["stop_distance_m"]) < 0.02 ||
        error("$name: stop distance $(d.x[d.istop]) m differs from the record $(r["stop_distance_m"]) m")
    for c in ("rl", "rr")
        w = d.corners[c].w
        moving = [i for i in eachindex(d.t) if d.t[i] >= 0 && d.v[i] > 2]
        ratio = minimum(abs(w[i]) * R_WHEEL / d.v[i] for i in moving)
        abs(ratio - r["min_wheel_speed_ratio"]["corner_$c"]) < 0.01 ||
            error("$name: rear $c wheel speed ratio $ratio differs from the record")
    end
    # The outline is drawn about the chassis frame origin, midway between the axles.
    cx = sum(d.corners[c].x[d.i0] for c in keys(d.corners)) / 4
    abs(cx - d.x0) < 0.05 || error("$name: wheel centers are not centered on the chassis frame origin")
end
stop = Dict(name => record["cases"][name]["stop_distance_m"] for name in CASES)
mfdd = Dict(name => record["cases"][name]["mfdd_mps2"] for name in CASES)
v0 = record["cases"]["abs_full"]["v0_kmh"]
v0 == record["cases"]["noabs_full"]["v0_kmh"] || error("the two cases start from different speeds")

# --- car outline from the chassis mesh ------------------------------------
# Top view in the chassis frame: mesh x is forward, mesh y is to the left (the
# screen's +y when the car drives toward +x), mesh z is up.
function hull(points)
    pts = sort(unique(points))
    length(pts) < 3 && return pts
    cross(o, a, b) = (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
    chain(seq) = foldl(seq; init = eltype(pts)[]) do h, p
        while length(h) >= 2 && cross(h[end - 1], h[end], p) <= 0
            pop!(h)
        end
        push!(h, p)
    end
    lower, upper = chain(pts), chain(reverse(pts))
    return vcat(lower[1:(end - 1)], upper[1:(end - 1)])
end
verts = [Tuple(parse.(Float64, split(l)[2:4])) for l in eachline(MESH) if startswith(l, "v ")]
const FRONT = maximum(first, verts)
body = hull([(v[1], v[2]) for v in verts])
glass = hull([(v[1], v[2]) for v in verts if v[3] > 1.02])
roof = hull([(v[1], v[2]) for v in verts if v[3] > 1.36])

# Place an outline at chassis displacement `dx` (from brake onset), lateral
# screen offset `y`, heading `θ`, with the front bumper at onset on x = 0.
place(shape, dx, y, θ) = [Point2f(dx - FRONT + px * cos(θ) - py * sin(θ),
    y + px * sin(θ) + py * cos(θ)) for (px, py) in shape]

# --- figure ---------------------------------------------------------------
set_theme!(Theme(
    fontsize = 17, textcolor = INK, backgroundcolor = BG,
    Axis = (backgroundcolor = BG, xgridcolor = LINE, ygridcolor = LINE,
        topspinevisible = false, rightspinevisible = false,
        leftspinecolor = LINE, bottomspinecolor = LINE, xtickcolor = LINE, ytickcolor = LINE,
        xticklabelcolor = MUTED, yticklabelcolor = MUTED, xlabelcolor = MUTED, ylabelcolor = MUTED,
        xlabelsize = 15, ylabelsize = 15, xticklabelsize = 14, yticklabelsize = 14,
        titlealign = :left, titlefont = :bold, titlesize = 18, titlecolor = INK,
        subtitlecolor = MUTED, subtitlesize = 14, titlegap = 6),
))
fig = Figure(size = (1600, 900), figure_padding = (36, 36, 22, 18))

# Header: eyebrow, claim, legend, label chip.
head = fig[1, 1:3] = GridLayout()
Label(head[1, 1], @sprintf("SEDAN · FULL BRAKING FROM %.1f km/h · DYAD SIMULATION", v0);
    font = MONO, fontsize = 14, color = MUTED, halign = :left, tellwidth = false)
Label(head[2, 1], @sprintf("ABS stops %.2f m shorter, with no wheel lock", stop["noabs_full"] - stop["abs_full"]);
    font = :bold, fontsize = 34, halign = :left, tellwidth = false)
chip = head[1:2, 2] = GridLayout(valign = :top)
Box(chip[1, 1]; color = colorant"#eef0f5", strokecolor = LINE, cornerradius = 8)
Label(chip[1, 1], "Comparison · no criterion"; font = MONO, fontsize = 13, color = MUTED,
    padding = (12, 12, 6, 6))
Legend(head[1:2, 3],
    [LineElement(color = COLOR[n], linewidth = 4) for n in CASES],
    ["No ABS: brake torque follows the command", "ABS: per-wheel slip limiter"];
    framevisible = false, orientation = :vertical, labelsize = 15, labelcolor = INK,
    patchsize = (26, 12), rowgap = 2, valign = :top, halign = :right)
colgap!(head, 24)
rowgap!(head, 2)

# Bird's-eye strip, to scale.
LANE = Dict("noabs_full" => 1.85, "abs_full" => -1.85)
strip = Axis(fig[2, 1:3]; aspect = DataAspect(), limits = ((-6.5, 33.5), (-3.7, 3.7)),
    xticks = 0:5:30, xlabel = "Distance from brake onset, front bumper [m]",
    yticksvisible = false, yticklabelsvisible = false, ygridvisible = false,
    xgridvisible = false, leftspinevisible = false, bottomspinecolor = LINE)
for name in CASES
    y0 = LANE[name]
    poly!(strip, Rect2f(-6.5, y0 - 1.75, 40, 3.5); color = ROAD)
end
hlines!(strip, [0.0]; color = :white, linewidth = 3, linestyle = (:dash, :dense))
vlines!(strip, [0.0]; color = MUTED, linewidth = 1.5, linestyle = :dash)
text!(strip, 0.2, 3.62; text = @sprintf("Brakes on at %.1f km/h", v0), font = MONO,
    fontsize = 13, color = MUTED, align = (:left, :top))

for name in CASES
    d, y0, c = data[name], LANE[name], COLOR[name]
    z0 = d.z[d.i0]
    # Skid marks: wheel-center track wherever the wheel turns at under 10 % of road speed.
    for k in ("fl", "fr", "rl", "rr")
        wc = d.corners[k]
        locked = [d.t[i] >= 0 && d.t[i] <= d.t[d.istop] &&
                  abs(wc.w[i]) * R_WHEEL < 0.1 * d.v[i] for i in eachindex(d.t)]
        any(locked) || continue
        pts = [locked[i] ? Point2f(wc.x[i] - d.x0 - FRONT, y0 - (wc.z[i] - z0)) : Point2f(NaN, NaN)
               for i in eachindex(d.t)]
        lines!(strip, pts; color = (SKID, 0.8), linewidth = 6)
    end
    # Outlines every 0.5 s, then the car at rest.
    rear = [(d.corners["rl"].x[i] + d.corners["rr"].x[i]) / 2 for i in eachindex(d.t)]
    front = [(d.corners["fl"].x[i] + d.corners["fr"].x[i]) / 2 for i in eachindex(d.t)]
    lat(k, i) = -(d.corners[k].z[i] - z0)
    heading(i) = atan((lat("fl", i) + lat("fr", i) - lat("rl", i) - lat("rr", i)) / 2, front[i] - rear[i])
    for tg in (0.0, 0.5, 1.0, 1.5)
        i = findfirst(>=(tg - 1e-9), d.t)
        poly!(strip, place(body, d.x[i], y0 - (d.z[i] - z0), heading(i));
            color = (c, 0.06), strokecolor = (c, 0.45), strokewidth = 1.2)
    end
    i = d.istop
    θ, yc = heading(i), y0 - (d.z[i] - z0)
    poly!(strip, place(body, d.x[i], yc, θ); color = c, strokecolor = (INK, 0.6), strokewidth = 1)
    poly!(strip, place(glass, d.x[i], yc, θ); color = (SKID, 0.55))
    poly!(strip, place(roof, d.x[i], yc, θ); color = c)
    text!(strip, -6.2, y0 + 1.6; text = NAME[name], font = :bold, fontsize = 16, align = (:left, :top))
    text!(strip, stop[name] + 0.25, y0; text = @sprintf("%.2f m", stop[name]), font = MONO,
        fontsize = 15, align = (:left, :center))
end
# The gap between the two stops.
let x1 = stop["abs_full"], x2 = stop["noabs_full"]
    linesegments!(strip, [Point2f(x1, LANE["abs_full"] + 0.95), Point2f(x1, 0.0),
            Point2f(x2, LANE["noabs_full"] - 0.95), Point2f(x2, 0.0)];
        color = (INK, 0.5), linewidth = 1, linestyle = :dot)
    linesegments!(strip, [Point2f(x1, -0.1), Point2f(x1, 0.1), Point2f(x2, -0.1), Point2f(x2, 0.1)];
        color = INK, linewidth = 1.5)
    linesegments!(strip, [Point2f(x1, 0.0), Point2f(x2, 0.0)]; color = INK, linewidth = 1.5)
    text!(strip, x2 + 0.3, 0.0; text = @sprintf("%.2f m shorter with ABS", x2 - x1), font = MONO,
        fontsize = 14, align = (:left, :center))
end
text!(strip, 11.0, LANE["noabs_full"] - 1.15; text = "Skid marks: rear wheels locked",
    fontsize = 14, color = MUTED, align = (:left, :center))
text!(strip, 11.0, LANE["abs_full"] - 1.15; text = "No skid marks: every wheel keeps turning",
    fontsize = 14, color = MUTED, align = (:left, :center))
text!(strip, 33.3, -3.6; text = "To scale · outlines every 0.5 s", fontsize = 13,
    color = MUTED, align = (:right, :bottom))

# (a) Speed against distance.
ax1 = Axis(fig[3, 1]; title = @sprintf("Stop distance: %.2f m → %.2f m", stop["noabs_full"], stop["abs_full"]),
    subtitle = "Speed against distance travelled",
    xlabel = "Distance from brake onset [m]", ylabel = "Speed [km/h]",
    limits = ((0, 28), (0, 85)), xticks = 0:5:25, yticks = 0:20:80)
for name in CASES
    d = data[name]
    r = d.i0:d.istop
    lines!(ax1, d.x[r], 3.6 .* d.v[r]; color = COLOR[name], linewidth = 2.5)
end

# (b) Rear-wheel braking slip against time.
ax2 = Axis(fig[3, 2]; title = "Rear-wheel slip: 100 % (locked) → 16 % at most",
    subtitle = "Both rear wheels, 1 − ωr/v",
    xlabel = "Time from brake onset [s]", ylabel = "Braking slip [%]",
    limits = ((0, 2.5), (-3, 105)), xticks = 0:0.5:2.5, yticks = 0:20:100)
hspan!(ax2, 8, 16; color = (COLOR["abs_full"], 0.12))
text!(ax2, 2.45, 18; text = "ABS slip band 8–16 %", fontsize = 13, color = MUTED, align = (:right, :bottom))
for name in CASES, k in ("rl", "rr")
    d = data[name]
    w = d.corners[k].w
    keep = [i for i in eachindex(d.t) if d.v[i] > 2]
    lines!(ax2, d.t[keep], [100 * (1 - abs(w[i]) * R_WHEEL / d.v[i]) for i in keep];
        color = COLOR[name], linewidth = 2)
end
text!(ax2, 2.45, 2; text = "Shown while v > 2 m/s", fontsize = 12, color = MUTED, align = (:right, :bottom))

# (c) Deceleration against time.
dmax = maximum(maximum(data[n].decel[data[n].i0:data[n].istop]) for n in CASES)
ax3 = Axis(fig[3, 3]; title = @sprintf("MFDD: %.3f → %.3f m/s²", mfdd["noabs_full"], mfdd["abs_full"]),
    subtitle = "Mean fully developed deceleration (dashed), 0.8 v0 to 0.1 v0",
    xlabel = "Time from brake onset [s]", ylabel = "Deceleration [m/s²]",
    limits = ((0, 2.5), (0, 2 * ceil(dmax / 2) + 2)), xticks = 0:0.5:2.5, yticks = 0:2:20)
for name in CASES
    d = data[name]
    r = d.i0:d.istop
    lines!(ax3, d.t[r], d.decel[r]; color = COLOR[name], linewidth = 2.5)
    # MFDD over 0.8 v0 to 0.1 v0.
    vb = d.v[d.i0]
    ib = findfirst(i -> d.t[i] >= 0 && d.v[i] <= 0.8vb, eachindex(d.t))
    ie = findfirst(i -> d.t[i] >= 0 && d.v[i] <= 0.1vb, eachindex(d.t))
    lines!(ax3, [d.t[ib], d.t[ie]], [mfdd[name], mfdd[name]]; color = COLOR[name],
        linewidth = 1.5, linestyle = :dash)
end
text!(ax3, 2.45, 0.4; text = "Filtered 10 Hz, 12-pole phaseless Butterworth", fontsize = 12,
    color = MUTED, align = (:right, :bottom))
text!(ax3, 0.42, 2 * ceil(dmax / 2) + 1.6;
    text = "Onset oscillation: the brake torque steps\ninstantly, with no pressure build-up", fontsize = 12,
    color = MUTED, align = (:left, :top))

# Footer: provenance.
Label(fig[4, 1:3],
    "Model: SedanDemo Sedan in Dyad (kernel 3.5.0), TMeasy tires, road μ 0.9, brakes 4 × 2000 N·m. " *
    "Brake command steps 0 → 1 at t = 0. A path follower holds a straight line.\n" *
    "ABS: the brake torque scale falls 1 → 0 as wheel slip rises 8 → 16 %. " *
    @sprintf("Data: brake_traces.csv (200 Hz) and brake_spike.toml, commit %s%s. Simulation, not test data.",
        record["commit"], record["dirty"] ? " + uncommitted changes" : "");
    font = MONO, fontsize = 11.5, color = MUTED, halign = :left, justification = :left, tellwidth = false)

rowsize!(fig.layout, 2, Auto(0.9))
rowgap!(fig.layout, 1, 6)
rowgap!(fig.layout, 3, 12)
colgap!(fig.layout, 40)

save(joinpath(HERE, "braking_abs.png"), fig; px_per_unit = 2)
save(joinpath(HERE, "braking_abs.pdf"), fig)
println("wrote braking_abs.png and braking_abs.pdf")
