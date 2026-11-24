using Test

if !isdefined(@__MODULE__, :CCRsAnalysis)
    include(joinpath(@__DIR__, "..", "validation", "sedan_aeb_ccrs", "ccrs_analysis.jl"))
end
using .CCRsAnalysis

@testset "CCRs synthetic analysis verification" begin
    protocol = load_protocol()
    matrix = protocol["matrix"]
    limits = protocol["conduct"]
    measurement = protocol["measurement"]
    speeds = matrix["vut_speed_kmh"]
    v10, v20, v30, v40, v50, v60, v70, v80 = speeds
    standard = matrix["impact_location_standard_pct"]
    extended = matrix["impact_location_extended_pct"]
    dt = 1 / limits["sample_rate_min_hz"]

    function make_cell(speed, location; contact = false, vi = 0.0, valid = true,
            notes = "synthetic", taeb_s = nothing)
        return (v_test_kmh = Float64(speed), impact_location_pct = Float64(location),
            range = location in standard ? :standard : :extended, contact,
            v_impact_kmh = Float64(vi), t0_s = 0.0, taeb_s,
            colour = colour(speed, vi, contact; protocol), valid, notes)
    end
    grid() = NamedTuple[make_cell(speed, location) for speed in speeds
        for location in vcat(standard, extended)]

    @testset "REQ-SCN-1/6 protocol intake and impact locations" begin
        @test length(grid()) == 56
        @test target_lateral_offset(first(standard); w_vut = 1.849) == 1.849 / 2
        @test target_lateral_offset(standard[3]; w_vut = 1.849) == 0
        @test target_lateral_offset(last(standard); w_vut = 1.849) == -1.849 / 2
        @test target_lateral_offset(first(extended); w_vut = 1.849) > 1.849 / 2
        @test target_lateral_offset(last(extended); w_vut = 1.849) < -1.849 / 2
        @test_throws "finite" target_lateral_offset(NaN; w_vut = 1.849)
        @test_throws "positive" target_lateral_offset(0; w_vut = 0)
        mktemp() do path, io
            write(io, "[matrix]\n")
            close(io)
            @test_throws "missing" load_protocol(path)
        end
        modified = deepcopy(protocol)
        modified["matrix"]["vut_speed_kmh"] = reverse(speeds)
        @test_throws "sorted" CCRsAnalysis._validate_protocol(modified)
        modified = deepcopy(protocol)
        modified["criterion"]["case"] = "unsupported expression"
        @test_throws "unsupported criterion" CCRsAnalysis._validate_protocol(modified)
    end

    @testset "REQ-MEAS-1 constant-deceleration contact oracle" begin
        v0, a, d = 10.0, 2.0, 12.0
        t = collect(0:dt:6)
        elapsed = min.(t, v0 / a)
        x = v0 .* elapsed .- a / 2 .* elapsed .^ 2
        v = max.(v0 .- a .* t, 0)
        z = zeros(length(t))
        yaw = zeros(length(t))
        geometry = (z_target = 0.0, w_vut = 1.849, w_target = 1.712,
            inset = measurement["front_profile_inset_m"])
        got = impact(t, x, z, yaw, v; x_target = d, geometry...)
        exact_vi = sqrt(v0^2 - 2a * d)
        exact_time = (v0 - exact_vi) / a
        speed_bound = 3.6a^2 * dt^2 / (4exact_vi)
        @test got.contact
        @test abs(got.v_impact_kmh - 3.6exact_vi) <= speed_bound
        @test abs(got.t_impact - exact_time) <= speed_bound / (3.6a)
        @test got.t_impact ∉ t
        no_contact = impact(t, x, z, yaw, v; x_target = v0^2 / (2a) + 0.01, geometry...)
        @test no_contact == (contact = false, t_impact = nothing, v_impact_kmh = 0.0)

        touch_speed = 1 / 3.6
        touch_time = (v0 - touch_speed) / a
        tt = sort!(unique([t; touch_time]))
        et = min.(tt, v0 / a)
        xx = v0 .* et .- a / 2 .* et .^ 2
        vv = max.(v0 .- a .* tt, 0)
        touch = impact(tt, xx, zeros(length(tt)), zeros(length(tt)), vv;
            x_target = (v0^2 - touch_speed^2) / (2a), geometry...)
        @test touch.contact
        @test touch.v_impact_kmh ≈ 1 atol = 1e-10
        @test touch.t_impact ≈ touch_time atol = 1e-10

        offset = target_lateral_offset(last(extended); w_vut = geometry.w_vut)
        touching_width = 2 * (abs(offset) - (geometry.w_vut / 2 - geometry.inset))
        for (width, contact) in ((touching_width - 1e-5, false), (touching_width + 1e-5, true))
            result = impact(t, x, z, yaw, v; x_target = d, z_target = offset,
                w_vut = geometry.w_vut, w_target = width, inset = geometry.inset)
            @test result.contact == contact
        end
        @test impact(t, x, z, yaw, v; x_target = 0.0, geometry...).t_impact == first(t)
        @test_throws "beyond" impact(t, x, z, yaw, v; x_target = -1.0, geometry...)
        @test_throws "strictly increasing" impact(reverse(t), x, z, yaw, v; x_target = d, geometry...)
        @test_throws DimensionMismatch impact(t, x[2:end], z, yaw, v; x_target = d, geometry...)
        bad_z = copy(z)
        bad_z[5] = NaN
        @test_throws "finite" impact(t, x, bad_z, yaw, v; x_target = d, geometry...)
        @test_throws "nonnegative" impact(t, x, z, yaw, -v; x_target = d, geometry...)
        view_result = impact(view(t, :), view(x, :), view(z, :), view(yaw, :), view(v, :);
            x_target = d, geometry...)
        @test view_result == got
        lateral_crossing = impact([0.0, 1.0], [0.0, 2.0], [-3.0, 3.0], [0.0, 0.0], [1.0, 3.0];
            x_target = 1.0, geometry...)
        @test lateral_crossing.contact
        @test lateral_crossing.t_impact == 0.5
        @test lateral_crossing.v_impact_kmh == 7.2

        # Yaw 30°: a profile end sits halfwidth*sin(yaw) ahead of or behind the center.
        # Target centered on the leading end, center stopping 0.3 m short of the plane:
        # the leading end hits. Only the trailing end facing the target, center passing
        # 0.2 m beyond the plane: no contact. The straight profile gives the opposite
        # result in both runs.
        θ = deg2rad(30)
        yawed = fill(θ, length(t))
        halfwidth = geometry.w_vut / 2 - geometry.inset
        stop = v0^2 / (2a)
        leading = merge(geometry, (x_target = stop + 0.3, z_target = halfwidth * cos(θ)))
        hit = impact(t, x, z, yawed, v; leading...)
        hit_vi = sqrt(v0^2 - 2a * (stop + 0.3 - halfwidth * sin(θ)))
        @test hit.contact
        @test abs(hit.v_impact_kmh - 3.6hit_vi) <= 3.6a^2 * dt^2 / (4hit_vi)
        @test !impact(t, x, z, yaw, v; leading...).contact
        trailing = merge(geometry, (x_target = stop - 0.2,
            z_target = -halfwidth * cos(θ) - geometry.w_target / 2 + 0.1))
        @test !impact(t, x, z, yawed, v; trailing...).contact
        @test impact(t, x, z, yaw, v; trailing...).contact
        @test_throws "±90°" profile_reach(0.0, 0.0, 2.0; z_target = 0.0, halfwidth, w_target = 1.0)
        # Yaw turning from 0° to 60° within one sample interval, profile half-width 1 m,
        # target wide enough to face the whole profile: the reach 2t + sin(πt/3) is
        # nonlinear in time, and contact is at its root.
        turning = merge(geometry, (x_target = 1.2, w_target = 10.0, w_vut = 2 + 2geometry.inset))
        turn = impact([0.0, 1.0], [0.0, 2.0], [0.0, 0.0], [0.0, π / 3], [1.0, 3.0]; turning...)
        @test turn.contact
        @test 2turn.t_impact + sin(π / 3 * turn.t_impact) ≈ 1.2 atol = 1e-12
        @test turn.v_impact_kmh ≈ 3.6 * (1 + 2turn.t_impact) atol = 1e-9
    end

    @testset "REQ-SCN-3 TTC start is interpolated" begin
        t = collect(0:dt:8)
        speed, d = 5.0, 35.1
        x = speed .* t
        v = fill(speed, length(t))
        ttc = limits["ttc_start_s"]
        expected = (d - ttc * speed) / speed
        @test test_start(t, x, v; x_target = d, ttc_s = ttc) ≈ expected
        @test test_start(t, x, v; x_target = ttc * speed, ttc_s = ttc) == 0
        @test_throws "never crosses" test_start(t, x, v; x_target = 1000, ttc_s = ttc)
        @test_throws "starts after" test_start(t, x, v; x_target = 1, ttc_s = ttc)
        @test_throws "never crosses" test_start(t, zeros(length(t)), zeros(length(t));
            x_target = d, ttc_s = ttc)
        crossing = 0.37
        xx, vv = [0.0, 3.0], [2.0, 4.0]
        xt = crossing * xx[2] + ttc * (vv[1] + crossing * (vv[2] - vv[1]))
        @test test_start([0.0, 1.0], xx, vv; x_target = xt, ttc_s = ttc) ≈ crossing
    end

    @testset "REQ-MEAS-2 Butterworth DC, cutoff gain and zero phase" begin
        fc = limits["accel_filter_cutoff_hz"]
        poles = limits["accel_filter_order"]
        fs = 2limits["sample_rate_min_hz"]
        t = collect(0:(1 / fs):8)
        filtered = butter_filtfilt(t, fill(2.5, length(t)); fc_hz = fc, poles)
        @test maximum(abs.(filtered .- 2.5)) < 1e-12
        sinusoid = sinpi.(2fc .* t)
        response = butter_filtfilt(t, sinusoid; fc_hz = fc, poles)
        middle = findall(time -> 1 < time < 7, t)
        gain = sum(response[middle] .* sinusoid[middle]) / sum(abs2, sinusoid[middle])
        @test gain ≈ 0.5 atol = 2e-5
        quadrature = cospi.(2fc .* t)
        @test abs(sum(response[middle] .* quadrature[middle]) /
            sum(abs2, quadrature[middle])) < 2e-5
        pulse = zeros(length(t))
        center = div(length(t) + 1, 2)
        pulse[center] = 1
        response = butter_filtfilt(t, pulse; fc_hz = fc, poles)
        @test argmax(response) == center
        @test maximum(abs.(response .- reverse(response))) < 1e-12
        @test sum(response) ≈ 1 atol = 1e-10
        @test butter_filtfilt(view(t, :), view(pulse, :); fc_hz = fc, poles) == response
        @test all(isfinite, butter_filtfilt([0.0, 0.01, 0.02], ones(3); fc_hz = fc, poles))
        @test_throws "uniformly" butter_filtfilt([0.0, 0.01, 0.025], ones(3); fc_hz = fc, poles)
        @test_throws "Nyquist" butter_filtfilt(t, pulse; fc_hz = fs, poles)
        @test_throws "even integer" butter_filtfilt(t, pulse; fc_hz = fc, poles = poles - 1)
        @test_throws "finite" butter_filtfilt(t, fill(Inf, length(t)); fc_hz = fc, poles)
        @test_throws "at least 3 samples" butter_filtfilt(t[1:2], pulse[1:2]; fc_hz = fc, poles)
        @test_throws "offset" butter_filtfilt(Base.Slice(0:2), ones(3); fc_hz = fc, poles)
    end

    @testset "REQ-MEAS-2 TAEB acceleration-ramp oracle" begin
        t = collect(0:(dt / 2):5)
        onset, ramp_time, deceleration, v0 = 2.0, 1.0, 4.0, 20.0
        function velocity(time)
            s = max(time - onset, 0)
            return v0 - (s <= ramp_time ? deceleration * s^2 / (2ramp_time) :
                deceleration * (s - ramp_time / 2))
        end
        v = velocity.(t)
        expected = onset - measurement["taeb_onset_mps2"] * ramp_time / deceleration
        got = taeb(t, v; protocol)
        @test got ≈ expected atol = dt / 2
        @test taeb(t, fill(v0, length(t)); protocol) === nothing
        mild = v0 .- t
        @test taeb(t, mild; protocol) === nothing
        @test_throws "precedes" taeb(t, v0 .- deceleration .* t; protocol)
    end

    @testset "REQ-SCN-4/5 and REQ-MEAS-3 conduct checks" begin
        t = collect(0:dt:4)
        reference = v60 / 3.6
        v = fill(reference, length(t))
        z = zeros(length(t))
        throttle = fill(0.2, length(t))
        kwargs = (v_test = reference, t0 = 0.213, t_end_check = 1.717, protocol)
        good = conduct_checks(t, v, z, throttle; kwargs...)
        @test good.valid
        @test good.throttle.release_s === nothing
        for sign in (-1, 1)
            edge_speed = v .+ sign * limits["vut_speed_tolerance_kmh"] / 3.6
            @test conduct_checks(t, edge_speed, z, throttle; kwargs...).speed.pass
            outside_speed = v .+ sign * (limits["vut_speed_tolerance_kmh"] + 1e-8) / 3.6
            @test !conduct_checks(t, outside_speed, z, throttle; kwargs...).speed.pass
            edge_lateral = fill(sign * limits["vut_lateral_deviation_m"], length(t))
            @test conduct_checks(t, v, edge_lateral, throttle; kwargs...).lateral.pass
            fast = v .+ sign * 1.1limits["vut_speed_tolerance_kmh"] / 3.6
            bad = conduct_checks(t, fast, z, throttle; kwargs...)
            @test !bad.valid
            @test bad.speed.worst_kmh ≈ sign * 1.1limits["vut_speed_tolerance_kmh"]
            lateral = fill(sign * 1.1limits["vut_lateral_deviation_m"], length(t))
            bad = conduct_checks(t, v, lateral, throttle; kwargs...)
            @test !bad.lateral.pass
            @test bad.lateral.worst_m == first(lateral)
        end
        braking = reference .- 2 .* max.(t .- 2, 0)
        released = [time < 2 ? 0.2 : 0.0 for time in t]
        checked = conduct_checks(t, braking, z, released; kwargs...)
        @test checked.valid
        @test checked.throttle.release_s ≈ 2 + limits["accelerator_release_drop_kmh"] / (3.6 * 2)
        reapplied = copy(released)
        reapplied[end] = 0.01
        @test !conduct_checks(t, braking, z, reapplied; kwargs...).throttle.pass
        recovered = copy(braking)
        recovered[end] = reference
        @test !conduct_checks(t, recovered, z, reapplied; kwargs...).throttle.pass
        step = 2
        @test !conduct_checks(t[1:step:end], v[1:step:end], z[1:step:end],
            throttle[1:step:end]; kwargs...).sampling.pass
        @test_throws "inside" conduct_checks(t, v, z, throttle;
            v_test = reference, t0 = -1, t_end_check = 1, protocol)
        @test_throws "start <= end" conduct_checks(t, v, z, throttle;
            v_test = reference, t0 = 2, t_end_check = 1, protocol)
        @test_throws "throttle" conduct_checks(t, v, z, fill(-0.01, length(t)); kwargs...)
        segment_t = [0.0, dt]
        edge = conduct_checks(segment_t, [reference + 2 / 3.6, reference], zeros(2), zeros(2);
            v_test = reference, t0 = dt / 4, t_end_check = 3dt / 4, protocol)
        @test !edge.speed.pass
        @test edge.speed.worst_kmh ≈ 1.5
    end

    @testset "REQ-AEB-2 Figure 5-1 color band edges" begin
        for speed in speeds
            @test colour(speed, 0, false; protocol) == :green
            @test colour(speed, speed, true; protocol) == :red
        end
        @test colour(v10, 0, true; protocol) == :red
        @test colour(v20, 0, true; protocol) == :red
        bands30 = protocol["colour_bands"][string(v30)]
        @test colour(v30, bands30["brown"], true; protocol) == :brown
        @test colour(v30, nextfloat(bands30["brown"]), true; protocol) == :red
        bands40 = protocol["colour_bands"][string(v40)]
        @test colour(v40, bands40["orange"], true; protocol) == :orange
        @test colour(v40, nextfloat(bands40["orange"]), true; protocol) == :brown
        @test colour(v40, bands40["brown"], true; protocol) == :brown
        @test colour(v40, nextfloat(bands40["brown"]), true; protocol) == :red
        bands60 = protocol["colour_bands"][string(v60)]
        for (name, nextname) in ((:yellow, :orange), (:orange, :brown), (:brown, :red))
            bound = bands60[String(name)]
            @test colour(v60, bound, true; protocol) == name
            @test colour(v60, nextfloat(bound), true; protocol) == nextname
        end
        @test_throws "unknown" colour(v80 + 1, 0, false; protocol)
        @test_throws "nonnegative" colour(v60, -1, true; protocol)
        @test_throws "finite" colour(v60, NaN, true; protocol)
        @test_throws "zero impact" colour(v60, 1, false; protocol)
    end

    @testset "REQ-AEB-1/2 complete-grid scoring and entry gate" begin
        cells = grid()
        all_green = score(cells; protocol)
        @test all_green.standard_points == protocol["scoring"]["standard_range_points"]
        @test all_green.extended_points == protocol["scoring"]["extended_range_points"]
        @test all_green.total_points ≈ 1.35
        @test all_green.req_aeb1
        low = findfirst(c -> c.v_test_kmh == v10 && c.range == :standard, cells)
        cells[low] = make_cell(v10, cells[low].impact_location_pct; contact = true, vi = 1)
        rejected = score(cells; protocol)
        @test !rejected.req_aeb1
        @test rejected.total_points == 0
        @test rejected.standard_points < all_green.standard_points
        @test_throws "incomplete" score(cells[2:end]; protocol)
        @test_throws "duplicate" score([cells; cells[1]]; protocol)
        cells = grid()
        cells[1] = merge(cells[1], (valid = false,))
        @test_throws "invalid test conduct" score(cells; protocol)
        cells = grid()
        cells[1] = merge(cells[1], (colour = :red,))
        @test_throws "disagrees" score(cells; protocol)
        cells = grid()
        cells[1] = merge(cells[1], (impact_location_pct = 17.0,))
        @test_throws "unknown" score(cells; protocol)
        for (fraction, credit) in ((0.49, 0.0), (0.50, 0.50), (0.74, 0.50),
                (0.75, 0.75), (1.0, 1.0))
            @test CCRsAnalysis._extended_credit(fraction, protocol) == credit
        end
        for successful in 0:(length(speeds) * length(extended))
            cells = grid()
            indices = findall(c -> c.range == :extended, cells)
            for j in (successful + 1):length(indices)
                c = cells[indices[j]]
                cells[indices[j]] = make_cell(c.v_test_kmh, c.impact_location_pct;
                    contact = true, vi = c.v_test_kmh)
            end
            fraction = successful / length(indices)
            expected = fraction == 1 ? 1.0 : fraction >= 0.75 ? 0.75 : fraction >= 0.5 ? 0.5 : 0.0
            got = score(cells; protocol)
            @test got.extended_fraction == fraction
            @test got.extended_raw_points == expected * protocol["scoring"]["extended_range_points"]
            @test got.extended_points == round(got.extended_raw_points; digits = 2)
        end
    end

    @testset "REQ-AEB-2 CSV and SVG interchange" begin
        mktempdir() do dir
            cells = grid()
            cells[1] = merge(cells[1], (notes = "comma, quote \" and\nnewline & <tag>",))
            cells[end] = merge(cells[end], (taeb_s = 1.25,))
            csv = joinpath(dir, "cells.csv")
            @test write_cells_csv(csv, cells; protocol) == csv
            reread = read_cells_csv(csv; protocol)
            @test reread == cells
            @test score(reread; protocol) == score(cells; protocol)
            svg = joinpath(dir, "grid.svg")
            @test grid_svg(svg, cells; protocol) == svg
            text = read(svg, String)
            @test count("class=\"cell\"", text) == length(cells)
            @test occursin("REQ-AEB-1: met", text)
            @test occursin("stroke-dasharray", text)
            @test occursin("1.35 points", text)
            @test findfirst("data-speed=\"$v80\" data-location=\"$(last(extended))\"", text) !== nothing
            write(csv, "bad,header\n")
            @test_throws "header" read_cells_csv(csv; protocol)
            write_cells_csv(csv, cells; protocol)
            write(csv, replace(read(csv, String), "\"true\"" => "\"yes\""; count = 1))
            @test_throws "Boolean" read_cells_csv(csv; protocol)
            @test_throws "unterminated" CCRsAnalysis._csv_records("\"no end")
            @test_throws "closing" CCRsAnalysis._csv_records("\"closed\"x")
            @test CCRsAnalysis._csv_records("a,b\r\nc,d\r\n") == [["a", "b"], ["c", "d"]]
        end
    end
end
