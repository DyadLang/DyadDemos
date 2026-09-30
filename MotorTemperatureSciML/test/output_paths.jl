module OutputPathTests
using Test
include("../scripts/output_paths.jl")

@testset "Run outputs and reference inputs stay separate" begin
    mktempdir() do dir
        reference = joinpath(dir, "assets", "calibrated_params.csv")
        mkpath(dirname(reference))
        write(reference, "reference fit")
        defaults = output_paths(String[]; default_dir = joinpath(dir, "runs"),
            default_calibration = reference)
        custom = output_paths(["--out-dir", joinpath(dir, "my run")];
            default_dir = defaults.out_dir, default_calibration = reference)
        @test defaults.calibration == custom.calibration == reference
        @test custom.out_dir == joinpath(dir, "my run")
        @test !isdir(custom.out_dir) # Parsing alone creates nothing.
        selected = output_paths(["--calibration", "runs/quick/calibrated_params.csv"];
            default_dir = defaults.out_dir, default_calibration = reference)
        @test selected.calibration == abspath("runs/quick/calibrated_params.csv")
        @test selected.out_dir == defaults.out_dir
        @test read(reference, String) == "reference fit"
        for args in (["--out-dir"], ["--out-dir", "--calibration"],
                     ["--out-dir", ""], ["--typo", "somewhere"],
                     ["--calibration", reference])
            @test_throws ArgumentError output_paths(args; default_dir = defaults.out_dir)
        end
    end
end
end
