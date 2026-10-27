# Stage 5: advance the C state only at communication points.
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
end
# cconvert keeps the owner alive while C uses its pointer.
Base.cconvert(::Type{Ptr{Cvoid}}, h::TireHandle) = h
Base.unsafe_convert(::Type{Ptr{Cvoid}}, h::TireHandle) = h.ptr

function TireHandle()
    h = TireHandle(C_NULL, 0, 0, 0, 0)
    finalizer(close, h)
    h
end
function Base.close(h::TireHandle)
    if h.ptr != C_NULL
        @ccall libtiremodel.tm_tire_free(h::Ptr{Cvoid})::Cvoid
        h.ptr = C_NULL
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

function begin_session!(h, Fz, B, C, D, E, sigma, vx, alpha0, t0)
    close(h)
    p = Ref(TireParams(MFParams(B, C, D, E), sigma, Fz))
    h.ptr = @ccall libtiremodel.tm_tire_new(p::Ref{TireParams})::Ptr{Cvoid}
    h.ptr == C_NULL && error("could not create tire")
    check_status(@ccall libtiremodel.tm_tire_reset(h::Ptr{Cvoid}, t0::Cdouble, alpha0::Cdouble)::Cint)
    h.time, h.alpha, h.vx, h.Fz = t0, alpha0, vx, Fz
    1.0
end
function current_fy!(h, alpha, tk, vx, Fz, ready)
    # At the initial tick C is already at tk; later ticks complete the previous interval.
    if tk > h.time
        check_status(@ccall libtiremodel.tm_tire_step(h::Ptr{Cvoid}, h.time::Cdouble,
            (tk-h.time)::Cdouble, h.alpha::Cdouble, h.vx::Cdouble, h.Fz::Cdouble)::Cint)
    end
    h.time, h.alpha, h.vx, h.Fz = tk, alpha, vx, Fz
    get_fy(h)
end
@register_symbolic begin_session!(h::TireHandle, Fz, B, C, D, E, sigma, vx, alpha0, t0)::Real
@register_symbolic current_fy!(h::TireHandle, alpha, tk, vx, Fz, ready)::Real

function RelaxationTire(; name, Fz=4000.0, B=10.0, C=1.3, D=1.0, E=0.97,
        sigma=0.5, vx=20.0, dt=0.005, alpha0=0.0)
    k = ShiftIndex(Clock(dt))
    ki = ShiftIndex(SynchToolkit.InitClock())
    @variables alpha(t_nounits) [input=true]
    @variables Fy(t_nounits) [output=true]
    @variables ready(t_nounits)
    @parameters (handle::TireHandle) = TireHandle() [tunable=false]
    @named sampler = DiscreteComponents.Sampler()
    # Latest makes session initialization precede the first periodic tick.
    eqs = [ready(ki) ~ begin_session!(handle, Fz, B, C, D, E, sigma, vx, alpha0, t_nounits),
        sampler.u ~ alpha,
        Fy(k) ~ current_fy!(handle, sampler.y, t_nounits, vx, Fz,
            SynchToolkit.Latest()(ready, 0.0))]
    cleanup = SymbolicDiscreteCallback(Float64[];
        finalize=ImperativeAffect((m, o, ctx, integrator) -> (close(o.handle); (;));
            observed=(; handle)))
    System(eqs, t_nounits; name, systems=[sampler], discrete_events=[cleanup])
end
