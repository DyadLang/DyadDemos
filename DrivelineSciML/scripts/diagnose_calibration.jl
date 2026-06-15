#=
Diagnose the two-stage calibration: WHY does the fit not land on the truth?

Runs both stages with full calibration diagnostics (gradient tracking), then for
each stage uses the DyadModelOptimizer diagnostic system to separate two very
different failure modes:

  (A) optimizer failure   — did MadNLP actually converge?            → assess_health
  (B) identifiability /   — is `truth` even the minimizer of the      → objective()
      structural bias        loss for this experiment?                  loss probe

The key test is (B): rebuild the exact objective the optimizer minimized and
evaluate it at the recovered optimum vs. at the ground-truth parameters. If
loss(truth) > loss(fitted), the optimizer did its job — the gap to truth is
NOT an optimization problem but a property of the data/model (decoupling bias,
flat valleys). A 1-D sweep of each parameter then shows which directions are
well-determined (sharp minimum near truth) vs. weakly identifiable (flat).
=#

using DrivelineSciML
using DyadInterface
using DyadModelOptimizer
using DyadModelOptimizer: objective, get_diagnostics, get_optimizer, get_losses,
                          get_gradients, get_iterations, assess_health,
                          format_diagnostic_summary, search_space_names
using LinearAlgebra: norm
using Printf
using Tables

const NOMINAL = (k1 = 200.0, c1 = 2.0, alpha = 30.0, A_bw = 1.0, beta_bw = 3.0, gamma_bw = 0.5)
const TRUTH   = (k1 = 300.0, c1 = 1.0, alpha = 50.0, A_bw = 1.0, beta_bw = 5.0, gamma_bw = 0.5)

const FULL_DIAG = DyadModelOptimizer.DiagnosticsLevel.CalibrationTracking(
    track_gradients = true, save_solutions = false)

# Strip any model namespace: `Tables.columnnames` yields MTK-namespaced symbols
# like `model₊k1` (the `₊` separator) — keep only the final component (`k1`).
bare(name) = Symbol(last(split(string(name), ['.', '₊'])))

rule(c = "─", n = 78) = println("  ", repeat(c, n))

# ── Layer A: did the optimizer converge? ──────────────────────────────────────
function report_convergence(label, r)
    println()
    println("══ $label · optimizer convergence ", repeat("═", 78 - length(label) - 26))
    diag  = get_diagnostics(r.alg)
    opt   = get_optimizer(r.alg)
    losses = get_losses(diag)
    iters  = get_iterations(diag)
    @printf "  optimizer        : %s\n" nameof(typeof(opt))
    @printf "  retcode          : %s   likely_wrong = %s\n" r.retcode r.likely_wrong
    @printf "  elapsed          : %.1f s   recorded states = %d\n" r.elapsed length(losses)
    if !isempty(losses)
        @printf "  loss             : %.6g  →  %.6g   (×%.2g reduction)\n" first(losses) last(losses) (first(losses) / max(last(losses), eps()))
    end
    grads = get_gradients(diag)
    if !isempty(grads)
        gn = norm.(grads)
        @printf "  ‖∇loss‖          : %.4g  →  %.4g   (final gradient norm)\n" first(gn) last(gn)
    end
    println()
    println(format_diagnostic_summary(assess_health(r)))
end

# ── Layer B: is `truth` the minimizer? (identifiability probe) ────────────────
# Build the exact objective the optimizer minimized and evaluate it off-optimum.
function probe_identifiability(label, r, stage_truth)
    println()
    println("══ $label · identifiability probe ", repeat("═", 78 - length(label) - 27))
    cost  = objective(r.prob, r.alg)
    syms  = collect(search_space_names(r.prob))      # symbolic vars, internal order
    names = collect(Tables.columnnames(r))           # pretty names, same order
    fitted = collect(r.u)

    pairs(vals) = [syms[i] => vals[i] for i in eachindex(syms)]
    truth_vec = [Float64(stage_truth[bare(n)]) for n in names]

    L_fit   = cost(pairs(fitted))
    L_truth = cost(pairs(truth_vec))

    # sanity: cost(fitted) should match the loss the optimizer reported
    diag = get_diagnostics(r.alg)
    losses = get_losses(diag)
    if !isempty(losses)
        @printf "  [check] cost(fitted)=%.6g  vs  final tracked loss=%.6g\n" L_fit last(losses)
    end
    println()
    @printf "  %-12s  %-12s  %-12s  %-12s\n" "parameter" "fitted" "truth" "truth/fit"
    rule()
    for (i, n) in enumerate(names)
        @printf "  %-12s  %-12.5g  %-12.5g  %-+12.1f%%\n" bare(n) fitted[i] truth_vec[i] 100*(truth_vec[i]-fitted[i])/fitted[i]
    end
    rule()
    @printf "  loss at fitted optimum : %.6g\n" L_fit
    @printf "  loss at ground truth   : %.6g\n" L_truth
    if L_truth > L_fit
        @printf "  →  truth fits the data %.2g× WORSE than the recovered optimum.\n" (L_truth / max(L_fit, eps()))
        println("     The optimizer is NOT the problem — truth is not the loss minimizer")
        println("     here (decoupling bias / unmodeled dynamics). Recovering it exactly")
        println("     would require fitting the data WORSE.")
    else
        @printf "  →  truth fits AT LEAST AS WELL (%.2g×). The optimizer stopped short of\n" (L_truth / max(L_fit, eps()))
        println("     truth despite a lower loss being available — suspect optimizer/bounds.")
    end

    # 1-D loss sweeps: vary one parameter, hold the rest at the fitted optimum.
    println()
    println("  1-D loss sweeps (others held at fitted optimum):")
    println("  a flat curve ⇒ weakly identifiable; a sharp min away from truth ⇒ biased")
    for (i, n) in enumerate(names)
        center = fitted[i]
        factors = (0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0)
        println()
        @printf "  %s  (fitted=%.4g, truth=%.4g)\n" bare(n) center truth_vec[i]
        @printf "    %-10s %-12s %-10s\n" "value" "loss" "rel.toMin"
        vals = Float64[]
        ls   = Float64[]
        for f in factors
            v = center * f
            x = copy(fitted); x[i] = v
            push!(vals, v); push!(ls, cost(pairs(x)))
        end
        Lmin = minimum(ls)
        for (v, L) in zip(vals, ls)
            marker = isapprox(v, center; rtol = 1e-6) ? " ← fitted" : ""
            @printf "    %-10.4g %-12.5g %-10.3g%s\n" v L (L / max(Lmin, eps()))  marker
        end
        # curvature proxy: how much does the loss rise at ±25%?
        span = (maximum(ls) - Lmin) / max(Lmin, eps())
        verdict = span < 0.05 ? "FLAT  → weakly identifiable" :
                  span < 0.5  ? "shallow" : "sharp → well-determined"
        @printf "    range over sweep: %.2g× → %s\n" (maximum(ls)/max(Lmin,eps())) verdict
    end
end

# ══ Stage 1: Maxwell branch (k1, c1) from chirp ═══════════════════════════════
@info "Stage 1: Maxwell branch (k1, c1) from chirp — running with full diagnostics"
res1 = DrivelineSciML.DrivelineStage1CalibrationAnalysis(; name = :stage1, diagnostics = FULL_DIAG)
r1 = res1.r
report_convergence("STAGE 1", r1)
probe_identifiability("STAGE 1", r1, TRUTH)

# ══ Stage 2: Bouc-Wen (alpha, beta_bw, gamma_bw), Maxwell frozen to Stage 1 ═══
@info "Stage 2: Bouc-Wen (alpha, beta_bw, gamma_bw), Maxwell frozen to Stage 1 fit"
# Map the Stage 1 fit back to (k1, c1) by name so freezing is order-independent.
n1 = collect(Tables.columnnames(r1))
fit1 = Dict(bare(n1[i]) => collect(r1.u)[i] for i in eachindex(n1))
stage2_model = DrivelineSciML.TestDrivelineSlowCycle(;
    name = :TestDrivelineSlowCycle, k1 = fit1[:k1], c1 = fit1[:c1])
res2 = DrivelineSciML.DrivelineStage2CalibrationAnalysis(;
    name = :stage2, model = stage2_model, diagnostics = FULL_DIAG)
r2 = res2.r
report_convergence("STAGE 2", r2)
probe_identifiability("STAGE 2", r2, TRUTH)

println()
@info "Diagnosis complete. Stage 1 Maxwell frozen for Stage 2: k1=$(round(fit1[:k1],digits=3)), c1=$(round(fit1[:c1],digits=3))"
