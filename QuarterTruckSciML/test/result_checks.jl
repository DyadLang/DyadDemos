using Test
using DyadInterface
include("../scripts/result_checks.jl")

@testset "Optimizer acceptance retains raw stopping criteria" begin
    # Reproduce the reviewed false positive without the expensive ODE training.
    function fit(; retcode=DyadInterface.SciMLBase.ReturnCode.Success,
                 gradient=0.09430872088659324, g_converged=false,
                 objective=0.38384846067991113, raw=nothing)
        evidence = isnothing(raw) ?
            (; stopped_by=(; f_converged=true, g_converged),
               g_residual=gradient, g_abstol=1e-8,
               f_abschange=6.05356569405302e-5, f_abstol=1e-4) : raw
        (; retcode, u=[1.0], likely_wrong=false,
           original=(; objective, stats=nothing, original=evidence))
    end
    @test_throws ErrorException check_lbfgs_optimality(fit())
    @test isnothing(check_lbfgs_optimality(fit(gradient=1e-9, g_converged=true)))
    @test_throws ErrorException check_lbfgs_optimality(fit(gradient=NaN, g_converged=true))
    @test_throws ErrorException check_lbfgs_optimality(fit(gradient=1e-9, g_converged=true,
        retcode=DyadInterface.SciMLBase.ReturnCode.MaxIters))
    @test_throws ErrorException check_lbfgs_optimality(fit(raw=(;)))
    @test_throws ErrorException check_lbfgs_optimality(fit(objective=NaN))
    @test isnothing(check_calibration(fit(raw=(; status=:SOLVE_SUCCEEDED))))
    @test_throws ErrorException check_calibration(fit(raw=(; status=:SOLVED_TO_ACCEPTABLE_LEVEL)))
    @test_throws ErrorException check_calibration(fit(raw=(; status=:USER_REQUESTED_STOP)))
    io = IOBuffer()
    report_optimizer(io, fit())
    evidence = String(take!(io))
    @test occursin("optimization_retcode=Success", evidence)
    @test occursin("g_residual=0.09430872088659324", evidence)
    @test occursin("f_abstol=0.0001", evidence)
end

@testset "Transient exports require the requested horizon" begin
    sol = (; retcode=DyadInterface.SciMLBase.ReturnCode.Success,
             t=[0.0, 1.0], u=[[0.0], [1.0]])
    @test isnothing(check_transient(sol, 0.0, 1.0))
    @test_throws ErrorException check_transient(sol, 0.0, 2.0)
    @test_throws ErrorException check_transient(merge(sol, (; u=[[NaN], [1.0]])), 0.0, 1.0)
    @test_throws ErrorException check_transient(merge(sol,
        (; retcode=DyadInterface.SciMLBase.ReturnCode.MaxIters)), 0.0, 1.0)
end
