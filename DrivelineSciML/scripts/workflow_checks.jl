# Shared by the executable workflows and their failure-path regression tests.
using DyadInterface: SciMLBase

function require_calibration_success(r, label)
    println(label, ": retcode=", r.retcode, " objective=", r.original.objective)
    SciMLBase.successful_retcode(r.retcode) ||
        error("$label calibration failed ($(r.retcode)); refusing to use or export this fit")
    all(isfinite, r.u) || error("$label returned nonfinite parameters")
    isfinite(r.original.objective) || error("$label returned a nonfinite objective")
    r.likely_wrong && error("$label flagged the fit as likely wrong")
    return r
end

function require_simulation_success(sol, stop, label)
    SciMLBase.successful_retcode(sol.retcode) || error("$label ODE failed ($(sol.retcode))")
    last(sol.t) == stop || error("$label stopped at $(last(sol.t)), expected $stop")
    all(u -> all(isfinite, u), sol.u) || error("$label returned nonfinite states")
    return sol
end
