module CCRsAnalysis

using TOML
using Printf

export load_protocol, target_lateral_offset, profile_reach, impact, test_start,
    butter_filtfilt, taeb, conduct_checks, colour, score, write_cells_csv, read_cells_csv,
    grid_svg

const PROTOCOL_PATH = joinpath(@__DIR__, "protocol.toml")
const CELL_FIELDS = (:v_test_kmh, :impact_location_pct, :range, :contact,
    :v_impact_kmh, :t0_s, :taeb_s, :colour, :valid, :notes)

function _finite(x, name)
    x isa Real && !(x isa Bool) && isfinite(x) ||
        throw(ArgumentError("$name must be a finite real number"))
    return Float64(x)
end

function _positive(x, name)
    value = _finite(x, name)
    value > 0 || throw(ArgumentError("$name must be positive"))
    return value
end

function _nonnegative(x, name)
    value = _finite(x, name)
    value >= 0 || throw(ArgumentError("$name must be nonnegative"))
    return value
end

function _series(t, channels...; min_samples = 2)
    t isa AbstractVector && all(y -> y isa AbstractVector, channels) ||
        throw(ArgumentError("time and channels must be vectors"))
    Base.require_one_based_indexing(t, channels...)
    all(y -> axes(y) == axes(t), channels) ||
        throw(DimensionMismatch("time and channel axes must match"))
    length(t) >= min_samples ||
        throw(ArgumentError("at least $min_samples samples are required"))
    all(x -> x isa Real && !(x isa Bool) && isfinite(x), t) &&
        all(y -> all(x -> x isa Real && !(x isa Bool) && isfinite(x), y), channels) ||
        throw(ArgumentError("time and channel samples must be finite real numbers"))
    all(>(0), diff(t)) || throw(ArgumentError("time must be strictly increasing"))
    return nothing
end

function _uniform_step(t)
    dt = Float64((last(t) - first(t)) / (length(t) - 1))
    tolerance = max(dt * 1e-9, 64eps(Float64) * maximum(abs, t))
    all(d -> abs(d - dt) <= tolerance, diff(t)) ||
        throw(ArgumentError("Butterworth filtering requires uniformly sampled time"))
    return dt
end

_lerp(a, b, f) = a + f * (b - a)

function _at(t, y, time)
    first(t) <= time <= last(t) ||
        throw(ArgumentError("requested time $time is outside the recorded interval"))
    i = searchsortedlast(t, time)
    i == lastindex(t) && return Float64(y[i])
    return _lerp(y[i], y[i + 1], (time - t[i]) / (t[i + 1] - t[i]))
end

function _criterion_speed(protocol)
    condition = protocol["criterion"]["case"]
    m = match(r"^vut_speed_kmh <= ([0-9]+(?:\.[0-9]+)?) at every standard impact location$", condition)
    isnothing(m) && throw(ArgumentError("unsupported criterion case: $condition"))
    return parse(Float64, m[1])
end

function _validate_protocol(p)
    for section in ("matrix", "conduct", "measurement", "criterion", "colour_bands", "scoring")
        haskey(p, section) || throw(ArgumentError("protocol is missing [$section]"))
    end
    matrix = p["matrix"]
    speeds = matrix["vut_speed_kmh"]
    standard = matrix["impact_location_standard_pct"]
    extended = matrix["impact_location_extended_pct"]
    for (name, values) in (("speeds", speeds), ("standard locations", standard),
            ("extended locations", extended))
        !isempty(values) && all(x -> x isa Real && isfinite(x), values) &&
            issorted(values) && allunique(values) ||
            throw(ArgumentError("protocol $name must be finite, nonempty, sorted and unique"))
    end
    isempty(intersect(standard, extended)) ||
        throw(ArgumentError("protocol standard and extended locations must be disjoint"))
    all(>(0), speeds) || throw(ArgumentError("protocol speeds must be positive"))
    threshold = _criterion_speed(p)
    any(<=(threshold), speeds) || throw(ArgumentError("criterion selects no grid cells"))
    order = p["colour_bands"]["order"]
    first(order) == "green" && allunique(order) ||
        throw(ArgumentError("color order must start with green and contain no duplicates"))
    for speed in speeds
        key = string(Int(speed))
        isinteger(speed) && haskey(p["colour_bands"], key) ||
            throw(ArgumentError("no color bands for protocol speed $speed"))
        bands = p["colour_bands"][key]
        all(c -> c in order, keys(bands)) || throw(ArgumentError("unknown protocol color"))
        bands["green"] == 0 || throw(ArgumentError("green bound must be zero"))
        bounds = [bands[c] for c in order if haskey(bands, c)]
        all(x -> x isa Real && isfinite(x) && x >= 0, bounds) &&
            all(>(0), diff(bounds)) || throw(ArgumentError("color bounds must increase from zero"))
    end
    for (threshold, credit) in p["scoring"]["extended_steps"]
        0 <= threshold <= 1 && 0 <= credit <= 1 ||
            throw(ArgumentError("extended steps must lie in [0, 1]"))
    end
    issorted(first.(p["scoring"]["extended_steps"])) ||
        throw(ArgumentError("extended step thresholds must be sorted"))
    return p
end

"""
    load_protocol(path = joinpath(@__DIR__, "protocol.toml"))

Read the protocol TOML and validate its grid, color bands, and criterion syntax.
All protocol thresholds used by the analysis come from the returned dictionary.
"""
load_protocol(path = PROTOCOL_PATH) = _validate_protocol(TOML.parsefile(path))

"""
    target_lateral_offset(p_pct; w_vut)

Return the target rear-center z coordinate in meters for a left-hand-drive VUT.
Positive z points right; `p_pct` is measured from the right edge (REQ-SCN-6).
"""
function target_lateral_offset(p_pct; w_vut)
    p = _finite(p_pct, "impact location")
    width = _positive(w_vut, "VUT width")
    return (0.5 - p / 100) * width
end

"""
    profile_reach(x_front, z_front, yaw; z_target, halfwidth, w_target)

Return `(x, overlap)` for a straight front profile of half-width `halfwidth`
centered at `(x_front, z_front)` and turned by `yaw` about +y, whose points sit
at `s .* (sin(yaw), cos(yaw))` from the center for `s` in `[-halfwidth, halfwidth]`.
`overlap` is true when part of the profile lies inside the target's closed
lateral span, and `x` is the greatest x of that part. Without overlap, `x`
belongs to the profile end nearest the span. The yaw must stay within ±90°.
"""
function profile_reach(x_front, z_front, yaw; z_target, halfwidth, w_target)
    sn, c = sincos(yaw)
    c > 0 || throw(ArgumentError("yaw $yaw rad is not within ±90°"))
    lo = (z_target - w_target / 2 - z_front) / c
    hi = (z_target + w_target / 2 - z_front) / c
    overlap = lo <= halfwidth && hi >= -halfwidth
    s_lo, s_hi = clamp(lo, -halfwidth, halfwidth), clamp(hi, -halfwidth, halfwidth)
    return (x = x_front + max(s_lo * sn, s_hi * sn), overlap)
end

"""
    impact(t, x_front, z, yaw, v; x_target, z_target, w_vut, w_target, inset)

Locate the first forward crossing of the stationary target's rear plane by the
front profile while it intersects the target's lateral span, including a shared
edge (REQ-MEAS-1). The profile is a straight line of width `w_vut - 2inset`
centered at `(x_front, z)` and turned by `yaw` (see `profile_reach`). Within a
sample interval, interpolate the pose linearly and bisect for the crossing of the
interpolated profile, whose reach is nonlinear in the yaw; interpolate time and
speed linearly at that crossing. Speeds in `v` are m/s. Return
`(contact, t_impact, v_impact_kmh)`; no contact gives `nothing` for time and zero
speed. The record must start with the profile on or before the target plane.
This sampled calculation does not replace dense-solution roots.
"""
function impact(t, x_front, z, yaw, v; x_target, z_target, w_vut, w_target, inset)
    _series(t, x_front, z, yaw, v)
    xt = _finite(x_target, "target x")
    zt = _finite(z_target, "target z")
    halfwidth = _positive(w_vut, "VUT width") / 2 - _nonnegative(inset, "profile inset")
    halfwidth > 0 || throw(ArgumentError("profile inset must be less than half the VUT width"))
    wt = _positive(w_target, "target width")
    all(>=(0), v) || throw(ArgumentError("speed samples must be nonnegative"))
    reach(xf, zf, yf) = profile_reach(xf, zf, yf; z_target = zt, halfwidth, w_target = wt)
    x_reach = [reach(x_front[i], z[i], yaw[i]).x for i in eachindex(t)]
    first(x_reach) <= xt || throw(ArgumentError("record starts beyond the target plane"))
    if first(x_reach) == xt && reach(first(x_front), first(z), first(yaw)).overlap
        return (contact = true, t_impact = Float64(first(t)), v_impact_kmh = 3.6first(v))
    end
    for i in firstindex(t):(lastindex(t) - 1)
        x_reach[i] < xt <= x_reach[i + 1] || continue
        posed(f) = reach(_lerp(x_front[i], x_front[i + 1], f), _lerp(z[i], z[i + 1], f),
            _lerp(yaw[i], yaw[i + 1], f))
        lo, hi = 0.0, 1.0
        for _ in 1:60
            f = (lo + hi) / 2
            posed(f).x < xt ? (lo = f) : (hi = f)
        end
        posed(hi).overlap || continue
        return (contact = true, t_impact = _lerp(t[i], t[i + 1], hi),
            v_impact_kmh = 3.6 * _lerp(v[i], v[i + 1], hi))
    end
    return (contact = false, t_impact = nothing, v_impact_kmh = 0.0)
end

"""
    test_start(t, x_front, v; x_target, ttc_s)

Return the first downward TTC crossing at `ttc_s` (REQ-SCN-3). Solve
`x_target - x_front - ttc_s*v = 0` on each linear sample segment, requiring
positive speed at the root. A missing crossing or a late record raises an error.
"""
function test_start(t, x_front, v; x_target, ttc_s)
    _series(t, x_front, v)
    xt = _finite(x_target, "target x")
    ttc = _positive(ttc_s, "start TTC")
    all(>=(0), v) || throw(ArgumentError("speed samples must be nonnegative"))
    residual = xt .- x_front .- ttc .* v
    first(residual) >= 0 || throw(ArgumentError("record starts after the requested TTC crossing"))
    first(residual) == 0 && first(v) > 0 && return Float64(first(t))
    for i in firstindex(t):(lastindex(t) - 1)
        if residual[i] >= 0 && residual[i + 1] <= 0 && residual[i] > residual[i + 1]
            f = residual[i] / (residual[i] - residual[i + 1])
            _lerp(v[i], v[i + 1], f) > 0 || continue
            return _lerp(t[i], t[i + 1], f)
        end
    end
    throw(ArgumentError("TTC never crosses the requested $ttc s at positive speed"))
end

function _filter_section(y, b0, b1, b2, a1, a2)
    result = similar(y)
    s1 = (1 - b0) * first(y)
    s2 = (b2 - a2) * first(y)
    for i in eachindex(y)
        result[i] = b0 * y[i] + s1
        s1 = b1 * y[i] - a1 * result[i] + s2
        s2 = b2 * y[i] - a2 * result[i]
    end
    return result
end

function _lowpass(y, k, order)
    result = y
    for j in 1:div(order, 2)
        damping = 2sinpi((2j - 1) / (2order))
        den = 1 + damping * k + k^2
        b = k^2 / den
        result = _filter_section(result, b, 2b, b,
            2(k^2 - 1) / den, (1 - damping * k + k^2) / den)
    end
    if isodd(order)
        b = k / (1 + k)
        result = _filter_section(result, b, b, 0.0, (k - 1) / (k + 1), 0.0)
    end
    return result
end

"""
    butter_filtfilt(t, y; fc_hz, poles)

Apply a bilinear-transform Butterworth low-pass of order `poles/2` forward and
backward (REQ-MEAS-2). `poles` must be a positive even integer, and `fc_hz`
must be below Nyquist. The paired gain at `fc_hz` is 0.5. Use odd reflection
padding of `min(length(y)-1, 3*(poles/2+1))` samples and steady-state section
initialization. Inputs require uniform time and at least three samples.
"""
function butter_filtfilt(t, y; fc_hz, poles)
    _series(t, y; min_samples = 3)
    dt = _uniform_step(t)
    fc = _positive(fc_hz, "filter cutoff")
    poles isa Integer && !(poles isa Bool) && poles > 0 && iseven(poles) ||
        throw(ArgumentError("filter poles must be a positive even integer"))
    fc < 1 / (2dt) || throw(ArgumentError("filter cutoff must be below Nyquist"))
    order = div(poles, 2)
    n = length(y)
    pad = min(n - 1, 3(order + 1))
    data = Float64.(y)
    padded = vcat(2first(data) .- data[(pad + 1):-1:2], data,
        2last(data) .- data[(n - 1):-1:(n - pad)])
    k = tanpi(fc * dt)
    forward = _lowpass(padded, k, order)
    backward = reverse(_lowpass(reverse(forward), k, order))
    all(isfinite, backward) || throw(ArgumentError("filter produced non-finite output"))
    return backward[(pad + 1):(pad + n)]
end

"""
    taeb(t, v; protocol)

Differentiate speed (m/s) with second-order finite differences and apply the
protocol's acceleration filter. Return the first interpolated onset-threshold
crossing before the first sample below the detection threshold, or `nothing`
when braking is not detected (REQ-MEAS-2). Raise an error if onset precedes the
record. Symmetric filtering can move the reported onset ahead of a sharp input.
"""
function taeb(t, v; protocol)
    _series(t, v; min_samples = 3)
    dt = _uniform_step(t)
    all(>=(0), v) || throw(ArgumentError("speed samples must be nonnegative"))
    acceleration = zeros(length(v))
    acceleration[1] = (-3v[1] + 4v[2] - v[3]) / (2dt)
    acceleration[end] = (3v[end] - 4v[end - 1] + v[end - 2]) / (2dt)
    for i in 2:(length(v) - 1)
        acceleration[i] = (v[i + 1] - v[i - 1]) / (2dt)
    end
    conduct = protocol["conduct"]
    filtered = butter_filtfilt(t, acceleration;
        fc_hz = conduct["accel_filter_cutoff_hz"], poles = conduct["accel_filter_order"])
    measurement = protocol["measurement"]
    onset = measurement["taeb_onset_mps2"]
    detect = measurement["taeb_detect_mps2"]
    detect < onset || throw(ArgumentError("TAEB detection threshold must be below onset threshold"))
    hit = findfirst(<(detect), filtered)
    isnothing(hit) && return nothing
    first(filtered) >= onset || throw(ArgumentError("TAEB onset precedes the recorded interval"))
    for i in 1:(hit - 1)
        if filtered[i] >= onset && filtered[i + 1] < onset
            f = (onset - filtered[i]) / (filtered[i + 1] - filtered[i])
            return _lerp(t[i], t[i + 1], f)
        end
    end
    throw(ArgumentError("detected AEB has no recorded onset crossing"))
end

"""
    conduct_checks(t, v, z_front_axle, throttle;
        v_test, t0, t_end_check, protocol)

Check speed (m/s) and front-axle lateral position on the closed pre-AEB window
and throttle from the first protocol speed-drop crossing through the record's
end (REQ-SCN-4/5). Interpolate window endpoints and the release instant. Report
signed worst deviations and the largest sample interval (REQ-MEAS-3). `valid`
requires speed, lateral, throttle, and minimum sampling rate checks to pass.
`v_test` is m/s; throttle is in [0, 1]. Missing release is vacuously compliant.
"""
function conduct_checks(t, v, z_front_axle, throttle;
        v_test, t0, t_end_check, protocol)
    _series(t, v, z_front_axle, throttle)
    reference = _positive(v_test, "test speed")
    start = _finite(t0, "test start time")
    finish = _finite(t_end_check, "conduct end time")
    first(t) <= start <= finish <= last(t) ||
        throw(ArgumentError("conduct window must lie inside the record with start <= end"))
    all(>=(0), v) || throw(ArgumentError("speed samples must be nonnegative"))
    all(x -> 0 <= x <= 1, throttle) || throw(ArgumentError("throttle must lie in [0, 1]"))
    window = [start; [time for time in t if start < time < finish]; finish]
    speed_errors = [3.6 * (_at(t, v, time) - reference) for time in window]
    lateral_errors = [_at(t, z_front_axle, time) for time in window]
    speed_worst = speed_errors[argmax(abs.(speed_errors))]
    lateral_worst = lateral_errors[argmax(abs.(lateral_errors))]
    limits = protocol["conduct"]
    # Subtracting speeds and converting units can move an exact boundary by a few ULPs.
    speed_roundoff = 64eps(Float64) * max(1, 3.6reference)
    lateral_roundoff = 64eps(Float64) * max(1, maximum(abs, lateral_errors))
    speed_ok = abs(speed_worst) <= limits["vut_speed_tolerance_kmh"] + speed_roundoff
    lateral_ok = abs(lateral_worst) <= limits["vut_lateral_deviation_m"] + lateral_roundoff
    release_speed = reference - limits["accelerator_release_drop_kmh"] / 3.6
    release = nothing
    if first(v) <= release_speed
        release = Float64(first(t))
    else
        for i in 1:(length(t) - 1)
            if v[i] > release_speed >= v[i + 1]
                f = (v[i] - release_speed) / (v[i] - v[i + 1])
                release = _lerp(t[i], t[i + 1], f)
                break
            end
        end
    end
    max_throttle = isnothing(release) ? 0.0 : maximum(
        [_at(t, throttle, release); [throttle[i] for i in eachindex(t) if t[i] > release]])
    throttle_ok = max_throttle == 0
    max_interval = maximum(diff(t))
    allowed_interval = 1 / limits["sample_rate_min_hz"]
    sampling_ok = max_interval <= allowed_interval + 64eps(Float64) * max(1, maximum(abs, t))
    return (valid = speed_ok && lateral_ok && throttle_ok && sampling_ok,
        speed = (pass = speed_ok, worst_kmh = speed_worst),
        lateral = (pass = lateral_ok, worst_m = lateral_worst),
        throttle = (pass = throttle_ok, release_s = release, maximum_after_release = max_throttle),
        sampling = (pass = sampling_ok, max_interval_s = max_interval))
end

"""
    colour(v_test_kmh, v_impact_kmh, contact; protocol)

Return the Figure 5-1 color for a protocol test speed (REQ-AEB-2). Green requires
no contact and zero impact speed. With contact, each available non-green band
includes its upper bound. Unknown speeds and negative/non-finite speeds error.
"""
function colour(v_test_kmh, v_impact_kmh, contact; protocol)
    speed = _positive(v_test_kmh, "test speed")
    vi = _nonnegative(v_impact_kmh, "impact speed")
    contact isa Bool || throw(ArgumentError("contact must be Bool"))
    speed in protocol["matrix"]["vut_speed_kmh"] ||
        throw(ArgumentError("unknown protocol test speed $speed km/h"))
    bands = protocol["colour_bands"][string(Int(speed))]
    if !contact
        vi == 0 || throw(ArgumentError("no-contact cells must have zero impact speed"))
        return :green
    end
    for name in protocol["colour_bands"]["order"]
        name == "green" && continue
        haskey(bands, name) && vi <= bands[name] && return Symbol(name)
    end
    return :red
end

function _range_name(value)
    value in (:standard, "standard") && return :standard
    value in (:extended, "extended") && return :extended
    throw(ArgumentError("cell range must be standard or extended"))
end

function _cells(cells, protocol; complete = false, full = false)
    result = collect(cells)
    seen = Set{Tuple{Float64, Float64}}()
    required = full ? CELL_FIELDS : (:v_test_kmh, :impact_location_pct, :range,
        :contact, :v_impact_kmh, :colour, :valid)
    matrix = protocol["matrix"]
    for cell in result
        all(k -> hasproperty(cell, k), required) ||
            throw(ArgumentError("each cell requires fields $(join(required, ", "))"))
        speed = _positive(cell.v_test_kmh, "cell test speed")
        location = _finite(cell.impact_location_pct, "cell impact location")
        range = _range_name(cell.range)
        speed in matrix["vut_speed_kmh"] || throw(ArgumentError("unknown cell test speed $speed"))
        locations = matrix[range == :standard ? "impact_location_standard_pct" : "impact_location_extended_pct"]
        location in locations || throw(ArgumentError("unknown $range impact location $location"))
        key = (speed, location)
        key in seen && throw(ArgumentError("duplicate grid cell $key"))
        push!(seen, key)
        cell.valid isa Bool || throw(ArgumentError("cell valid flag must be Bool"))
        expected = colour(speed, cell.v_impact_kmh, cell.contact; protocol)
        cell.colour in (expected, String(expected)) ||
            throw(ArgumentError("cell $key colour disagrees with contact and impact speed; expected $expected"))
        if full
            _finite(cell.t0_s, "cell T0")
            isnothing(cell.taeb_s) || _finite(cell.taeb_s, "cell TAEB")
            cell.notes isa AbstractString || throw(ArgumentError("cell notes must be text"))
        end
    end
    expected_count = length(matrix["vut_speed_kmh"]) *
        (length(matrix["impact_location_standard_pct"]) + length(matrix["impact_location_extended_pct"]))
    complete && length(result) != expected_count &&
        throw(ArgumentError("incomplete grid: expected $expected_count unique cells, got $(length(result))"))
    return result
end

function _extended_credit(fraction, protocol)
    0 <= fraction <= 1 || throw(ArgumentError("extended fraction must lie in [0, 1]"))
    credit = 0.0
    for (threshold, value) in protocol["scoring"]["extended_steps"]
        fraction >= threshold && (credit = value)
    end
    return credit
end

"""
    score(cells; protocol)

Validate a complete, unique, conduct-valid grid and return normalized standard
and extended points (rounded to hundredths), raw points, extended success
fraction and credited fraction, and `req_aeb1` (REQ-SCN-1, REQ-AEB-1/2).
`standard_points` and `extended_points` describe the predicted grid; `total_points`
is zero unless every standard cell selected by the protocol criterion avoids
contact. Invalid conduct, incomplete grids, or inconsistent colors raise errors.
Cells are named tuples or objects with the fields documented in ANALYSIS.md.
"""
function score(cells; protocol)
    data = _cells(cells, protocol; complete = true)
    all(c -> c.valid, data) || throw(ArgumentError("invalid test conduct: grid cannot be scored"))
    standard = filter(c -> _range_name(c.range) == :standard, data)
    extended = filter(c -> _range_name(c.range) == :extended, data)
    scoring = protocol["scoring"]
    standard_raw = sum(c -> scoring["colour_subscore"][String(c.colour)], standard) *
        scoring["standard_range_points"] / length(standard)
    fraction = count(c -> c.colour in (:green, :yellow, :orange, :brown,
        "green", "yellow", "orange", "brown"), extended) / length(extended)
    credit = _extended_credit(fraction, protocol)
    extended_raw = credit * scoring["extended_range_points"]
    threshold = _criterion_speed(protocol)
    accepted = all(c -> c.v_test_kmh > threshold ||
        (!c.contact && c.v_impact_kmh <= protocol["criterion"]["vimpact_max_kmh"]), standard)
    standard_points = round(standard_raw; digits = 2)
    extended_points = round(extended_raw; digits = 2)
    return (; standard_points, extended_points, standard_raw_points = standard_raw,
        extended_raw_points = extended_raw, extended_fraction = fraction,
        extended_credit = credit, req_aeb1 = accepted,
        total_points = accepted ? round(standard_points + extended_points; digits = 2) : 0.0)
end

_csv_escape(value) = "\"" * replace(string(value), "\"" => "\"\"") * "\""

"""
    write_cells_csv(path, cells; protocol = load_protocol())

Write the ten documented cell fields in CSV with quoted, escaped text and an
empty TAEB field for `nothing`. Validate cells before opening the destination.
Partial grids and invalid-conduct cells can be recorded; scoring rejects them.
"""
function write_cells_csv(path, cells; protocol = load_protocol())
    data = _cells(cells, protocol; full = true)
    open(path, "w") do io
        println(io, join(string.(CELL_FIELDS), ','))
        for c in data
            fields = (c.v_test_kmh, c.impact_location_pct, String(_range_name(c.range)),
                c.contact, c.v_impact_kmh, c.t0_s, isnothing(c.taeb_s) ? "" : c.taeb_s,
                String(c.colour), c.valid, c.notes)
            println(io, join(_csv_escape.(fields), ','))
        end
    end
    return path
end

function _csv_records(text)
    records = Vector{Vector{String}}()
    row = String[]
    field = IOBuffer()
    state = :start
    chars = collect(text)
    i = 1
    while i <= length(chars)
        c = chars[i]
        if state == :quoted
            if c == '"'
                if i < length(chars) && chars[i + 1] == '"'
                    print(field, '"')
                    i += 1
                else
                    state = :closed
                end
            else
                print(field, c)
            end
        elseif c in (',', '\n', '\r')
            push!(row, String(take!(field)))
            state = :start
            if c != ','
                push!(records, row)
                row = String[]
                if c == '\r' && i < length(chars) && chars[i + 1] == '\n'
                    i += 1
                end
            end
        elseif state == :closed
            throw(ArgumentError("unexpected character after closing CSV quote"))
        elseif c == '"'
            state == :start || throw(ArgumentError("quote inside unquoted CSV field"))
            state = :quoted
        else
            print(field, c)
            state = :plain
        end
        i += 1
    end
    state == :quoted && throw(ArgumentError("unterminated quoted CSV field"))
    if state != :start || !isempty(row)
        push!(row, String(take!(field)))
        push!(records, row)
    end
    return records
end

function _csv_bool(text)
    text == "true" && return true
    text == "false" && return false
    throw(ArgumentError("CSV Boolean must be true or false, got $(repr(text))"))
end

"""
    read_cells_csv(path; protocol = load_protocol())

Read the exact ten-column schema written by `write_cells_csv`, including quoted
commas, quotes, and newlines in notes. Return named tuples with Symbol range
and color. Reject malformed CSV, non-finite fields, duplicates, and unknown cells.
"""
function read_cells_csv(path; protocol = load_protocol())
    records = _csv_records(read(path, String))
    !isempty(records) && first(records) == string.(collect(CELL_FIELDS)) ||
        throw(ArgumentError("CSV header must match the documented ten-column cell schema"))
    cells = map(records[2:end]) do row
        length(row) == length(CELL_FIELDS) || throw(ArgumentError("CSV row must have ten columns"))
        values = (parse(Float64, row[1]), parse(Float64, row[2]), Symbol(row[3]),
            _csv_bool(row[4]), parse(Float64, row[5]), parse(Float64, row[6]),
            isempty(row[7]) ? nothing : parse(Float64, row[7]), Symbol(row[8]),
            _csv_bool(row[9]), row[10])
        NamedTuple{CELL_FIELDS}(values)
    end
    return _cells(cells, protocol; full = true)
end

_xml(text) = replace(string(text), '&' => "&amp;", '<' => "&lt;", '>' => "&gt;",
    '"' => "&quot;", '\'' => "&apos;")

"""
    grid_svg(path, cells; protocol)

Write a standalone SVG grid with descending speed rows and descending impact
location columns (REQ-SCN-1, REQ-AEB-2). Show impact speed for contact cells,
separate extended columns, and label predicted versus eligible total points.
Each of the grid's rectangles has `class="cell"` and an accessible title.
"""
function grid_svg(path, cells; protocol)
    data = _cells(cells, protocol; complete = true)
    result = score(data; protocol)
    matrix = protocol["matrix"]
    speeds = reverse(matrix["vut_speed_kmh"])
    locations = sort(vcat(matrix["impact_location_standard_pct"],
        matrix["impact_location_extended_pct"]); rev = true)
    lookup = Dict((c.v_test_kmh, c.impact_location_pct) => c for c in data)
    fills = Dict(:green => "#00ad4f", :yellow => "#fff03b", :orange => "#ffc000",
        :brown => "#843c0c", :red => "#e30613")
    left, top, cw, ch = 126, 146, 104, 52
    width = left + length(locations) * cw + 42
    height = top + length(speeds) * ch + 182
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $width $height\" role=\"img\" aria-labelledby=\"title desc\">")
        println(io, "<title id=\"title\">CCRs predicted performance</title><desc id=\"desc\">Impact speed in km/h; green indicates no contact. Extended range columns have dashed borders.</desc>")
        println(io, "<rect width=\"$width\" height=\"$height\" fill=\"#f4f4f2\"/>")
        println(io, "<g font-family=\"Arial, sans-serif\" fill=\"#171717\">")
        println(io, "<text x=\"32\" y=\"38\" font-size=\"24\" font-weight=\"bold\">CCRs predicted performance</text>")
        println(io, "<text x=\"32\" y=\"64\" font-size=\"13\">Euro NCAP protocol $(_xml(protocol["source"]["version"])) | Figure 5-1; sections 5.1 and 5.3</text>")
        println(io, "<text x=\"32\" y=\"89\" font-size=\"13\">Rows: test speed (km/h) | Columns: impact location (%) | Cells: impact speed (km/h)</text>")
        for (j, location) in enumerate(locations)
            x = left + (j - 0.5) * cw
            extended = location in matrix["impact_location_extended_pct"]
            println(io, "<text x=\"$x\" y=\"122\" text-anchor=\"middle\" font-size=\"16\">$location%</text>")
            extended && println(io, "<text x=\"$x\" y=\"139\" text-anchor=\"middle\" font-size=\"10\">EXTENDED</text>")
        end
        for (i, speed) in enumerate(speeds)
            y = top + (i - 1) * ch
            println(io, "<text x=\"110\" y=\"$(y + 32)\" text-anchor=\"end\" font-size=\"16\">$speed</text>")
            for (j, location) in enumerate(locations)
                c = lookup[(speed, location)]
                x = left + (j - 1) * cw
                name = Symbol(c.colour)
                extended = _range_name(c.range) == :extended
                dash = extended ? " stroke-dasharray=\"5 3\"" : ""
                println(io, "<rect class=\"cell\" data-speed=\"$speed\" data-location=\"$location\" x=\"$(x + 3)\" y=\"$(y + 3)\" width=\"$(cw - 6)\" height=\"$(ch - 6)\" rx=\"4\" fill=\"$(fills[name])\" stroke=\"#333333\"$dash><title>$speed km/h, $location%: $name; impact $(_xml(c.v_impact_kmh)) km/h</title></rect>")
                if c.contact
                    ink = name in (:brown, :red) ? "#ffffff" : "#171717"
                    label = @sprintf("%.2f", c.v_impact_kmh)
                    println(io, "<text x=\"$(x + cw / 2)\" y=\"$(y + 32)\" text-anchor=\"middle\" font-family=\"monospace\" font-size=\"16\" fill=\"$ink\">$label</text>")
                end
            end
        end
        baseline = top + length(speeds) * ch
        for (j, name) in enumerate((:green, :yellow, :orange, :brown, :red))
            x = 32 + (j - 1) * 155
            println(io, "<rect x=\"$x\" y=\"$(baseline + 24)\" width=\"16\" height=\"16\" fill=\"$(fills[name])\"/><text x=\"$(x + 24)\" y=\"$(baseline + 37)\" font-size=\"13\">$name</text>")
        end
        totals = @sprintf("Predicted points: standard %.2f / %.2f | extended %.2f / %.2f",
            result.standard_points, protocol["scoring"]["standard_range_points"],
            result.extended_points, protocol["scoring"]["extended_range_points"])
        println(io, "<text x=\"32\" y=\"$(baseline + 74)\" font-size=\"16\">$totals</text>")
        status = result.req_aeb1 ? "met" : "not met"
        total = @sprintf("%.2f", result.total_points)
        println(io, "<text x=\"32\" y=\"$(baseline + 101)\" font-size=\"16\">REQ-AEB-1: $status | Eligible total: $total points</text>")
        println(io, "<text x=\"32\" y=\"$(baseline + 131)\" font-size=\"12\">Prediction only. Robustness layers and official verification tests are outside this analysis.</text>")
        println(io, "<a href=\"$(_xml(protocol["source"]["url"]))#page=69\"><text x=\"32\" y=\"$(baseline + 157)\" font-size=\"12\" text-decoration=\"underline\">Source: Euro NCAP Crash Avoidance - Frontal Collisions</text></a></g></svg>")
    end
    return path
end

end # module CCRsAnalysis
