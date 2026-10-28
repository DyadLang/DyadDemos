# Run with the FrictionBrakeDemo/docs environment, where Documenter is a dependency.
# Expected result: HTMLSizeThresholdError with Documenter's default size limits.
using Documenter

asset = normpath(@__DIR__, "..", "assets", "brake_caliper.svg")
fixture = mktempdir()
mkpath(joinpath(fixture, "src"))
write(joinpath(fixture, "src", "index.md"),
    "# FrictionBrake inline SVG\n\n```@raw html\n" * read(asset, String) * "\n```\n")
println("Inline SVG fixture: ", fixture, "; asset bytes: ", filesize(asset))
makedocs(;
    root=fixture,
    sitename="FrictionBrake SVG fixture",
    remotes=nothing,
    modules=Module[],
    pages=["index.md"],
    format=Documenter.HTML(),
)
