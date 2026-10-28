using ModelingToolkit

@testset "HL-20 aerodynamic core" begin
    data = HL20Demo._data()
    @test data.atm_sig(0.0) ≈ 1.0 atol=1e-3
    @test 1100 < data.atm_vs(0.0) < 1130
    @test HL20Demo.idx1d("CL0A") == HL20Demo.idx1d("CL0A0")
    @test HL20Demo.grp2dr("CLBFLL") == HL20Demo.idx2dr("CLBFLL0")
    @test HL20Demo.grp2de("CLRUD") == HL20Demo.idx2de("CLRUD0")
    @test_throws ErrorException HL20Demo.idx1d("missing-table")
    for alpha in (-5.0, 0.0, 10.0, 30.0)
        @test isfinite(HL20Demo.hl20_poly1d(HL20Demo.idx1d("CL0A"), alpha, 0.2))
        @test isfinite(HL20Demo.hl20_poly2dr(HL20Demo.grp2dr("CLBFLL"), alpha, 0.0, 0.2))
        @test isfinite(HL20Demo.hl20_poly2de(HL20Demo.grp2de("CLRUD"), alpha, 0.0, 0.2))
    end
    # Construction exercises all table indices and registered symbolic functions.
    @named aero = HL20Demo.shared.HL20Aero()
    @test !isempty(equations(aero))
    @test isequal(ModelingToolkit.getname(aero), :aero)
end
