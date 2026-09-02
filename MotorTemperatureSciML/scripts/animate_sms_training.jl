# Animated view of stochastic multiple shooting while it trains the TNN.
#
# Runs a coarsely segmented calibration (24 × 300 s segments so the individual
# segments are visible; ~10 min at 8 threads) with callbacks that snapshot the
# optimizer state, then re-solves every segment for each snapshot and renders
# two GIFs:
#
#   assets/sms_training.gif          — T_pm: measured trace, the 24 segment
#                                      predictions (gold = in the current
#                                      mini-batch, brown = dormant), red bars
#                                      for the continuity defects at junctions
#   assets/sms_training_detailed.gif — the same panel plus per-segment data
#                                      MSE, the training curves (AugLag
#                                      objective, data MSE, constraint norm,
#                                      gradient norm) and the per-junction
#                                      defect of each of the four states
#
# plus a PNG of the final frame of each. The snapshots are cached in
# assets/sms_snapshots.bin (gitignored); delete it or set FORCE_RETRAIN=1 to
# retrain.
#
# Run from the package root:
#   JULIA_NUM_THREADS=8 julia +dyad-3.3.0 --project scripts/animate_sms_training.jl

include("common.jl")
using DyadModelOptimizer: setup_problem, internal_params_part, split_timespan,
                          get_uuid, timespan, get_saveat
using SciMLBase: init, reinit!, solve!
using Setfield: @set
using Statistics: mean
using LinearAlgebra: norm
using Printf
using Base.Threads: nthreads
using ADTypes, ForwardDiff
using Serialization: serialize, deserialize
using CairoMakie
using Colors

# ── Configuration ────────────────────────────────────────────────────────────
# Coarser than the real training run (common.jl: 96 × 75 s) so each segment
# spans ~4 % of the plot; the batch/segment ratio (8/24) matches (32/96).
const ANIM_WINDOW_S    = 300.0
const ANIM_N_SEGMENTS  = round(Int, TRAIN_HORIZON_S / ANIM_WINDOW_S)   # 24
const ANIM_BATCH_SIZE  = 8
const ANIM_BLOCK_SIZE  = 2
const ANIM_INNER_LR    = 1e-3
const ANIM_INNER_EPOCHS = 33     # 3 batches/epoch → 99 inner steps per outer iteration
const ANIM_OUTER_ITERS = 10      # 990 steps; ends 2–3 °C off the plateau (README explains)
const CAPTURE_EVERY    = 10      # inner steps between snapshots → ~99 frames
const MAX_FRAMES       = 120
const FPS              = 8
const SAVEAT           = 0.5

const CACHE_PATH   = joinpath(ASSETS_DIR, "sms_snapshots.bin")
const GIF_SIMPLE   = joinpath(ASSETS_DIR, "sms_training.gif")
const GIF_DETAILED = joinpath(ASSETS_DIR, "sms_training_detailed.gif")

# Palette
const BG       = parse(Colorant, "#1F1F1F")
const GRID     = parse(Colorant, "#3A3A3A")
const TXT      = parse(Colorant, "#CCCCCC")
const TXT_DIM  = parse(Colorant, "#777777")
const TARGET_C = parse(Colorant, "#2EBF94")
const DORMANT  = parse(Colorant, "#B07458")
const SAMPLED  = parse(Colorant, "#FFD23F")
const DEFECT_C = parse(Colorant, "#FF4848")
const BAR_FILL = parse(Colorant, "#3FA9F5")
const STATE_COLORS = (parse(Colorant, "#FF6B6B"), parse(Colorant, "#FFC36B"),
                      parse(Colorant, "#6BCFFF"), parse(Colorant, "#6BFFA5"))

# ── Problem (same as training, coarser segmentation) ─────────────────────────
df         = load_profile(TRAIN_PROFILE)
df_h       = df[df.time .<= TRAIN_HORIZON_S, :]
sys        = build_system(TRAIN_PROFILE)
experiment = build_experiment(sys, df; name = "profile_$(TRAIN_PROFILE)_animation")
invprob    = build_invprob(experiment, build_search_space(sys))
T          = temperature_states(sys)
const UUID = get_uuid(experiment)

# ── Snapshot callbacks ───────────────────────────────────────────────────────
# Inner callback: fires once per Adam step with the full optimization state
# (search-space values + segment initial states), the current mini-batch and
# the gradient of the AugLag objective.
const SNAPSHOTS = NamedTuple[]
function snap_cb(state, loss)
    if state.iter % CAPTURE_EVERY == 0 && length(SNAPSHOTS) < MAX_FRAMES
        batch = try collect(state.p.indices[UUID]) catch; Int[] end
        gnorm = try norm(state.grad) catch; NaN end
        push!(SNAPSHOTS, (; iter = state.iter, u = copy(state.u), loss = float(loss),
            batch, grad_norm = float(gnorm)))
        length(SNAPSHOTS) % 10 == 0 &&
            @info "snapshot $(length(SNAPSHOTS))" iter = state.iter loss = round(loss; sigdigits = 4) grad_norm = round(gnorm; sigdigits = 4)
    end
    return false
end

# Outer callback: fires once per AugLag outer iteration; `state.original`
# carries the primal/dual residuals, the multipliers λ and the penalty ρ.
const OUTER_SNAPSHOTS = NamedTuple[]
function outer_cb(state, loss, args...)
    s = state.original
    push!(OUTER_SNAPSHOTS, (; outer_iter = state.iter, loss = float(loss),
        r_primal = float(s.r_primal), r_dual = float(s.r_dual), ρ = float(s.ρ),
        λ_norm = float(norm(s.λ))))
    @info "outer $(state.iter)" loss = round(loss; sigdigits = 4) ρ = round(s.ρ; sigdigits = 4) λ_norm = round(norm(s.λ); sigdigits = 4) r_primal = round(s.r_primal; sigdigits = 3)
    return false
end

alg = make_sms(; n_segments = ANIM_N_SEGMENTS, batch_size = ANIM_BATCH_SIZE,
    block_size = ANIM_BLOCK_SIZE, inner_lr = ANIM_INNER_LR,
    inner_epochs = ANIM_INNER_EPOCHS, outer_maxiters = ANIM_OUTER_ITERS,
    inner_kwargs = (; callback = snap_cb),
    # Run the whole budget: with 300 s segments the junction gaps close to the
    # 0.2 °C tolerance long before the data fit has settled, and the stopping
    # test only certifies continuity.
    auglag_kwargs = (; ϵ_primal = 1e-8),
    callback = outer_cb)   # forwarded to the AugLag solve by `calibrate`

# ── Train (or load the cached snapshots) ─────────────────────────────────────
if isfile(CACHE_PATH) && get(ENV, "FORCE_RETRAIN", "0") != "1"
    cached = deserialize(CACHE_PATH)
    append!(SNAPSHOTS, cached.snapshots)
    append!(OUTER_SNAPSHOTS, cached.outer_snapshots)
    @info "Loaded cached snapshots" path = CACHE_PATH n_frames = length(SNAPSHOTS) final_loss = cached.final_loss
else
    @info "Calibrating for the animation…" julia_threads = nthreads() ANIM_N_SEGMENTS ANIM_BATCH_SIZE ANIM_INNER_EPOCHS ANIM_OUTER_ITERS
    calres = calibrate(invprob, alg; adtype = AutoForwardDiff())
    @info "Calibration done" elapsed_s = round(calres.elapsed; digits = 1) retcode = calres.retcode n_frames = length(SNAPSHOTS)
    serialize(CACHE_PATH, (; snapshots = SNAPSHOTS, outer_snapshots = OUTER_SNAPSHOTS,
        final_loss = calres.original.objective, retcode = calres.retcode))
end
const N_FRAMES = length(SNAPSHOTS)

# ── Frame reconstruction ─────────────────────────────────────────────────────
# Each inner step only solves the sampled segments, so for every snapshot all
# 24 segments are re-solved here with one integrator that is `reinit!`ed per
# segment — the same pattern the algorithm's integrator pool uses. Stripping
# `initialization_data` is load-bearing: otherwise `reinit!` re-runs the
# model's initialization and overwrites the segment's own initial state.
const TIME_INTERVALS = split_timespan(alg, timespan(experiment), get_saveat(experiment))

function build_integrator(x)
    prob = setup_problem(experiment, invprob, x; tspan = TIME_INTERVALS[1])
    prob = @set prob.f.initialization_data = nothing
    return init(prob, Tsit5(); saveat = SAVEAT, abstol = 1e-6, reltol = 1e-6)
end

function solve_segment!(integ, x, k, u0_first)
    t0, t1 = TIME_INTERVALS[k]
    u0 = k == 1 ? u0_first : internal_params_part(alg, experiment, x, invprob)[:, k - 1]
    reinit!(integ, u0; t0, tf = t1)
    solve!(integ)
    sol = integ.sol
    return (; t = collect(sol.t), (Symbol(TARGET_COLS[i]) => sol[T[i]] .* MAX_TEMP for i in 1:4)...)
end

# Measured data per segment, for the per-segment MSE panel.
const MEAS_SEG = map(1:ANIM_N_SEGMENTS) do k
    t0, t1 = TIME_INTERVALS[k]
    m = (df_h.time .>= t0) .& (df_h.time .<= t1)
    (; t = df_h.time[m], (c => df_h[m, c] for c in TARGET_COLS)...)
end

function segment_mse(seg, meas)
    n = min(length(seg.pm), length(meas.pm))
    return [mean(abs2, seg[c][1:n] .- meas[c][1:n]) for c in TARGET_COLS]
end

@info "Reconstructing $N_FRAMES frames…"
const FRAMES = map(enumerate(SNAPSHOTS)) do (i, snap)
    integ = build_integrator(snap.u)
    u0_first = copy(integ.u)
    segs = [solve_segment!(integ, snap.u, k, u0_first) for k in 1:ANIM_N_SEGMENTS]
    mse = [segment_mse(segs[k], MEAS_SEG[k]) for k in 1:ANIM_N_SEGMENTS]   # per segment, 4 channels
    defects = [segs[k][c][end] - segs[k + 1][c][1] for c in TARGET_COLS, k in 1:(ANIM_N_SEGMENTS - 1)]
    i % 10 == 0 && @info "reconstructed $i / $N_FRAMES"
    (; segs, mse_pm = getindex.(mse, 1), data_mse = mean(mean.(mse)), defects,
        constraint_norm = norm(defects), loss = snap.loss, iter = snap.iter,
        batch = snap.batch, grad_norm = snap.grad_norm)
end

# ── Rendering ────────────────────────────────────────────────────────────────
set_theme!(theme_dark())
const AXIS_KW = (backgroundcolor = BG, xgridcolor = GRID, ygridcolor = GRID,
    xgridstyle = :dot, ygridstyle = :dot, leftspinecolor = GRID, rightspinecolor = GRID,
    topspinecolor = GRID, bottomspinecolor = GRID, xticklabelcolor = TXT_DIM,
    yticklabelcolor = TXT_DIM, xlabelcolor = TXT_DIM, ylabelcolor = TXT_DIM, titlecolor = TXT)

# Fixed y-limits from the data: early in training the predictions leave the
# physical range; letting them run off-axis is the honest picture.
const PM_YLIMS = let (lo, hi) = extrema(df_h.pm)
    (lo - 0.5 * (hi - lo), hi + 1.5 * (hi - lo))
end

function metric_panel!(parent, title, value_obs; fontsize = 26)
    g = GridLayout(parent)
    Label(g[1, 1], title; color = TXT_DIM, fontsize = 12, halign = :left, tellwidth = false)
    Label(g[2, 1], value_obs; color = TXT, fontsize, halign = :left, tellwidth = false)
    rowgap!(g, 4)
end

"""
The T_pm segments panel shared by both figures. Returns a closure that
updates the panel for frame `f`.
"""
function segments_panel!(ax)
    xlims!(ax, -0.02 * TRAIN_HORIZON_S, 1.02 * TRAIN_HORIZON_S)
    ylims!(ax, PM_YLIMS...)
    lines!(ax, df_h.time, df_h.pm; color = TARGET_C, linewidth = 2.5)
    seg_t   = [Observable(Float64[]) for _ in 1:ANIM_N_SEGMENTS]
    seg_y   = [Observable(Float64[]) for _ in 1:ANIM_N_SEGMENTS]
    seg_col = [Observable(DORMANT) for _ in 1:ANIM_N_SEGMENTS]
    seg_lw  = [Observable(1.8) for _ in 1:ANIM_N_SEGMENTS]
    for k in 1:ANIM_N_SEGMENTS
        lines!(ax, seg_t[k], seg_y[k]; color = seg_col[k], linewidth = seg_lw[k])
    end
    defect_segs = Observable(Point2f[])
    linesegments!(ax, defect_segs; color = DEFECT_C, linewidth = 3.5)
    scatter!(ax, defect_segs; color = DEFECT_C, markersize = 7)
    return function (f)
        fr = FRAMES[f]
        for k in 1:ANIM_N_SEGMENTS
            sampled = k in fr.batch
            seg_t[k][]   = fr.segs[k].t
            seg_y[k][]   = fr.segs[k].pm
            seg_col[k][] = sampled ? SAMPLED : DORMANT
            seg_lw[k][]  = sampled ? 3.0 : 1.8
        end
        defect_segs[] = reduce(vcat, (Point2f[(TIME_INTERVALS[k][2], fr.segs[k].pm[end]),
                                             (TIME_INTERVALS[k][2], fr.segs[k + 1].pm[1])]
                                     for k in 1:(ANIM_N_SEGMENTS - 1)))
    end
end

# ── Figure 1: segments only ──────────────────────────────────────────────────
fig1 = Figure(size = (900, 620), backgroundcolor = BG, figure_padding = 20)
ax1 = Axis(fig1[1, 1:3]; AXIS_KW..., xlabel = "t [s]", ylabel = "T_pm [°C]",
    xticklabelsize = 13, yticklabelsize = 13)
update_segments1! = segments_panel!(ax1)
step1 = Observable("0"); loss1 = Observable("0"); def1 = Observable("0")
metric_panel!(fig1[2, 1], "Inner step", step1)
metric_panel!(fig1[2, 2], "AugLag objective", loss1)
metric_panel!(fig1[2, 3], "Mean |defect| (°C)", def1)
Legend(fig1[3, 1:3],
    [LineElement(color = TARGET_C, linewidth = 3), LineElement(color = DORMANT, linewidth = 2),
     LineElement(color = SAMPLED, linewidth = 2.8), LineElement(color = DEFECT_C, linewidth = 3.5)],
    ["T_pm measured", "segment (dormant)", "segment (in current batch)", "continuity defect"];
    orientation = :horizontal, framevisible = false, labelcolor = TXT,
    backgroundcolor = :transparent, patchsize = (22, 10), colgap = 18)
rowsize!(fig1.layout, 1, Relative(0.72)); rowsize!(fig1.layout, 2, Relative(0.20)); rowgap!(fig1.layout, 4)

function set_frame1!(f)
    fr = FRAMES[f]
    update_segments1!(f)
    step1[] = string(fr.iter)
    loss1[] = @sprintf("%.3e", fr.loss)
    def1[]  = @sprintf("%.3f", mean(abs, fr.defects[1, :]))
end

# ── Figure 2: segments + training internals ──────────────────────────────────
fig2 = Figure(size = (1500, 1000), backgroundcolor = BG, figure_padding = 18)
ax_main = Axis(fig2[1, 1:2]; AXIS_KW..., xlabel = "t [s]", ylabel = "T_pm [°C]",
    title = "Segment predictions vs measured (T_pm)")
update_segments2! = segments_panel!(ax_main)
ax_mse = Axis(fig2[1, 3]; AXIS_KW..., xlabel = "segment", ylabel = "T_pm MSE [°C²]",
    title = "Per-segment fit")
ax_loss = Axis(fig2[2, 1:2]; AXIS_KW..., xlabel = "snapshot", ylabel = "value (log)",
    yscale = log10, title = "Training curves")
ax_def = Axis(fig2[2, 3]; AXIS_KW..., xlabel = "junction", ylabel = "defect [°C]",
    title = "Per-junction defect by state")

mse_y = Observable(zeros(ANIM_N_SEGMENTS))
barplot!(ax_mse, 1:ANIM_N_SEGMENTS, mse_y; color = BAR_FILL)
ylims!(ax_mse, 0, 1.05 * maximum(fr -> maximum(fr.mse_pm), FRAMES))

const SERIES = (
    (label = "AugLag objective", color = SAMPLED,  values = [fr.loss for fr in FRAMES]),
    (label = "data MSE (all segments)", color = TARGET_C, values = [fr.data_mse for fr in FRAMES]),
    (label = "‖constraint‖₂", color = DEFECT_C, values = [fr.constraint_norm / MAX_TEMP for fr in FRAMES]),
    (label = "‖∇ AugLag‖₂", color = parse(Colorant, "#6BCFFF"), values = [fr.grad_norm for fr in FRAMES]),
)
loss_x = Observable(Int[])
series_y = [Observable(Float64[]) for _ in SERIES]
for (s, y) in zip(SERIES, series_y)
    lines!(ax_loss, loss_x, y; color = s.color, linewidth = 2)
end
marker_x = Observable([1]); marker_y = Observable([SERIES[1].values[1]])
scatter!(ax_loss, marker_x, marker_y; color = SAMPLED, markersize = 8, strokecolor = TXT, strokewidth = 1)
xlims!(ax_loss, 1, N_FRAMES)
let vals = filter(v -> isfinite(v) && v > 0, reduce(vcat, [s.values for s in SERIES]))
    ylims!(ax_loss, 0.5 * minimum(vals), 2.0 * maximum(vals))
end
axislegend(ax_loss, [LineElement(color = s.color, linewidth = 2) for s in SERIES],
    [s.label for s in SERIES]; position = :rt, framevisible = false, labelcolor = TXT,
    backgroundcolor = (BG, 0.7), labelsize = 10, patchsize = (18, 6))

def_lines = [Observable(zeros(ANIM_N_SEGMENTS - 1)) for _ in 1:4]
for i in 1:4
    lines!(ax_def, 1:(ANIM_N_SEGMENTS - 1), def_lines[i]; color = STATE_COLORS[i], linewidth = 2)
    scatter!(ax_def, 1:(ANIM_N_SEGMENTS - 1), def_lines[i]; color = STATE_COLORS[i], markersize = 5)
end
hlines!(ax_def, [0]; color = GRID, linestyle = :dash)
let m = maximum(fr -> maximum(abs, fr.defects), FRAMES)
    ylims!(ax_def, -1.2m, 1.2m)
end

step2 = Observable("0"); loss2 = Observable("0"); mse2 = Observable("0")
metric_panel!(fig2[3, 1], "Inner step", step2; fontsize = 22)
metric_panel!(fig2[3, 2], "AugLag objective", loss2; fontsize = 22)
metric_panel!(fig2[3, 3], "Data MSE, all segments (°C²)", mse2; fontsize = 22)
Legend(fig2[4, 1:3],
    [LineElement(color = TARGET_C, linewidth = 3), LineElement(color = DORMANT, linewidth = 2),
     LineElement(color = SAMPLED, linewidth = 2.8), LineElement(color = DEFECT_C, linewidth = 3.5),
     [LineElement(color = STATE_COLORS[i], linewidth = 2.5) for i in 1:4]...],
    ["measured", "segment (dormant)", "segment (in batch)", "defect", TARGET_LABELS...];
    orientation = :horizontal, framevisible = false, labelcolor = TXT,
    backgroundcolor = :transparent, patchsize = (22, 10), colgap = 18)
rowsize!(fig2.layout, 1, Relative(0.42)); rowsize!(fig2.layout, 2, Relative(0.34))
rowsize!(fig2.layout, 3, Relative(0.14)); rowsize!(fig2.layout, 4, Relative(0.08)); rowgap!(fig2.layout, 6)

function set_frame2!(f)
    fr = FRAMES[f]
    update_segments2!(f)
    mse_y[] = fr.mse_pm
    loss_x[] = collect(1:f)
    for (s, y) in zip(SERIES, series_y)
        y[] = s.values[1:f]
    end
    marker_x[] = [f]; marker_y[] = [SERIES[1].values[f]]
    for i in 1:4
        def_lines[i][] = fr.defects[i, :]
    end
    step2[] = string(fr.iter)
    loss2[] = @sprintf("%.3e", fr.loss)
    mse2[]  = @sprintf("%.2f", fr.data_mse)
end

# ── Record ───────────────────────────────────────────────────────────────────
for (fig, set_frame!, path) in ((fig1, set_frame1!, GIF_SIMPLE), (fig2, set_frame2!, GIF_DETAILED))
    set_frame!(1)
    @info "Rendering" path n_frames = N_FRAMES fps = FPS
    record(fig, path, 1:N_FRAMES; framerate = FPS) do f
        set_frame!(f)
    end
    set_frame!(N_FRAMES)
    save(replace(path, ".gif" => "_final.png"), fig; px_per_unit = 2)
    @info "Done" path size_MB = round(filesize(path) / 2^20; digits = 1)
end
