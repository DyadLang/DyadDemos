using Logging: global_logger
using GitHubActions: GitHubActionsLogger, group
get(ENV, "GITHUB_ACTIONS", "false") == "true" && global_logger(GitHubActionsLogger())

import Pkg
import DyadHarness

# Gives us the ability to report what succeeded and what failed
include("github_utils.jl")

folders = filter(readdir(dirname(@__DIR__); join = true)) do path
    isdir(path) &&
    !startswith(basename(path), ".") &&
    isdir(joinpath(path, "dyad"))
end

for folder in folders
    group("Testing $folder") do
        @info "Instantiating project" 
        try
            withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do 
                Pkg.activate(folder)
                Pkg.resolve()  
                Pkg.instantiate()          
            end
        catch e
            @error "Failed to instantiate project" error = e
            post_status(name = "$(basename(folder))/instantiate", type = "failure")
            return
        finally
            Pkg.activate(@__DIR__)
        end

        @info "Running tests"
        test_result = try
            Pkg.activate(folder)
            Pkg.test()
        catch e
            @error "Tests errored" error = e
            post_status(name = "$(basename(folder))/test", type = "error")
            return
        finally
            Pkg.activate(@__DIR__)
        end

        @info "Compiling with latest `dyad-lang`"
        compile_result = cd(folder) do
            success(`$(DyadHarness.dyad_cli_path) compile .`)
        end
        if compile_result == false
            @error "Compilation failed"
            post_status(name = "$(basename(folder))/dyad-compile", type = "failure")
            return
        end

        @info "Running Dyad doc-gen"
        docgen_result = cd(folder) do
            success(`$(DyadHarness.dyad_cli_path) document $(basename(folder))`)
        end
        if docgen_result == false
            @error "Doc-gen failed"
            post_status(name = "$(basename(folder))/dyad-doc-gen", type = "failure")
        end

        # If the demo ships a docs/ gallery page (consumed by DyadDocs'
        # make_examples.jl), assert its docs/Project.toml resolves standalone.
        # The env's [sources] dev's the demo itself from "..", so no explicit
        # Pkg.develop is needed. This only checks the demo author's own docs env
        # — the DyadDocs doc-tooling is seeded separately at docs-build time.
        docs_dir = joinpath(folder, "docs")
        if isfile(joinpath(docs_dir, "Project.toml"))
            @info "Instantiating docs env"
            docs_ok = try
                withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
                    Pkg.activate(docs_dir)
                    Pkg.instantiate()    # [sources] ".." dev's the demo itself
                end
                true
            catch e
                @error "docs env failed to instantiate" error = e
                false
            finally
                Pkg.activate(@__DIR__)
            end
            post_status(name = "$(basename(folder))/docs-instantiate",
                        type = docs_ok ? "success" : "failure")
        end

        @info "All steps succeeded"
        post_status(name = "$(basename(folder))/all", type = "success")
    end
end