module ASPDemo

using DataInterpolations

abstract type AbstractMedium end

include("utilities.jl")
include("ASM1.jl")

# ------------------------------------------------------------------
# Workaround for SymbolicUtils bug: Array{Real} (a UnionAll) is passed
# where a DataType is expected during mtkcompile alias elimination.
# This occurs because vector-valued symbolic parameters/variables
# produce intermediate expressions typed as Array{Real} (missing the
# ndims parameter). Two patches are needed:
#   1. _numeric_or_arrnumeric_type must accept UnionAll types
#   2. The Term constructor must convert UnionAll → concrete DataType
# Patches are applied in __init__() to avoid precompilation restrictions.
# ------------------------------------------------------------------
import SymbolicUtils

function __init__()
    _BSImpl = SymbolicUtils.BasicSymbolicImpl

    @eval function SymbolicUtils._numeric_or_arrnumeric_type(S::UnionAll)
        return S <: Union{Number, AbstractArray{<:Number}}
    end

    @eval @inline function $(_BSImpl).Term{T}(
            f, args;
            metadata = nothing,
            type,
            shape = SymbolicUtils.default_shape(type),
            unsafe = false) where {T}
        if type isa UnionAll && type <: AbstractArray
            type = Vector{eltype(type)}
        end
        metadata = SymbolicUtils.parse_metadata(metadata)
        shape    = SymbolicUtils.parse_shape(shape)
        args     = SymbolicUtils.parse_args(T, args)
        props    = SymbolicUtils.ordered_override_properties($(_BSImpl).Term)
        var      = $(_BSImpl).Term{T}(f, args, metadata, shape, type, props...)
        if !unsafe
            var = SymbolicUtils.hashcons(var)
        end
        return var
    end
end
# ------------------------------------------------------------------

include("../generated/module.jl")
    
end # module ASPDemo