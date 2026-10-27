# Stage 5: only callbacks may advance the foreign state.
struct TireParams
    mf::MFParams
    sigma::Cdouble
    Fz0::Cdouble
end

mutable struct TireHandle
    ptr::Ptr{Cvoid}
    time::Float64
    alpha::Float64
    vx::Float64
    Fz::Float64
    allocations::Int
    frees::Int
end
# cconvert keeps the owner alive while C uses its pointer.
Base.cconvert(::Type{Ptr{Cvoid}}, h::TireHandle) = h
Base.unsafe_convert(::Type{Ptr{Cvoid}}, h::TireHandle) = h.ptr

function TireHandle()
    h = TireHandle(C_NULL, 0, 0, 0, 0, 0, 0)
    finalizer(close, h)
    h
end
function Base.close(h::TireHandle)
    if h.ptr != C_NULL
        @ccall libtiremodel.tm_tire_free(h::Ptr{Cvoid})::Cvoid
        h.ptr = C_NULL
        h.frees += 1
    end
    nothing
end
check_status(code) = code == 0 ? nothing : error("tiremodel status $code")
function tire_state(h::TireHandle)
    buf = zeros(3)
    check_status(@ccall libtiremodel.tm_tire_get_state(h::Ptr{Cvoid}, buf::Ptr{Cdouble}, 3::Cint)::Cint)
    buf
end
function set_tire_state!(h::TireHandle, buf::Vector{Float64})
    check_status(@ccall libtiremodel.tm_tire_set_state(h::Ptr{Cvoid}, buf::Ptr{Cdouble}, length(buf)::Cint)::Cint)
    h.time = buf[1]
    nothing
end
get_fy(h::TireHandle) = @ccall libtiremodel.tm_tire_get_fy(h::Ptr{Cvoid})::Cdouble

function initialize_tire!(m, o, ctx, integrator)
    h = o.handle
    close(h)
    p = Ref(TireParams(MFParams(o.B, o.C, o.D, o.E), o.sigma, o.Fz))
    h.ptr = @ccall libtiremodel.tm_tire_new(p::Ref{TireParams})::Ptr{Cvoid}
    h.ptr == C_NULL && error("could not create tire")
    h.allocations += 1
    check_status(@ccall libtiremodel.tm_tire_reset(h::Ptr{Cvoid}, o.t::Cdouble, o.alpha0::Cdouble)::Cint)
    h.time, h.alpha, h.vx, h.Fz = o.t, o.alpha, o.vx, o.Fz
    (; Fy_hold = get_fy(h))
end
function step_tire!(m, o, ctx, integrator)
    h = o.handle
    dt = o.t - h.time
    # Complete the previous interval with its LEFT-endpoint inputs. Sampling
    # current inputs before advancing would silently change the coupling scheme.
    check_status(@ccall libtiremodel.tm_tire_step(h::Ptr{Cvoid}, h.time::Cdouble,
        dt::Cdouble, h.alpha::Cdouble, h.vx::Cdouble, h.Fz::Cdouble)::Cint)
    h.time, h.alpha, h.vx, h.Fz = o.t, o.alpha, o.vx, o.Fz
    (; Fy_hold = get_fy(h))
end
function finalize_tire!(m, o, ctx, integrator)
    close(o.handle)
    (;)
end

function RelaxationTire(; name, Fz=4000.0, B=10.0, C=1.3, D=1.0, E=0.97,
        sigma=0.5, vx=20.0, dt=0.005, alpha0=0.0)
    dt > 0 || throw(ArgumentError("dt must be positive"))
    @variables alpha(t_nounits) [input=true]
    @variables Fy(t_nounits) [output=true]
    @parameters (handle::TireHandle) = TireHandle() [tunable=false]
    @discretes Fy_hold(t_nounits) [tunable=false]
    observed = (; handle, alpha, t=t_nounits, Fz, B, C, D, E, sigma, vx, alpha0)
    modified = (; Fy_hold)
    cb = SymbolicDiscreteCallback(dt,
        ImperativeAffect(step_tire!; observed, modified);
        initialize=ImperativeAffect(initialize_tire!; observed, modified),
        finalize=ImperativeAffect(finalize_tire!; observed=(; handle)),
        reinitializealg=ModelingToolkit.SciMLBase.NoInit())
    # A pure initialization equation supplies a consistent held force before
    # callback initialization. The continuous equation reads only this parameter.
    System([Fy ~ Fy_hold], t_nounits, [alpha, Fy], [handle, Fy_hold]; name,
        initialization_eqs=[Fy_hold ~ julia_mf(alpha0, Fz, B, C, D, E)],
        discrete_events=[cb])
end
