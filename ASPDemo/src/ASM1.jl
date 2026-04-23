@kwdef struct ASM1 <: AbstractMedium
    mediumName::String = "ASM1"
    nS::Int = 13
    # Reference temperature [degC]
    T_ref_C::Float64 = 15
    # Maximum heterotrophic growth rate at T=15 deg C [day^-1]
    mu_h_T::Float64 = 4.0
    # Heterotrophic decay rate at T=15 deg C [day^-1]
    b_h_T::Float64 = 0.28 
    # Maximum autotrophic growth rate at T=15 deg C[day^-1]"
    mu_a_T::Float64 = 0.5
    # Autotrophic decay rate at T=15 deg C [day^-1]
    b_a_T::Float64 = 0.1 
    # Ammonification rate at T=15 deg C [m3/(g COD day)]
    k_a_T::Float64 = 0.06
    # Maximum specific hydrolysis rate at T=15 deg C [g Xs/(g Xbh COD day)]
    k_h_T::Float64 = 1.75
    # Half-saturation (hydrolysis) at T=15 deg C [g Xs/(g Xbh COD)]
    K_x_T::Float64 = 0.0175
    # Half-saturation (auto. growth) [g NH-N/m3]
    K_nh::Float64 = 1.0 
    # Half-saturation (hetero. growth) [g COD/m3]
    K_s::Float64 = 20.0 
    # Half-saturation (hetero. oxygen) [g O/m3]
    K_oh::Float64 = 0.2 
    # Half-saturation (nitrate) [g NO-N/m3]
    K_no::Float64 = 0.5 
    # Half-saturation (auto. oxygen) [g O/m3]
    K_oa::Float64 = 0.4 
    # Anoxic growth rate correction factor [-]
    ny_g::Float64 = 0.8
    # Anoxic hydrolysis rate correction factor [-]
    ny_h::Float64 = 0.4
    # Heterotrophic Yield [g Xbh COD formed/(g COD utilised)]
    Y_h::Float64 = 0.67
    # Autotrophic Yield [g Xba COD formed/(g N utilised)]
    Y_a::Float64 = 0.24
    # Fraction of biomass to particulate products [-]
    f_p::Float64 = 0.08 
    # Fraction nitrogen in biomass [g N/(g COD)]
    i_xb::Float64 = 0.086 
    # Fraction nitrogen in particulate products [g N/(g COD)]
    i_xp::Float64 = 0.06

end

function _reactions(medium::ASM1, T, states)
    r = similar(states)

    # Temperature dependent Kinetic parameters based on 15 deg C
    mu_h = KineticExp(T, medium.mu_h_T, 0.069, medium.T_ref_C)
    b_h = KineticExp(T, medium.b_h_T, 0.069, medium.T_ref_C)
    mu_a = KineticExp(T, medium.mu_a_T, 0.098, medium.T_ref_C)
    b_a = KineticExp(T, medium.b_a_T, 0.08, medium.T_ref_C)
    k_a = KineticExp(T, medium.k_a_T, 0.069, medium.T_ref_C)
    k_h = KineticExp(T, medium.k_h_T, 0.11, medium.T_ref_C)
    K_x = KineticExp(T, medium.K_x_T, 0.11, medium.T_ref_C)

    # Extract states
    Ss = states[2]
    Xs = states[4]
    Xbh = states[5]
    Xba = states[6]
    So = states[8]
    Sno = states[9]
    Snh = states[10]
    Snd = states[11]
    Xnd = states[12]

    # Process rates
    p1 = mu_h*(Ss/(medium.K_s + Ss))*(So/(medium.K_oh + So))*Xbh
    p2 = mu_h*(Ss/(medium.K_s + Ss))*(medium.K_oh/(medium.K_oh + So))*(Sno/(medium.K_no + Sno))*medium.ny_g*Xbh
    p3 = mu_a*(Snh/(medium.K_nh + Snh))*(So/(medium.K_oa + So))*Xba
    p4 = b_h*Xbh
    p5 = b_a*Xba
    p6 = k_a*Snd*Xbh
    p7 = k_h*((Xs/Xbh)/(K_x + (Xs/Xbh)))*((So/(medium.K_oh + So)) + medium.ny_h*(medium.K_oh/(medium.K_oh
     + So))*(Sno/(medium.K_no + Sno)))*Xbh
    p8 = p7*Xnd/Xs

    # Biochemical reactions
    r[1] = 0
    r[2] = (-p1 - p2)/medium.Y_h + p7
    r[3] = 0
    r[4] = (1 - medium.f_p)*(p4 + p5) - p7
    r[5] = p1 + p2 - p4
    r[6] = p3 - p5
    r[7] = medium.f_p*(p4 + p5)
    r[8] = -((1 - medium.Y_h)/medium.Y_h)*p1 - ((4.57 - medium.Y_a)/medium.Y_a)*p3
    r[9] = -((1 - medium.Y_h)/(2.86*medium.Y_h))*p2 + p3/medium.Y_a
    r[10] = -medium.i_xb*(p1 + p2) - (medium.i_xb + (1/medium.Y_a))*p3 + p6
    r[11] = -p6 + p8
    r[12] = (medium.i_xb - medium.f_p*medium.i_xp)*(p4 + p5) - p8
    r[13] = -medium.i_xb/14*p1 + ((1 - medium.Y_h)/(14*2.86*medium.Y_h) - (medium.i_xb/14))*p2 - ((medium.i_xb/14)
     + 1/(7*medium.Y_a))*p3 + p6/14

    return r
end

reactions(medium::AbstractMedium, T, states) = _reactions(medium, T, states)
@register_array_symbolic reactions(medium::AbstractMedium, T, states::AbstractVector) begin
    size = size(states)
    eltype = eltype(states)
end