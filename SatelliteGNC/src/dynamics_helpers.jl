# 6-DOF dynamics helper functions for SatelliteBody6DOF.
# All functions use basic arithmetic and trig — fully compatible with
# ModelingToolkit symbolic variables (no if/else, no mutation).

"""
    eci_grav_ax(x, y, z, mu)

Gravitational acceleration x-component in ECI frame (two-body).
"""
function eci_grav_ax(x, y, z, mu)
    r = sqrt(x^2 + y^2 + z^2)
    return -mu * x / r^3
end

"""
    eci_grav_ay(x, y, z, mu)

Gravitational acceleration y-component in ECI frame (two-body).
"""
function eci_grav_ay(x, y, z, mu)
    r = sqrt(x^2 + y^2 + z^2)
    return -mu * y / r^3
end

"""
    eci_grav_az(x, y, z, mu)

Gravitational acceleration z-component in ECI frame (two-body).
"""
function eci_grav_az(x, y, z, mu)
    r = sqrt(x^2 + y^2 + z^2)
    return -mu * z / r^3
end

# --- 3-2-1 (yaw-pitch-roll) rotation matrix: body → ECI ---
# R = Rz(ψ) * Ry(θ) * Rx(φ)
# Returns individual elements R_ij for use in Dyad equations.

"R(1,1) of 3-2-1 body-to-ECI rotation matrix"
function rot321_11(phi, theta, psi)
    return cos(theta) * cos(psi)
end

"R(1,2) of 3-2-1 body-to-ECI rotation matrix"
function rot321_12(phi, theta, psi)
    return sin(phi) * sin(theta) * cos(psi) - cos(phi) * sin(psi)
end

"R(1,3) of 3-2-1 body-to-ECI rotation matrix"
function rot321_13(phi, theta, psi)
    return cos(phi) * sin(theta) * cos(psi) + sin(phi) * sin(psi)
end

"R(2,1) of 3-2-1 body-to-ECI rotation matrix"
function rot321_21(phi, theta, psi)
    return cos(theta) * sin(psi)
end

"R(2,2) of 3-2-1 body-to-ECI rotation matrix"
function rot321_22(phi, theta, psi)
    return sin(phi) * sin(theta) * sin(psi) + cos(phi) * cos(psi)
end

"R(2,3) of 3-2-1 body-to-ECI rotation matrix"
function rot321_23(phi, theta, psi)
    return cos(phi) * sin(theta) * sin(psi) - sin(phi) * cos(psi)
end

"R(3,1) of 3-2-1 body-to-ECI rotation matrix"
function rot321_31(phi, theta, psi)
    return -sin(theta)
end

"R(3,2) of 3-2-1 body-to-ECI rotation matrix"
function rot321_32(phi, theta, psi)
    return sin(phi) * cos(theta)
end

"R(3,3) of 3-2-1 body-to-ECI rotation matrix"
function rot321_33(phi, theta, psi)
    return cos(phi) * cos(theta)
end

# --- Body-to-ECI vector rotation ---
# v_eci = R * v_body  (using individual element functions)

"Rotate body-frame vector to ECI: x-component"
function body_to_eci_x(phi, theta, psi, bx, by, bz)
    return rot321_11(phi, theta, psi) * bx +
           rot321_12(phi, theta, psi) * by +
           rot321_13(phi, theta, psi) * bz
end

"Rotate body-frame vector to ECI: y-component"
function body_to_eci_y(phi, theta, psi, bx, by, bz)
    return rot321_21(phi, theta, psi) * bx +
           rot321_22(phi, theta, psi) * by +
           rot321_23(phi, theta, psi) * bz
end

"Rotate body-frame vector to ECI: z-component"
function body_to_eci_z(phi, theta, psi, bx, by, bz)
    return rot321_31(phi, theta, psi) * bx +
           rot321_32(phi, theta, psi) * by +
           rot321_33(phi, theta, psi) * bz
end

# --- ECI-to-body vector rotation ---
# v_body = R^T * v_eci  (transpose of body-to-ECI)

"Rotate ECI vector to body frame: x-component"
function eci_to_body_x(phi, theta, psi, ex, ey, ez)
    return rot321_11(phi, theta, psi) * ex +
           rot321_21(phi, theta, psi) * ey +
           rot321_31(phi, theta, psi) * ez
end

"Rotate ECI vector to body frame: y-component"
function eci_to_body_y(phi, theta, psi, ex, ey, ez)
    return rot321_12(phi, theta, psi) * ex +
           rot321_22(phi, theta, psi) * ey +
           rot321_32(phi, theta, psi) * ez
end

"Rotate ECI vector to body frame: z-component"
function eci_to_body_z(phi, theta, psi, ex, ey, ez)
    return rot321_13(phi, theta, psi) * ex +
           rot321_23(phi, theta, psi) * ey +
           rot321_33(phi, theta, psi) * ez
end

# --- Gravity gradient torque ---
# τ_gg = (3μ/r^5) * (r_body × I·r_body)
# where r_body = R^T * r_eci
#
# Returns each torque component separately for use in Dyad.

"Gravity gradient torque x-component (body frame)"
function gg_torque_x(x, y, z, phi, theta, psi, Ixx, Iyy, Izz, mu)
    r = sqrt(x^2 + y^2 + z^2)
    # Position in body frame
    rb_x = eci_to_body_x(phi, theta, psi, x, y, z)
    rb_y = eci_to_body_y(phi, theta, psi, x, y, z)
    rb_z = eci_to_body_z(phi, theta, psi, x, y, z)
    # I * r_body
    Ir_x = Ixx * rb_x
    Ir_y = Iyy * rb_y
    Ir_z = Izz * rb_z
    # Cross product: r_body × (I * r_body), x-component
    # (r × Ir)_x = rb_y * Ir_z - rb_z * Ir_y
    cross_x = rb_y * Ir_z - rb_z * Ir_y
    return 3 * mu / r^5 * cross_x
end

"Gravity gradient torque y-component (body frame)"
function gg_torque_y(x, y, z, phi, theta, psi, Ixx, Iyy, Izz, mu)
    r = sqrt(x^2 + y^2 + z^2)
    rb_x = eci_to_body_x(phi, theta, psi, x, y, z)
    rb_y = eci_to_body_y(phi, theta, psi, x, y, z)
    rb_z = eci_to_body_z(phi, theta, psi, x, y, z)
    Ir_x = Ixx * rb_x
    Ir_y = Iyy * rb_y
    Ir_z = Izz * rb_z
    # (r × Ir)_y = rb_z * Ir_x - rb_x * Ir_z
    cross_y = rb_z * Ir_x - rb_x * Ir_z
    return 3 * mu / r^5 * cross_y
end

"Gravity gradient torque z-component (body frame)"
function gg_torque_z(x, y, z, phi, theta, psi, Ixx, Iyy, Izz, mu)
    r = sqrt(x^2 + y^2 + z^2)
    rb_x = eci_to_body_x(phi, theta, psi, x, y, z)
    rb_y = eci_to_body_y(phi, theta, psi, x, y, z)
    rb_z = eci_to_body_z(phi, theta, psi, x, y, z)
    Ir_x = Ixx * rb_x
    Ir_y = Iyy * rb_y
    Ir_z = Izz * rb_z
    # (r × Ir)_z = rb_x * Ir_y - rb_y * Ir_x
    cross_z = rb_x * Ir_y - rb_y * Ir_x
    return 3 * mu / r^5 * cross_z
end

# --- Cross product components (for ReactionJet torque) ---

"Cross product x-component: (a × b)_x = ay*bz - az*by"
function cross_x(ax, ay, az, bx, by, bz)
    return ay * bz - az * by
end

"Cross product y-component: (a × b)_y = az*bx - ax*bz"
function cross_y(ax, ay, az, bx, by, bz)
    return az * bx - ax * bz
end

"Cross product z-component: (a × b)_z = ax*by - ay*bx"
function cross_z(ax, ay, az, bx, by, bz)
    return ax * by - ay * bx
end
