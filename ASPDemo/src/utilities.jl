using ModelingToolkit

function KineticExp(T, 
    a,
    b,
    T_ref  # Reference temperature
    )
    k = a * exp(b * (T - T_ref))
end

# Takacs double-exponential sedimentation velocity function.
function vS_TakacsDoubleExponential(
    X, # total sludge concentration in m-th layer in g/m3 or mg/l
    Xf, # total sludge concentration in clarifier feed in g/m3 or mg/l
    v0slash=250.0, # max. settling velocity in m/d
    v0=474.0, # max. Vesilind settl. veloc. in m/d
    rh=0.000576, # hindered zone settl. param. in m3/(g SS)
    rp=0.00286, # flocculant zone settl. param. in m3/(g SS)
    fns=0.00228 #  non-settleable fraction in -
    )

    vS = max(0.0, min(v0slash, v0 * (exp(-rh * (X - fns * Xf)) - exp(-rp * (X - fns * Xf)))))
end