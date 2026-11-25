# Slide figure: the Euro NCAP CCRs prediction for the Sedan with AEB, the trigger
# threshold study, and one 50 km/h event with the nominal and a late threshold.
# Reads ccrs_cells.csv, ccrs_summary.toml, ccrs_sensitivity.csv/.toml and
# ccrs_traces.csv (written by ccrs_sweep.jl) and stops on any inconsistency.
# Writes ccrs_aeb.png and ccrs_aeb.pdf next to this file.
#
#   julia --project=validation/sedan_aeb_ccrs validation/sedan_aeb_ccrs/plot_ccrs.jl
using CairoMakie, DelimitedFiles, TOML, Printf
include(joinpath(@__DIR__, "ccrs_analysis.jl"))
using .CCRsAnalysis: load_protocol, read_cells_csv, score

const HERE = @__DIR__
const PROTOCOL = load_protocol()
const INK, MUTED, LINE, BG = colorant"#17181f", colorant"#5d6070", colorant"#dcdee6", colorant"#fbfbfd"
const NCAP = Dict(:green => colorant"#1f9d4c", :yellow => colorant"#f0c419", :orange => colorant"#f08a12",
    :brown => colorant"#7a6a1c", :red => colorant"#d9302a")
const ON_DARK = (:green, :brown, :red)
const SERIES = Dict("nominal_50kmh" => colorant"#5b3fd1", "late_a_on_9_50kmh" => colorant"#0d9488")
const MONO = "Menlo"

# --- data -----------------------------------------------------------------
cells = read_cells_csv(joinpath(HERE, "ccrs_cells.csv"); protocol = PROTOCOL)
summary = TOML.parsefile(joinpath(HERE, "ccrs_summary.toml"))
result = score(cells; protocol = PROTOCOL)
result.total_points == summary["score"]["total_points"] || error("ccrs_summary.toml disagrees with ccrs_cells.csv")
speeds = PROTOCOL["matrix"]["vut_speed_kmh"]
locations = sort(vcat(PROTOCOL["matrix"]["impact_location_extended_pct"], PROTOCOL["matrix"]["impact_location_standard_pct"]))
cell = Dict((c.v_test_kmh, c.impact_location_pct) => c for c in cells)
gap = Dict(k => summary["cells"][@sprintf("%02d_kmh_%+04d_pct", k[1], k[2])]["stop_gap_m"] for k in keys(cell))

sens_raw, sens_head = readdlm(joinpath(HERE, "ccrs_sensitivity.csv"), ','; header = true)
sc = Dict(Symbol(h) => j for (j, h) in enumerate(vec(sens_head)))
sens_toml = TOML.parsefile(joinpath(HERE, "ccrs_sensitivity.toml"))
a_ons = sort(unique(Float64.(sens_raw[:, sc[:a_on_mps2]])))
# The study table shows one cell per speed and threshold, which needs every impact
# location at that speed to share the colour and impact speed.
study = Dict{Tuple{Float64, Int}, Tuple{Symbol, Float64}}()
for a in a_ons, v in speeds
    rows = [i for i in axes(sens_raw, 1) if sens_raw[i, sc[:a_on_mps2]] == a && sens_raw[i, sc[:v_test_kmh]] == v]
    length(rows) == length(locations) || error("sensitivity: $(length(rows)) cells at a_on $a, $v km/h")
    cols = unique(Symbol.(sens_raw[rows, sc[:colour]]))
    vis = Float64.(sens_raw[rows, sc[:v_impact_kmh]])
    length(cols) == 1 && maximum(vis) - minimum(vis) < 0.01 ||
        error("sensitivity: impact locations differ at a_on $a, $v km/h")
    all(==(true), sens_raw[rows, sc[:valid]]) || error("sensitivity: invalid conduct at a_on $a, $v km/h")
    study[(a, v)] = (only(cols), vis[1])
end
for v in speeds, p in locations   # the nominal study column is the nominal grid
    c = cell[(Float64(v), Float64(p))]
    (c.colour, round(c.v_impact_kmh; digits = 3)) == (study[(5.0, v)][1], study[(5.0, v)][2]) ||
        error("sensitivity a_on 5 disagrees with ccrs_cells.csv at $v km/h, $p %")
end
points = Dict(a => sens_toml["thresholds"][@sprintf("a_on_%.1f", a)]["total_points"] for a in a_ons)

tr_raw, tr_head = readdlm(joinpath(HERE, "ccrs_traces.csv"), ','; header = true)
tc = Dict(Symbol(h) => j for (j, h) in enumerate(vec(tr_head)))
num(x) = x isa Number ? Float64(x) : nothing
traces = map(("nominal_50kmh", "late_a_on_9_50kmh")) do name
    rows = findall(==(name), tr_raw[:, tc[:case]])
    isempty(rows) && error("ccrs_traces.csv has no rows for $name")
    col(s) = Float64.(tr_raw[rows, tc[s]])
    (; name, t = col(:t_s), v = col(:v), gap = col(:gap), braking = col(:braking),
        t0 = num(tr_raw[rows[1], tc[:t0_s]]), taeb = num(tr_raw[rows[1], tc[:taeb_s]]),
        t_impact = num(tr_raw[rows[1], tc[:t_impact_s]]))
end
nominal, late = traces
isnothing(nominal.t_impact) || error("the nominal 50 km/h trace has an impact")
late_vi = study[(9.0, 50)][2]
nominal_gap = gap[(50.0, 50.0)]

# --- figure ---------------------------------------------------------------
set_theme!(Theme(
    fontsize = 16, textcolor = INK, backgroundcolor = BG,
    Axis = (backgroundcolor = BG, xgridcolor = LINE, ygridcolor = LINE,
        topspinevisible = false, rightspinevisible = false,
        leftspinecolor = LINE, bottomspinecolor = LINE, xtickcolor = LINE, ytickcolor = LINE,
        xticklabelcolor = MUTED, yticklabelcolor = MUTED, xlabelcolor = MUTED, ylabelcolor = MUTED,
        xlabelsize = 14, ylabelsize = 14, xticklabelsize = 13, yticklabelsize = 13,
        titlealign = :left, titlefont = :bold, titlesize = 17, titlecolor = INK,
        subtitlecolor = MUTED, subtitlesize = 13, titlegap = 6),
))
fig = Figure(size = (1600, 900), figure_padding = (36, 36, 22, 18))

head = fig[1, 1:3] = GridLayout()
Label(head[1, 1], "SEDAN AEB · EURO NCAP CCRs, PROTOCOL v1.2 (2026) · DYAD SIMULATION · $(length(cells)) CELLS";
    font = MONO, fontsize = 14, color = MUTED, halign = :left, tellwidth = false)
Label(head[2, 1], "AEB avoids the stationary target in all $(length(cells)) cells";
    font = :bold, fontsize = 34, halign = :left, tellwidth = false)
chip = head[1:2, 2] = GridLayout(valign = :top)
Box(chip[1, 1]; color = colorant"#e7f5ec", strokecolor = NCAP[:green], cornerradius = 8)
Label(chip[1, 1], result.req_aeb1 ? "Acceptance · REQ-AEB-1 met" : "Acceptance · REQ-AEB-1 not met";
    font = MONO, fontsize = 13, color = INK, padding = (12, 12, 6, 6))
rowgap!(head, 2)

# (a) Nominal grid.
cellsize = 1.0
ax1 = Axis(fig[2, 1]; title = "Predicted grid, nominal AEB",
    subtitle = "Cell: gap left at standstill. Columns −25 % and 125 % are the extended range.",
    xlabel = "Impact location [% of vehicle width from the right edge]", ylabel = "Test speed [km/h]",
    xticks = (1:length(locations), string.(locations)), yticks = (1:length(speeds), string.(speeds)),
    xgridvisible = false, ygridvisible = false, leftspinevisible = false, bottomspinevisible = false,
    xticksvisible = false, yticksvisible = false, limits = ((0.5, length(locations) + 0.5), (0.5, length(speeds) + 0.5)))
for (j, p) in enumerate(locations), (i, v) in enumerate(speeds)
    c = cell[(Float64(v), Float64(p))]
    extended = p in PROTOCOL["matrix"]["impact_location_extended_pct"]
    poly!(ax1, Rect2f(j - 0.46, i - 0.44, 0.92, 0.88); color = NCAP[c.colour],
        strokecolor = extended ? (INK, 0.5) : BG, strokewidth = extended ? 1.2 : 0, linestyle = extended ? :dash : :solid)
    label = c.contact ? @sprintf("%.1f km/h", c.v_impact_kmh) : @sprintf("%.2f m", gap[(Float64(v), Float64(p))])
    text!(ax1, j, i; text = label, align = (:center, :center), font = MONO, fontsize = 12,
        color = c.colour in ON_DARK ? :white : INK)
end
Label(fig[3, 1], @sprintf("Standard %.2f / %.2f · Extended %.2f / %.2f · Total %.2f points",
        result.standard_points, PROTOCOL["scoring"]["standard_range_points"], result.extended_points,
        PROTOCOL["scoring"]["extended_range_points"], result.total_points);
    font = MONO, fontsize = 13, halign = :left, tellwidth = false)

# (b) Trigger threshold study.
ax2 = Axis(fig[2, 2]; title = "How late can the AEB brake?",
    subtitle = "Request 0 at a_on, 1 at a_on + 3 m/s². Cell: impact speed [km/h].",
    xlabel = "Trigger threshold a_on [m/s²]", ylabel = "Test speed [km/h]",
    xticks = (1:length(a_ons), [@sprintf("%g", a) for a in a_ons]), yticks = (1:length(speeds), string.(speeds)),
    xgridvisible = false, ygridvisible = false, leftspinevisible = false, bottomspinevisible = false,
    xticksvisible = false, yticksvisible = false, limits = ((0.5, length(a_ons) + 0.5), (0.5, length(speeds) + 0.5)))
for (j, a) in enumerate(a_ons), (i, v) in enumerate(speeds)
    col, vi = study[(a, v)]
    poly!(ax2, Rect2f(j - 0.46, i - 0.44, 0.92, 0.88); color = NCAP[col],
        strokecolor = a == 5.0 ? INK : BG, strokewidth = a == 5.0 ? 1.5 : 0)
    col == :green || text!(ax2, j, i; text = @sprintf("%.1f", vi), align = (:center, :center),
        font = MONO, fontsize = 12, color = col in ON_DARK ? :white : INK)
end
Label(fig[3, 2], "Points: " * join([@sprintf("%.2f", points[a]) for a in a_ons], " · ") * " (outlined: nominal)";
    font = MONO, fontsize = 13, halign = :left, tellwidth = false)

# (c) One event at 50 km/h: speed against the gap to the target.
ax3 = Axis(fig[2, 3]; title = @sprintf("50 km/h: stops %.2f m short, or hits at %.1f km/h", nominal_gap, late_vi),
    subtitle = "Speed against gap to target. Dot: braking detected (TAEB).",
    xlabel = "Gap to target [m]", ylabel = "Speed [km/h]", xreversed = true,
    limits = ((-2, 45), (0, 55)), xticks = 0:10:40, yticks = 0:10:50)
vspan!(ax3, -2, 0; color = (NCAP[:red], 0.10))
text!(ax3, -0.3, 46; text = "Target", fontsize = 12, color = MUTED, align = (:right, :top))
for tr in traces
    k = findall(i -> tr.t[i] >= tr.t0 && (isnothing(tr.t_impact) || tr.t[i] <= tr.t_impact + 0.05), eachindex(tr.t))
    lines!(ax3, tr.gap[k], 3.6 .* tr.v[k]; color = SERIES[tr.name], linewidth = 2.5)
    ib = findfirst(>=(tr.taeb), tr.t)
    scatter!(ax3, [tr.gap[ib]], [3.6tr.v[ib]]; color = SERIES[tr.name], markersize = 11,
        strokecolor = BG, strokewidth = 2)
end
for (tr, label, side) in ((nominal, "a_on 5 (nominal)", :right), (late, "a_on 9 (late)", :left))
    ib = findfirst(>=(tr.taeb), tr.t)
    text!(ax3, tr.gap[ib], 3.6tr.v[ib] + 1.5; text = label, fontsize = 12, align = (side, :bottom))
end
let i = findlast(<=(late.t_impact), late.t)
    linesegments!(ax3, [Point2f(5.6, 10), Point2f(0.4, 3.6late.v[i] - 0.5)]; color = MUTED, linewidth = 1)
    text!(ax3, 6, 10; text = @sprintf("%.1f km/h at impact", late_vi), fontsize = 12, font = MONO,
        align = (:right, :center))
end

Label(fig[4, 1:3],
    "Model: SedanDemo Sedan in Dyad (kernel 3.5.0) with ABS, an ideal range sensor and an AEB that brakes on the deceleration " *
    "needed to stop 1.0 m short (DEC-12). Launch from rest, T0 at TTC 4 s.\n" *
    "Colours and points: Euro NCAP Crash Avoidance – Frontal Collisions v1.2, Fig. 5-1 and §5.3. REQ-AEB-1: full avoidance at 10 and 20 km/h (§5.1). " *
    "Threshold study: design study, no criterion.\n" *
    @sprintf("Data: ccrs_sweep.jl, commit %s%s. Simulation, not test data.", summary["commit"], summary["dirty"] ? " + uncommitted changes" : "");
    font = MONO, fontsize = 11, color = MUTED, halign = :left, justification = :left, tellwidth = false)

colsize!(fig.layout, 1, Relative(0.40))
colsize!(fig.layout, 2, Relative(0.25))
colgap!(fig.layout, 44)
rowgap!(fig.layout, 1, 8)
rowgap!(fig.layout, 2, 4)
rowgap!(fig.layout, 3, 14)

save(joinpath(HERE, "ccrs_aeb.png"), fig; px_per_unit = 2)
save(joinpath(HERE, "ccrs_aeb.pdf"), fig)
println("wrote ccrs_aeb.png and ccrs_aeb.pdf")
