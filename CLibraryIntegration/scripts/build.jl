# Stage 1: compile locally; no binary is stored in git or downloaded.
using Libdl
function build_tiremodel()
    root = normpath(joinpath(@__DIR__, ".."))
    run(`make -s -C $(joinpath(root, "csrc"))`)
    install_dir = mkpath(joinpath(root, "TireModel_jll", "override", "lib"))
    source = joinpath(root, "csrc", "build", "libtiremodel." * Libdl.dlext)
    destination = joinpath(install_dir, basename(source))
    if !isfile(destination) || mtime(destination) < mtime(source)
        cp(source, destination; force=true)
    end
    destination
end
abspath(PROGRAM_FILE) == (@__FILE__) && build_tiremodel()
