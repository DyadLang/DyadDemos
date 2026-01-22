#=
# Introduction to Makie

Makie is a high-level, performant plotting library for Julia.

It has three "backends", which are different ways of rendering the plots.
- GLMakie: uses OpenGL, desktop only, fastest and most powerful.
- WGLMakie: uses WebGL in the browser, can be streamed over the web, slower, a bit more limited.
- CairoMakie: vector output to PDF, SVG, etc.  Mostly 2D only.

In this webinar, we will focus on GLMakie, but the principles are the same for the other backends.
=#

using GLMakie

fig, ax, plt = plot(1:11, 5:15)
lines!(ax, 1:11, 4:14)
lines(fig[1, 2], rand(10))
fig

#=
## Figure, Axis, Plot

What's this fig, ax, plt thing in my `plot`?

The **figure** is the top-level container for a window that might have multiple axes and plots.
It contains a `Scene`, which is the graphical description of what is to be drawn,
and a `GridLayout`, which allows `Block`s like axes, sliders, labels, etc. 
to be placed in a grid-based layout in the figure.

The **axis** is the container that holds plots and determines the mapping from data space to pixel space.
It also describes the axis ticks, grid lines, labels, etc.

The **plot** is the unit of visual content that is drawn.  
At the end of the day everything is "just a plot"
but organized into a tree of scenes, blocks, etc.
=#

# Let's create a simple plot:
fig, ax, plt = lines(rand(10))
# and then plot something else on top of that:
plt2 = scatter!(rand(10))
# You can also create a new axis in the figure, in a new column on the same row:
ax2 = Axis(fig[1, 2])
hm = heatmap!(ax2, rand(10, 10))
fig

#=
## Updating, observables, compute graph

Makie's "killer feature" is the ability to surgically update
a single attribute of a plot at a very low cost,
without having to recreate the entire figure.

In Makie, each attribute of a plot - color, marker size, positions, etc. - 
is an "observable" (this is not quite true now but effectively so).  

You can directly update any such attribute.
=#

fig, ax, plt = scatterlines(rand(10))

plt.color[] = RGBf(1, 0, 0)
plt.plots[1].color[] = RGBf(0, 1, 0)

# If you want to update multiple attributes at once,
# you can use `update!(plot, args...; kwargs...)`.
update!(plt, rand(10); color = RGBf(0, 0, 1))
update!(plt, rand(10); color = [RGBf(0, i/10, 1) for i in 1:10])

# There is a limitation to this in that you are restricted to
# the "input type" when updating - so a plot that initially has
# a single color, can't go to a color per point.

fig, ax, plt = scatterlines(1:10, rand(10); color = colorant"blue")
plt.color[] = RGBf(1, 0, 0) # fine
plt.color[] = rand(RGBf, 10) # error

# Let's update something "live":
# every second, we'll change the color of the plot.

for i in 1:10
    plt.color[] = RGBf(i/10, 1-i/10, 0)
    sleep(1)
end

# But this approach can be slow and a bit fragile.
# Let's instead use the tick event to update the plot.
fig, ax, plt = scatterlines(1:10, rand(10); color = colorant"blue")

current_dt = 0.0

listener = on(events(fig).tick) do tick_state
    # only update if the tick is a regular render tick or a skipped render tick
    dt = tick_state.delta_time
    global current_dt
    current_dt += dt
    if current_dt > 1.0
        plt.color[] = RGBf(rand(), rand(), rand())
        current_dt = 0.0
    end
end

# You can turn that listener off:
off(listener)

# and create a new listener, which changes the data instead:

listener = on(events(fig).tick) do tick_state
    # only update if the tick is a regular render tick or a skipped render tick
    dt = tick_state.delta_time
    global current_dt
    current_dt += dt
    if current_dt > 1.0
        update!(plt, rand(10) .* 10, rand(10))
        current_dt = 0.0
    end
end

off(listener)

#=
## Animations

Animations are dead simple with the Makie update system.
Just keep updating within a `record` loop.
=#

xs = LinRange(0, 10, 100)
f, a, p = lines(sin.(xs) .* xs, cos.(xs) .* xs)

@time record(f, "animation.mp4", 1:30; framerate = 10) do i
    if i <= 10
        p.color[] = rand(RGBf)
    elseif i <= 30
        xs = LinRange(0, (i-10)/2, 100)
        # to update two different attributes simultaneously,
        # use `update!(plot, args...; kwargs...)`.
        update!(p, sin.(xs) .* xs, cos.(xs) .* xs)
    end
end

#=
## Creating complex layouts

Let's see how to create a complex figure, with observable linkages, multiple axes, and more!
=#

fig = Figure()

title = Label(fig[1, 1:2], "Super Title"; fontsize = 24, font = :bold)
title.fontsize = 32

ax1 = Axis(fig[2, 1])
ax2 = Axis(fig[2, 2])
linkaxes!(ax1, ax2) # link both axis limits

control_gl = GridLayout(fig[3, 1:2])

sliders = SliderGrid(control_gl[1, 1:2], (; label = "Scale", range = 0.0:0.01:1.0, startvalue = 0.5))

menu_options = [("sin", sin), ("cos", cos), ("atan", atan)]
menu1 = Menu(control_gl[2, 1], options = menu_options)
menu2 = Menu(control_gl[2, 2], options = menu_options)

line1_points = Observable(Point2f[])
line2_points = Observable(Point2f[])

onany(menu1.selection, sliders.sliders[1].value) do selection, scale
    line1_points[] = [Point2f(x, selection(x * scale)) for x in 0:0.01:10]
end
onany(menu2.selection, sliders.sliders[1].value) do selection, scale
    line2_points[] = [Point2f(x, selection(x * scale)) for x in 0:0.01:10]
end

lines!(ax1, line1_points)
lines!(ax2, line2_points)

fig