using Logging: global_logger
using GitHubActions: GitHubActionsLogger, group
get(ENV, "GITHUB_ACTIONS", "false") == "true" && global_logger(GitHubActionsLogger())

import Pkg
import DyadHarness

folders = filter(readdir(dirname(@__DIR__); join = true)) do path
    isdir(path) && !startswith(basename(path), ".") && isdir(joinpath(path, "dyad"))
end

function test_demo(folder)
    try
        @info "Instantiating project" folder
        withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
            Pkg.activate(folder)
            Pkg.resolve()
            Pkg.instantiate()
        end

        # Regenerate before testing, so tests exercise the pinned compiler output.
        @info "Compiling Dyad sources" folder
        cd(folder) do
            run(`$(DyadHarness.dyad_cli_path) compile .`)
        end

        @info "Running tests" folder
        Pkg.test()

        @info "Generating Dyad documentation" folder
        cd(folder) do
            run(`$(DyadHarness.dyad_cli_path) document $(basename(folder))`)
        end

        docs_dir = joinpath(folder, "docs")
        if isfile(joinpath(docs_dir, "Project.toml"))
            @info "Instantiating docs environment" folder
            withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
                Pkg.activate(docs_dir)
                Pkg.instantiate()
            end
        end
        return true
    catch error
        @error "Demo validation failed" folder exception = (error, catch_backtrace())
        return false
    finally
        Pkg.activate(@__DIR__)
    end
end

failed = String[]
for folder in folders
    ok = group("Testing $(basename(folder))") do
        test_demo(folder)
    end
    ok || push!(failed, basename(folder))
end

# Still check every project, but never turn a failed demo into a green CI job.
isempty(failed) || error("Demo validation failed: $(join(failed, ", "))")
