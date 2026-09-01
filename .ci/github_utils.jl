function post_status(; name, type, repo::String = "JuliaComputing/DyadDemos", subfolder = nothing, kwargs...)
    !haskey(ENV, "CI") && return
    try # make this non-fatal and silent
        # Runs only after the deploy decision, so the environment is already validated.
        sha = nothing
        if get(ENV, "GITHUB_EVENT_NAME", nothing) == "pull_request"
            event_path = get(ENV, "GITHUB_EVENT_PATH", nothing)
            event_path === nothing && return
            event = JSON.parsefile(event_path)
            if haskey(event, "pull_request") &&
                    haskey(event["pull_request"], "head") &&
                    haskey(event["pull_request"]["head"], "sha")
                sha = event["pull_request"]["head"]["sha"]
            end
        elseif get(ENV, "GITHUB_EVENT_NAME", nothing) == "push"
            sha = get(ENV, "GITHUB_SHA", nothing)
        end
        sha === nothing && return
        return post_github_status(name, type, gha.github_repository, repo, sha, subfolder)
    catch
        @debug "Failed to post status"
    end
end

function post_github_status(name::S, type::S, source::S, repo::S, sha::S, subfolder = nothing) where {S <: String}
    try
        Sys.which("curl") === nothing && return
        ## Extract owner and repository names
        source_owner, source_repo = split(source, '/')
        m = match(r"^github.com\/(.+?)\/(.+?)(.git)?$", repo)
        m === nothing && return
        deploy_owner = String(m.captures[1])
        deploy_repo = String(m.captures[2])

        ## Need an access token for this
        auth = get(ENV, "GITHUB_TOKEN", nothing)
        auth === nothing && return
        # construct the curl call
        cmd = `curl -sX POST`
        push!(cmd.exec, "-H", "Authorization: token $(auth)")
        push!(cmd.exec, "-H", "User-Agent: Dyad Demo Bot")
        push!(cmd.exec, "-H", "Content-Type: application/json")
        json = Dict{String, Any}("context" => name, "state" => type)
        if type == "pending"
            json["description"] = "Testing $name in progress"
        elseif type == "success"
            json["description"] = "Testing $name succeeded"
        elseif type == "error"
            json["description"] = "Testing $name errored"
        elseif type == "failure"
            json["description"] = "Testing $name failed"
        else
            error("unsupported type: $type")
        end
        push!(cmd.exec, "-d", JSON.json(json))
        push!(cmd.exec, "https://api.github.com/repos/$(source_owner)/$(source_repo)/statuses/$(sha)")
        # Run the command (silently)
        io = IOBuffer()
        res = run(pipeline(cmd; stdout = io, stderr = devnull))
        @debug "Response of curl POST request" response = String(take!(io))
    catch
        @debug "Failed to post status"
    end
    return nothing
end

