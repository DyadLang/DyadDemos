# Trapezoidal velocity profile for rest-to-rest slew maneuvers.
# Reference: Standard spacecraft AOCS practice (ESA ECSS-E-ST-60-30C, NASA GSFC).
#
# Profile phases:
#   1. Accelerate at +a_max until w_max reached
#   2. Coast at w_max
#   3. Decelerate at -a_max to rest
#
# Uses ModelingToolkit-compatible ifelse() for symbolic traceability.

using ModelingToolkit: ifelse

"""
    trapz_angle_ref(t, target_angle, w_max, a_max)

Returns the reference angle at time `t` for a trapezoidal velocity profile
that slews from 0 to `target_angle`. Compatible with symbolic MTK variables.

Assumes trapezoidal regime (target_angle > w_max²/a_max). For our default
parameters this always holds.
"""
function trapz_angle_ref(t, target_angle, w_max, a_max)
    t_ramp = w_max / a_max
    theta_ramp = w_max^2 / (2 * a_max)
    t_coast = (target_angle - 2 * theta_ramp) / w_max
    t_total = 2 * t_ramp + t_coast
    t_decel_start = t_ramp + t_coast
    t_loc = t - t_decel_start

    # Phase 1: accelerate
    phase1 = 0.5 * a_max * t^2
    # Phase 2: coast
    phase2 = theta_ramp + w_max * (t - t_ramp)
    # Phase 3: decelerate
    phase3 = theta_ramp + w_max * t_coast + w_max * t_loc - 0.5 * a_max * t_loc^2
    # Phase 4: hold
    phase4 = target_angle

    return ifelse(t < 0, 0.0,
           ifelse(t < t_ramp, phase1,
           ifelse(t < t_decel_start, phase2,
           ifelse(t < t_total, phase3,
                  phase4))))
end

"""
    trapz_accel_ref(t, target_angle, w_max, a_max)

Returns the reference angular acceleration at time `t` for a trapezoidal
velocity profile. Compatible with symbolic MTK variables.
"""
function trapz_accel_ref(t, target_angle, w_max, a_max)
    t_ramp = w_max / a_max
    theta_ramp = w_max^2 / (2 * a_max)
    t_coast = (target_angle - 2 * theta_ramp) / w_max
    t_total = 2 * t_ramp + t_coast
    t_decel_start = t_ramp + t_coast

    return ifelse(t < 0, 0.0,
           ifelse(t < t_ramp, a_max,
           ifelse(t < t_decel_start, 0.0,
           ifelse(t < t_total, -a_max,
                  0.0))))
end

"""
    trapz_rate_ref(t, target_angle, w_max, a_max)

Returns the reference angular rate at time `t` for a trapezoidal velocity profile.
Compatible with symbolic MTK variables.
"""
function trapz_rate_ref(t, target_angle, w_max, a_max)
    t_ramp = w_max / a_max
    theta_ramp = w_max^2 / (2 * a_max)
    t_coast = (target_angle - 2 * theta_ramp) / w_max
    t_total = 2 * t_ramp + t_coast
    t_decel_start = t_ramp + t_coast
    t_loc = t - t_decel_start

    # Phase 1: accelerate
    phase1 = a_max * t
    # Phase 2: coast
    phase2 = w_max
    # Phase 3: decelerate
    phase3 = w_max - a_max * t_loc
    # Phase 4: hold
    phase4 = 0.0

    return ifelse(t < 0, 0.0,
           ifelse(t < t_ramp, phase1,
           ifelse(t < t_decel_start, phase2,
           ifelse(t < t_total, phase3,
                  phase4))))
end
