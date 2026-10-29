# Shared acceptance checks for the headless demo scripts. Keep raw optimizer
# evidence: a SciML Success can mean a function-change stop rather than optimality.
using DyadInterface

function check_finite_fit(r)
    all(isfinite, r.u) && isfinite(r.original.objective) || error("Nonfinite fitted result")
    r.likely_wrong && error("Fit failed the library's calibration diagnostics")
    return nothing
end

function report_optimizer(io, r)
    println(io, "optimization_retcode=", r.retcode,
        " objective=", r.original.objective, " stats=", r.original.stats,
        " likely_wrong=", r.likely_wrong)
    raw = r.original.original
    for field in (:status, :primal_feas, :dual_feas, :stopped_by,
                  :f_abschange, :f_abstol, :g_residual, :g_abstol)
        hasproperty(raw, field) && println(io, field, "=", getproperty(raw, field))
    end
    return nothing
end

function check_lbfgs_optimality(r)
    check_finite_fit(r)
    DyadInterface.SciMLBase.successful_retcode(r.retcode) ||
        error("LBFGS stopped with $(r.retcode)")
    raw = r.original.original
    all(f -> hasproperty(raw, f), (:stopped_by, :g_residual, :g_abstol)) ||
        error("LBFGS gradient evidence unavailable; cannot certify optimality")
    # RC2's optimizer_abstol maps to f_abstol, not this gradient criterion.
    # Do not accept a future adapter's looser gradient tolerance either.
    tolerance = min(raw.g_abstol, 1e-8)
    raw.stopped_by.g_converged && isfinite(raw.g_residual) && raw.g_residual <= tolerance ||
        error("LBFGS optimality not met: |g|=$(raw.g_residual), required ≤ $tolerance; " *
              "retcode=$(r.retcode), stopped_by=$(raw.stopped_by). No accepted weights exported.")
    return nothing
end

function check_calibration(r)
    check_finite_fit(r)
    DyadInterface.SciMLBase.successful_retcode(r.retcode) ||
        error("Calibration stopped with $(r.retcode)")
    raw = r.original.original
    # MadNLP also maps acceptable-level and user stops to SciML Success.
    hasproperty(raw, :status) && string(raw.status) == "SOLVE_SUCCEEDED" ||
        error("Calibration requires raw MadNLP SOLVE_SUCCEEDED")
    return nothing
end

function check_transient(sol, start, stop)
    DyadInterface.SciMLBase.successful_retcode(sol.retcode) || error("ODE failed: $(sol.retcode)")
    isempty(sol.t) && error("ODE returned no samples")
    isapprox(first(sol.t), start; rtol=0, atol=1e-12) &&
        isapprox(last(sol.t), stop; rtol=0, atol=1e-12) || error("ODE did not cover requested horizon")
    all(isfinite, sol.t) && all(u -> all(isfinite, u), sol.u) || error("Nonfinite ODE trajectory")
    return nothing
end
