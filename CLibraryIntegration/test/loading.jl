@testset "Two loading paths" begin
    system_script = joinpath(ROOT, "scripts", "a_system_library.jl")
    pathvar = Sys.isapple() ? "DYLD_LIBRARY_PATH" : "LD_LIBRARY_PATH"
    cmd = `$(Base.julia_cmd()) --startup-file=no $system_script`
    output = read(addenv(cmd, pathvar => joinpath(ROOT, "csrc", "build")), String)
    @test occursin("system library: Fy =", output)

    # A distinct pathname proves the preference won over the override directory.
    mktempdir() do dir
        library = cp(C.libtiremodel, joinpath(dir, basename(C.libtiremodel)))
        write(joinpath(dir, "Project.toml"), """
        [deps]
        TireModel_jll = "05ed9bfa-a1af-4766-ad26-33c8c1e93ffc"
        [sources]
        TireModel_jll = {path = $(repr(joinpath(ROOT, "TireModel_jll")))}
        """)
        write(joinpath(dir, "LocalPreferences.toml"), """
        [TireModel_jll]
        libtiremodel_path = $(repr(library))
        """)
        code = "using Pkg; Pkg.instantiate(); using TireModel_jll; " *
            "@assert TireModel_jll.libtiremodel == $(repr(library)); " *
            "include($(repr(joinpath(ROOT, "scripts", "b_local_jll.jl"))))"
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$dir -e $code`
        # Pkg.test restricts LOAD_PATH; this subprocess owns a different project.
        output = read(addenv(cmd, "JULIA_LOAD_PATH" => "@:@stdlib"), String)
        @test occursin("local JLL: Fy =", output)
    end
end
