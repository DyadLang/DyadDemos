# 3D animation of the CCRs test at 50 km/h, 50 % impact location: the nominal AEB
# (a_on 5 m/s²) beside a late trigger (a_on 9 m/s²). The sedan is drawn by
# MultibodyComponents' renderer from the simulated multibody state; the target is
# the sedan's body mesh placed with its rear on the target's rear plane. The late
# run freezes at first contact, because the model has no collision physics.
# Writes ccrs_aeb_50kmh.mp4 next to this file.
#
#   julia --project=validation/sedan_aeb_ccrs validation/sedan_aeb_ccrs/animate_ccrs.jl
using GLMakie
include(joinpath(@__DIR__, "ccrs_sweep.jl"))

# MultibodyComponents' renderer; it loads with Makie and brings its own mesh loader.
const RENDER = Base.get_extension(MultibodyComponents, :Render)
RENDER === nothing && error("MultibodyComponents' Render extension is not loaded")
const CHASSIS_MESH = joinpath(@__DIR__, "..", "..", "assets", "sedan", "sedan_chassis_vis.obj")
const V_KMH, P_PCT = 50, 50
const CASES = (("Nominal AEB, a_on 5 m/s²", 5.0), ("Late trigger, a_on 9 m/s²", 9.0))
const SLOWDOWN = 2.0      # playback at half speed
const FPS = 30
const SUBFRAMES = 4
const BG = RGBf(0.984, 0.984, 0.992)

function simulate(built)
    ssys, prob0, getter, derived = built
    return map(CASES) do (label, a_on)
        _, detail, run = run_cell(ssys, prob0, getter, derived, V_KMH, P_PCT, :standard;
            extra = (ssys.a_on => a_on,))
        (; label, run, detail, l_front = prob0.ps[ssys.l_front])
    end
end

# Ground, lane and markings at separate heights just below the tire contact plane
# y = 0, so their faces never coincide.
function road!(scene, x_target)
    mesh!(scene, Rect3f(Vec3f(-20, -0.08, -40), Vec3f(x_target + 120, 0.05, 80)); color = RGBf(0.80, 0.83, 0.78))
    mesh!(scene, Rect3f(Vec3f(-20, -0.05, -1.9), Vec3f(x_target + 120, 0.04, 3.8)); color = RGBf(0.40, 0.41, 0.44))
    for z in (-1.9, 1.75), x in -20:6:(x_target + 100)
        mesh!(scene, Rect3f(Vec3f(x, -0.012, z), Vec3f(3, 0.008, 0.15)); color = :white)
    end
end

# The target drawn with the chassis mesh: mesh x forward, y left, z up maps to the
# world's x forward, z right, y up; the mesh's rearmost point sits on the rear plane.
function target!(scene, x_target, z_target)
    m = RENDER.FileIO.load(CHASSIS_MESH)
    rear = minimum(p[1] for p in Makie.GeometryBasics.coordinates(m))
    t = mesh!(scene, m; color = RGBf(0.55, 0.57, 0.64))
    Makie.transform!(t; translation = Vec3f(x_target - rear, 0.219, z_target),
        rotation = Makie.qrotation(Vec3f(1, 0, 0), -π / 2))
end

# Writes the video with a full-frame shutter: each frame averages SUBFRAMES renders
# spread over its interval, so the spinning wheels blur as in a camera instead of
# strobing (they turn about 40° per frame at 50 km/h and half speed). The readouts
# are set once per frame so their digits do not blur.
function encode(fig, path, frames, scene!, hud!)
    dτ = step(frames)
    H, W = size(Makie.colorbuffer(fig))
    acc = zeros(Float32, 3, W, H)
    buf = Vector{UInt8}(undef, length(acc))
    exe = GLMakie.Makie.FFMPEG_jll.ffmpeg()
    open(`$exe -v error -y -f rawvideo -pix_fmt rgb24 -s $(W)x$(H) -r $FPS -i - -c:v libx264 -pix_fmt yuv420p -crf 20 $path`, "w") do io
        for τ in frames
            hud!(τ)
            fill!(acc, 0)
            for k in 1:SUBFRAMES
                scene!(τ + ((k - 0.5) / SUBFRAMES - 0.5) * dτ)
                add_frame!(acc, Makie.colorbuffer(fig))
            end
            buf .= round.(UInt8, clamp.(vec(acc) .* (255.0f0 / SUBFRAMES), 0, 255))
            write(io, buf)
        end
    end
end

function add_frame!(acc, img)
    for y in axes(img, 1), x in axes(img, 2)
        c = img[y, x]
        acc[1, x, y] += Float32(Makie.Colors.red(c))
        acc[2, x, y] += Float32(Makie.Colors.green(c))
        acc[3, x, y] += Float32(Makie.Colors.blue(c))
    end
    return acc
end

# Records the video to `path`, or with `still = τ` saves the frame at time τ as a PNG.
function animate(model, runs; path, still = nothing)
    any(r -> isnothing(r.run.tb), runs) && error("a run has no AEB braking to animate")
    # The renderer reads the model hierarchy, with names as in the solved system.
    ModelingToolkit.iscomplete(model) || (model = complete(model; flatten = false))
    t_start = minimum(r.run.t0 for r in runs) - 0.5
    t_end_of(r) = something(r.run.t_impact, r.run.t[end])
    t_stop = maximum(t_end_of(r) for r in runs) + 1.0
    frames = range(t_start, t_stop; step = 1 / (FPS * SLOWDOWN))

    fig = Figure(size = (1600, 900), backgroundcolor = BG)
    Label(fig[1, 1:2], "Euro NCAP CCRs at $V_KMH km/h, stationary target, $P_PCT % impact location";
        fontsize = 30, font = :bold, halign = :left, tellwidth = false, padding = (20, 0, 0, 10))
    Label(fig[2, 1:2], "Dyad multibody sedan with ABS, ideal range sensor and AEB · half speed · simulation, not test data";
        fontsize = 17, color = RGBf(0.36, 0.38, 0.44), halign = :left, tellwidth = false, padding = (20, 0, 6, 0))
    panels = map(enumerate(runs)) do (j, r)
        ls = LScene(fig[3, j]; show_axis = false)
        ls.scene.backgroundcolor[] = RGBAf(0.89, 0.92, 0.96, 1.0)
        ls.scene.clear[] = true
        cam3d!(ls.scene; center = false)
        ctx = RENDER.RenderContext(r.run.sol, ls.scene)
        RENDER.recursive_render!(ls.scene, model, ctx)
        vget = RENDER._finalize_render!(ctx)
        road!(ls.scene, r.run.x_target)
        target!(ls.scene, r.run.x_target, r.run.z_target)
        hud = Observable("")
        Label(fig[4, j], r.label; fontsize = 22, font = :bold, tellwidth = false)
        Label(fig[5, j], hud; fontsize = 18, font = "Menlo", tellwidth = false)
        banner, banner_color = Observable(" "), Observable(RGBf(0.12, 0.62, 0.30))
        Label(fig[6, j], banner; fontsize = 20, font = :bold, color = banner_color, tellwidth = false)
        (; r, ls, ctx, vget, hud, banner, banner_color)
    end
    rowsize!(fig.layout, 3, Relative(0.70))
    rowgap!(fig.layout, 2, 10)

    # Camera and readouts interpolate the 100 Hz record linearly, so they move as
    # smoothly as the car, which the renderer draws from the dense solution.
    lerp(ts, ys, t) = (i = clamp(searchsortedlast(ts, t), firstindex(ts), lastindex(ts) - 1);
        f = clamp((t - ts[i]) / (ts[i + 1] - ts[i]), 0, 1); ys[i] + f * (ys[i + 1] - ys[i]))
    function scene!(τ)
        for p in panels
            run = p.r.run
            tp = min(τ, t_end_of(p.r))
            p.ctx.vals[] = p.vget(tp)
            xc, zc = lerp(run.t, run.r.x_front, tp) - p.r.l_front, lerp(run.t, run.r.z_front, tp)
            update_cam!(p.ls.scene, cameracontrols(p.ls.scene), Vec3f(xc - 6.5, 2.0, zc - 5.0),
                Vec3f(xc + 6, 0.7, zc + 0.4), Vec3f(0, 1, 0))
        end
    end
    function hud!(τ)
        for p in panels
            run = p.r.run
            tp = min(τ, t_end_of(p.r))
            # Frozen at contact, the speed shown is the impact speed located on the dense solution.
            v_kmh = tp == run.t_impact ? p.r.detail["v_impact_kmh"] : 3.6lerp(run.t, run.r.v, tp)
            p.hud[] = @sprintf("t − T0 %5.2f s   %5.1f km/h   gap %5.1f m   brake %3.0f %%",
                tp - run.t0, v_kmh, max(lerp(run.t, run.r.gap, tp), 0.0), max(100lerp(run.t, run.r.braking, tp), 0.0))
            if !isnothing(run.t_impact) && τ >= run.t_impact
                p.banner_color[] = RGBf(0.85, 0.19, 0.16)
                p.banner[] = @sprintf("Contact at %.1f km/h", p.r.detail["v_impact_kmh"])
            elseif isnothing(run.t_impact) && τ >= run.t[end]
                p.banner[] = @sprintf("Stopped %.2f m short", p.r.detail["stop_gap_m"])
            else
                p.banner[] = " "
            end
        end
    end
    if still !== nothing
        hud!(still)
        scene!(still)
        save(path, fig)
    else
        encode(fig, path, frames, scene!, hud!)
    end
    return path
end

if abspath(PROGRAM_FILE) == @__FILE__
    built = build()
    @named model = SedanDemo.SedanCCRs()
    animate(model, simulate(built); path = joinpath(@__DIR__, "ccrs_aeb_50kmh.mp4"))
end
