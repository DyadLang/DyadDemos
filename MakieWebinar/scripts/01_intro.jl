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

fig, ax, plt = plot(1:10)

#=
## Figure, Axis, Plot

What's this fig, ax, plt thing in my `plot`?

The **figure** is the top-level container for a window that might have multiple axes and plots.
It contains a `Scene`, which is the graphical description of what is to be drawn,
and a `GridLayout`, which allows `Block`s like axes, sliders, labels, etc. 
to be placed in a grid-based layout in the figure.

The **axis** is the 
=#

