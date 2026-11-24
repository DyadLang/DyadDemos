# CCRs measurement and scoring

`ccrs_analysis.jl` is a dependency-free Julia module for sampled CCRs traces and
prediction grids. It reads protocol values from [`protocol.toml`](protocol.toml).
The source is Euro NCAP [Crash Avoidance - Frontal Collisions, v1.2](https://cdn.euroncap.com/cars/assets/Euro_NCAP_Protocol_Crash_Avoidance_Frontal_Collisions_v1_2_220d87e28a.pdf):
definitions p.4; measurement sections 1.3/1.5; conduct section 4.3.2; entry
condition section 5.1; colour Figure 5-1; scoring sections 5.3.1/5.3.2.

This ten-line example creates a synthetic, all-green prediction grid:

```julia
include("validation/sedan_aeb_ccrs/ccrs_analysis.jl")
using .CCRsAnalysis
p = load_protocol()
m = p["matrix"]
cells = NamedTuple[]
for v in m["vut_speed_kmh"], loc in vcat(m["impact_location_standard_pct"], m["impact_location_extended_pct"])
    push!(cells, (; v_test_kmh=v, impact_location_pct=loc, range=loc in m["impact_location_standard_pct"] ? :standard : :extended, contact=false, v_impact_kmh=0.0, t0_s=0.0, taeb_s=nothing, colour=:green, valid=true, notes="synthetic"))
end
score(cells; protocol=p)
grid_svg("ccrs_grid.svg", cells; protocol=p)
```

It predicts 1.20 standard points, 0.15 extended points, and an eligible total of
1.35. It provides no evidence about the vehicle or controller.

## Integration contract

All traces use finite, one-based vectors with identical axes and strictly
increasing times. Ordinary arrays and views work; offset-indexed arrays raise a
clear indexing error. Times are seconds, positions meters, and trace speeds m/s.
`v_test` in `conduct_checks` is also m/s. Grid speeds and `colour` inputs are km/h.
World +x is travel and +z is right for the declared left-hand-drive VUT.

| Call | Result and boundary |
| --- | --- |
| `load_protocol(path)` | Parsed dictionary; rejects unsupported criterion syntax, malformed grids, and inconsistent color bounds. The only TOML reader. |
| `target_lateral_offset(p; w_vut)` | Rear-center lateral coordinate. This geometry helper accepts any finite percentage; grid functions validate protocol locations. |
| `profile_reach(x_front, z_front, yaw; z_target, halfwidth, w_target)` | Named tuple `x`, `overlap` for a straight front profile turned by the yaw: the greatest x of the part inside the target's closed lateral span, and whether that part exists. Yaw outside ±90° errors. |
| `impact(t, x_front, z, yaw, v; x_target, z_target, w_vut, w_target, inset)` | Named tuple `contact`, `t_impact`, `v_impact_kmh`. No contact gives `nothing` and zero. Bisects the linearly interpolated pose of each sample interval for the first forward plane crossing by `profile_reach` with overlapping closed spans, then interpolates time and speed there. |
| `test_start(t, x_front, v; x_target, ttc_s)` | T0 from a root of `x_target-x_front-ttc_s*v` on the interpolated segment. Missing or already-passed crossings error. |
| `butter_filtfilt(t, y; fc_hz, poles)` | Uniform-sample, forward/backward Butterworth result. Each pass has half the requested total poles. |
| `taeb(t, v; protocol=p)` | Interpolated onset time or `nothing` if detection never occurs. A record that starts below onset and later detects braking errors. |
| `conduct_checks(t, v, z_front_axle, throttle; v_test, t0, t_end_check, protocol=p)` | `valid`, plus named `speed`, `lateral`, `throttle`, and `sampling` results. Each has `pass` and measured values. |
| `colour(v_test_kmh, v_impact_kmh, contact; protocol=p)` | Symbol color. Green requires no contact. Contact at zero speed still receives a non-green color. Bounds include their upper endpoint. |
| `score(cells; protocol=p)` | Predicted points, raw points, extended fractions, `req_aeb1`, and eligible `total_points`. Requires a complete, unique, conduct-valid grid and consistent colors. |
| `write_cells_csv(path, cells; protocol=p)` / `read_cells_csv(path; protocol=p)` | Quoted CSV interchange; supports partial and conduct-invalid records for diagnostics. Missing TAEB is an empty field. |
| `grid_svg(path, cells; protocol=p)` | Standalone SVG; complete valid grid, with impact speeds, extended-column borders, color legend, entry result, and points. |

Each cell is a named tuple or an object with these properties, in CSV column order:

```text
v_test_kmh, impact_location_pct, range, contact, v_impact_kmh,
t0_s, taeb_s, colour, valid, notes
```

`range` is `:standard` or `:extended`; `colour` is a protocol color Symbol.
The corresponding strings also work. `contact` and `valid` must be Booleans.
`taeb_s` is a finite time or `nothing`; `notes` is text. Scoring needs only
speed, location, range, contact, impact speed, colour, and validity. When mixing
missing and measured TAEB, use `NamedTuple[]` or a suitably widened element
type for the cell vector.

## Numerical and scoring choices

- **Sampled contact:** linear interpolation implements the assigned helper.
  REQ-MEAS-1 also requires a root on the dense simulation solution. The scenario
  integrator must supply that refinement; sampled tests alone do not fulfill it.
  The profile is a straight line that turns with the vehicle yaw, with no body
  curvature, as declared in `requirements.md`. A shared lateral edge counts as contact.
- **TAEB:** differentiate speed with second-order finite differences, then apply
  the bilinear-transform filter as second-order sections. Use odd reflection
  and steady-state initial conditions. Forward/backward filtering attenuates
  the cutoff sinusoid to half amplitude and can precede a sharp physical onset.
  Short records remain susceptible to endpoint effects.
- **Conduct:** check both interpolated endpoints and every sample in the closed
  pre-AEB window. Report the signed speed and lateral deviations of largest
  magnitude. A 64-ULP-scale guard handles floating-point unit conversion at
  inclusive boundaries; it is a numerical guard, not an added physical tolerance.
  Sampling checks the largest time gap against the protocol minimum rate.
  Throttle must be exactly zero from the interpolated release threshold through
  the end, including any later speed recovery. If that threshold never occurs,
  release is not required. The caller must verify controller precedence and
  absence of other brake inputs; these cannot be inferred from the four channels.
- **Points:** `standard_points` and `extended_points` describe the color grid.
  Both are rounded to hundredths, following section 5.3; `*_raw_points` retain
  the unrounded calculation. Extended credit below the first configured step
  is zero. A failed REQ-AEB-1 sets `total_points` to zero; the component point
  fields remain visible for diagnosis. Invalid-conduct cells raise an error
  rather than contributing to points or reducing the grid denominator.
- **Criterion:** the speed limit is read from `criterion.case` using a strict
  parser for its existing `vut_speed_kmh <= … at every standard impact location`
  syntax. The limit is not repeated in code. An unsupported expression errors.

These are prediction and numerical-verification outputs. Robustness layers,
official verification tests, and vehicle/controller acceptance are separate.

Run the focused synthetic suite from the repository root:

```sh
julia +dyad-3.5.0 --project=validation/sedan_aeb_ccrs test/test_ccrs_analysis.jl
```

Every testset names its requirement. Numerical error bounds in the synthetic
oracles verify the implementation; they do not create vehicle acceptance limits.
`test/runtests.jl` includes this file in the package suite.
