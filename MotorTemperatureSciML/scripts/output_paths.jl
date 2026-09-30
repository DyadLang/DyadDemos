"""Parse script output paths without depending on the modeling packages.

Relative paths are resolved against the caller's working directory. Validation
uses the shipped calibration unless --calibration explicitly selects another fit.
"""
function output_paths(args; default_dir, default_calibration = nothing)
    out_dir = default_dir
    calibration = default_calibration
    i = 1
    while i <= length(args)
        flag = args[i]
        valid = flag == "--out-dir" ||
                (flag == "--calibration" && !isnothing(default_calibration))
        valid || throw(ArgumentError("Unknown option: $flag"))
        i < length(args) && !startswith(args[i + 1], "--") ||
            throw(ArgumentError("$flag requires a path"))
        value = args[i + 1]
        isempty(strip(value)) && throw(ArgumentError("$flag requires a nonempty path"))
        if flag == "--out-dir"
            out_dir = value
        else
            calibration = value
        end
        i += 2
    end
    return (; out_dir = abspath(expanduser(out_dir)),
        calibration = isnothing(calibration) ? nothing : abspath(expanduser(calibration)))
end
