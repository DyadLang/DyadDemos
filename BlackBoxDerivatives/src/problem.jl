# Minimum-time problem on the Dyad model: drive the car 10 m and stop, choosing the slip.
# Direct collocation (implicit midpoint) on N intervals; unknowns z = [x₀…x_N; v₀…v_N; slip₁…slip_N; T].

const N = 40

"The Dyad model's right-hand sides `(ẋ, v̇)` as expressions of `(x, v, slip)`, parameters at their defaults."
function model_rhs(force)
    @named car = TireCar()
    sys = mtkcompile(car; inputs = [ModelingToolkit.toggle_namespacing(car, false).slip])
    vars = [unknowns(sys); ModelingToolkit.inputs(sys)]
    swap(e) = iscall(e) && operation(e) === F ? force(arguments(e)...) : e
    return map(equations(sys)) do eq
        build_function(Postwalk(swap)(substitute(eq.rhs, Dict(initial_conditions(sys)))), vars...; expression = Val{true})
    end
end

# Compiled into ordinary Julia functions once, when the package loads. `reference_dynamics` swaps
# the black box for its plain formula, to check everything else against.
for (name, f) in ((:car_dynamics, F), (:reference_dynamics, tire))
    ẋ, v̇ = model_rhs(f)
    @eval $name(x, v, slip) = ($ẋ(x, v, slip), $v̇(x, v, slip))
end

split_z(z) = (z[1:(N + 1)], z[(N + 2):(2N + 2)], z[(2N + 3):(3N + 2)], z[end])

objective(z) = z[end]

"Collocation defects; zero when the trajectory obeys the dynamics."
function defects(dynamics, z)
    x, v, s, T = split_z(z)
    h = T / N
    d = [dynamics((x[k] + x[k + 1]) / 2, (v[k] + v[k + 1]) / 2, s[k]) for k in 1:N]
    return [diff(x) .- h .* first.(d); diff(v) .- h .* last.(d)]
end

"Bounds `(lb, ub)` and starting point. Start and end states are fixed through their bounds."
function bounds_and_start()
    lb = [0.0; zeros(N - 1); 10.0; zeros(N + 1); fill(-0.8, N); 0.1]
    ub = [0.0; fill(10.0, N - 1); 10.0; 0.0; fill(5.0, N - 1); 0.0; fill(0.8, N); 30.0]
    τ = range(0, 1; length = N + 1)
    z0 = [10τ; 2sin.(π * τ); [k <= N / 2 ? 0.3 : -0.3 for k in 1:N]; 8.0]
    return lb, ub, z0
end
