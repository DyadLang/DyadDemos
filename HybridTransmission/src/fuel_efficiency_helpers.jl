# Helper functions for fuel efficiency optimization

"""
Rolling resistance force, zero below a small speed threshold.

Inputs:
  - speed_ms: Vehicle speed (m/s)
  - C_rr: Rolling resistance coefficient
  - m_kg: Vehicle mass (kg)
  - v_threshold: Minimum speed for rolling resistance (m/s), default 0.1

Output:
  - F_rolling: Rolling resistance force (N)
"""
function rolling_resistance_force(speed_ms, C_rr, m_kg, v_threshold=0.1)
    # ifelse keeps this usable inside symbolic expressions.
    return ifelse(abs(speed_ms) > v_threshold, C_rr * m_kg * 9.81, 0.0)
end

"""
Engine BSFC (Brake Specific Fuel Consumption) fuel rate calculation.

Based on data from:
  Guzzella, L. & Sciarretta, A. (2013). "Vehicle Propulsion Systems: Introduction to Modeling and Optimization" (3rd ed.)
  Table 3.1: Typical SI engine BSFC map
  - Best point: 250 g/kWh at 2500 RPM, 75% load
  - Part-load penalty: +50-100 g/kWh
  - Speed penalty: +30-50 g/kWh away from optimal

Inputs:
  - torque_nm: Engine torque (N·m)
  - speed_rpm: Engine speed (RPM)

Output:
  - fuel_rate_gs: Fuel consumption rate (g/s)
"""
function engine_bsfc_fuel_rate(torque_nm, speed_rpm)
    # Use max/min for clamping (symbolic-safe)
    torque = min(max(torque_nm, 0.0), 150.0)
    speed = min(max(speed_rpm, 0.0), 6000.0)
    
    # Calculate power (kW) - add small epsilon to avoid division by zero
    power_kw = torque * (speed * 2 * π / 60) / 1000.0 + 1e-6
    
    # Normalized coordinates for efficiency
    speed_norm = speed / 3000.0  # Normalize around 3000 RPM
    torque_norm = torque / 100.0  # Normalize around 100 N·m
    
    # BSFC model (g/kWh) - parabolic with sweet spot
    # Best efficiency at mid-range
    speed_penalty = (speed_norm - 1.0)^2 * 50
    torque_penalty = (torque_norm - 0.7)^2 * 80
    
    # Low load penalty (using smooth max instead of if)
    low_load_penalty = max(0.0, 100 * (0.3 - torque_norm))
    
    bsfc = 250.0 + speed_penalty + torque_penalty + low_load_penalty  # g/kWh
    
    # Convert to fuel rate (g/s)
    fuel_rate = (bsfc * power_kw) / 3600.0
    
    # Minimum is idle consumption (use max for symbolic safety)
    return max(fuel_rate, 0.5)
end

"""
UDDS (urban) drive cycle speed profile: time `t` in seconds, speed out in m/s.
Simplified smooth approximation.
"""
function udds_speed_profile(t)
    # Simplified UDDS-like profile using piecewise polynomial
    # This creates a city-driving pattern with stops and accelerations
    
    # Use smooth periodic function (symbolic-safe)
    # Period of ~200 seconds for this simplified version
    period = 200.0
    t_norm = mod(t, period) / period  # Normalize to [0, 1]
    
    # Create speed profile using smooth functions
    # Combination of sine waves creates acceleration/deceleration/cruise pattern
    base_speed = 10.0 * sin(2 * π * t_norm)  # Base oscillation
    accel_component = 5.0 * sin(4 * π * t_norm)  # Faster variations
    stop_zones = max(0.0, 5.0 * cos(π * t_norm))  # Periodic stops
    
    # Combine components
    speed_mps = max(0.0, base_speed + accel_component + stop_zones)
    
    return speed_mps
end

"""
Engine operating point that burns the least fuel for a given power demand (kW).
Returns `(torque_nm, speed_rpm)`.
"""
function optimal_engine_point(power_demand_kw::Real)::Tuple{Real, Real}
    # For a given power, the optimal operating point is typically
    # at moderate speed (2500-3500 RPM) and appropriate torque
    
    if power_demand_kw < 5.0
        # Low power: use moderate speed, low torque
        optimal_speed_rpm = 2500.0
        # P = T * omega, omega = 2*pi*N/60
        omega = optimal_speed_rpm * 2 * π / 60
        optimal_torque_nm = (power_demand_kw * 1000.0) / omega
    elseif power_demand_kw < 30.0
        # Medium power: sweet spot around 3000 RPM, 70 N·m
        optimal_speed_rpm = 3000.0
        omega = optimal_speed_rpm * 2 * π / 60
        optimal_torque_nm = (power_demand_kw * 1000.0) / omega
    else
        # High power: increase speed to avoid excessive torque
        optimal_speed_rpm = 3500.0
        omega = optimal_speed_rpm * 2 * π / 60
        optimal_torque_nm = (power_demand_kw * 1000.0) / omega
    end
    
    # Clamp to engine limits
    optimal_torque_nm = clamp(optimal_torque_nm, 0.0, 150.0)
    optimal_speed_rpm = clamp(optimal_speed_rpm, 1000.0, 6000.0)
    
    return (optimal_torque_nm, optimal_speed_rpm)
end

"""
EPA Highway/Freeway drive cycle speed profile (HWFET).

Source: EPA 40 CFR Part 86, Appendix I, Section (f)
  - Duration: 765 seconds
  - Distance: 10.26 miles  
  - Average speed: 48.3 mph (77.7 km/h)
  - Maximum speed: 60 mph (96.6 km/h)

Simplified piecewise constant approximation of official test cycle.

Input:
  - t: Time (seconds)

Output:
  - speed_mps: Vehicle speed (m/s)
"""
function epa_highway_speed(t)
    # tanh transitions keep the profile differentiable for the solver.
    
    # Convert mph to m/s
    mph_to_ms = 0.44704
    
    # Smoothing parameter (transition width in seconds)
    k = 0.5  # Smaller = sharper but still smooth transitions
    
    # Phase 1: Initial acceleration (t=7s to t=33s)
    # Ramp from 0 to 60 mph using smooth sigmoid
    accel_start = 7.0
    accel_end = 33.0
    cruise_speed = 60.0 * mph_to_ms
    
    # Smooth startup: zero for t < 5, transitions smoothly to 1 around t=7
    # Use a sharper transition centered at t=7
    startup = (1.0 + tanh((t - accel_start) / k)) / 2.0
    
    # Smooth acceleration profile using tanh
    # At t=7: starts rising, at t=33: reaches cruise speed
    accel_phase = cruise_speed * (1.0 + tanh((t - (accel_start + accel_end) / 2.0) / ((accel_end - accel_start) / 4.0))) / 2.0
    
    # Phase 2-3: Cruise at 60 mph (t=33s to t=477s) - already at cruise from accel_phase
    
    # Phase 4: Deceleration (t=477s to t=485s) to 48 mph
    decel_start = 477.0
    decel_end = 485.0
    final_speed = 48.0 * mph_to_ms
    speed_drop = cruise_speed - final_speed
    
    # Smooth deceleration
    decel_phase = speed_drop * (1.0 + tanh((t - (decel_start + decel_end) / 2.0) / ((decel_end - decel_start) / 4.0))) / 2.0
    
    # Combine phases: start at 0, accelerate to cruise, then decelerate
    speed = startup * (accel_phase - decel_phase)
    
    # Ensure non-negative and exactly zero for early times
    # Use smooth max to avoid discontinuity
    return speed * startup  # Double multiplication ensures very small values at t=0
end
