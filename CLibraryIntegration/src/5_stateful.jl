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
@register_symbolic get_fy(h::TireHandle)::Real

function initialize_tire!(m, o, ctx, integrator)
    h = o.handle
    close(h)
    p = Ref(TireParams(MFParams(o.B, o.C, o.D, o.E), o.sigma, o.Fz))
    h.ptr = @ccall libtiremodel.tm_tire_new(p::Ref{TireParams})::Ptr{Cvoid}
    h.ptr == C_NULL && error("could not create tire")
    check_status(@ccall libtiremodel.tm_tire_reset(h::Ptr{Cvoid}, o.t::Cdouble, o.alpha0::Cdouble)::Cint)
    h.time, h.alpha, h.vx, h.Fz = o.t, o.alpha, o.vx, o.Fz
    SynchToolkit.get_clock_invoker(integrator.f.sys, integrator, ctx)()
    (;)
end
function step_tire!(m, o, ctx, integrator)
    h = o.handle
    dt = o.t - h.time
    # Complete the previous interval with its LEFT-endpoint inputs. Sampling
    # current inputs before advancing would silently change the coupling scheme.
    check_status(@ccall libtiremodel.tm_tire_step(h::Ptr{Cvoid}, h.time::Cdouble,
        dt::Cdouble, h.alpha::Cdouble, h.vx::Cdouble, h.Fz::Cdouble)::Cint)
    h.time, h.alpha, h.vx, h.Fz = o.t, o.alpha, o.vx, o.Fz
    SynchToolkit.get_clock_invoker(integrator.f.sys, integrator, ctx)()
    (;)
end
function finalize_tire!(m, o, ctx, integrator)
    close(o.handle)
    (;)
end

function RelaxationTire(; name, Fz=4000.0, B=10.0, C=1.3, D=1.0, E=0.97,
        sigma=0.5, vx=20.0, dt=0.005, alpha0=0.0)
    clock = SynchToolkit.ImperativeClock()
    k = ShiftIndex(clock)
    @variables alpha(t_nounits) [input=true]
    @variables Fy(t_nounits) [output=true]
    @parameters (handle::TireHandle) = TireHandle() [tunable=false]
    observed = (; handle, alpha, t=t_nounits, Fz, B, C, D, E, sigma, vx, alpha0)
    cb = SymbolicDiscreteCallback(dt,
        ImperativeAffect(step_tire!; observed, ctx=clock);
        initialize=ImperativeAffect(initialize_tire!; observed, ctx=clock),
        finalize=ImperativeAffect(finalize_tire!; observed=(; handle)),
        reinitializealg=ModelingToolkit.SciMLBase.NoInit())
    # Publish after C updates, so a downstream hold sees this tick's force.
    System([Fy(k) ~ get_fy(handle)], t_nounits, [alpha, Fy(k)], [handle]; name,
        discrete_events=[cb])
end
