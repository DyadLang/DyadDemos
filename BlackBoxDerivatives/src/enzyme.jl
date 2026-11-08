# Enzyme: ChainRules rules, imported as Enzyme forward and reverse rules. F, Fx and Fy all get
# them, so forward-over-reverse Hessians work.
import ChainRulesCore as CRC

CRC.frule((_, dx, dy), ::typeof(F), x, y) = (F(x, y), Fx(x, y) * dx + Fy(x, y) * dy)
CRC.frule((_, dx, dy), ::typeof(Fx), x, y) = (Fx(x, y), Fxx(x, y) * dx + Fxy(x, y) * dy)
CRC.frule((_, dx, dy), ::typeof(Fy), x, y) = (Fy(x, y), Fxy(x, y) * dx + Fyy(x, y) * dy)
CRC.rrule(::typeof(F), x, y) = (F(x, y), dz -> (CRC.NoTangent(), dz * Fx(x, y), dz * Fy(x, y)))
CRC.rrule(::typeof(Fx), x, y) = (Fx(x, y), dz -> (CRC.NoTangent(), dz * Fxx(x, y), dz * Fxy(x, y)))
CRC.rrule(::typeof(Fy), x, y) = (Fy(x, y), dz -> (CRC.NoTangent(), dz * Fxy(x, y), dz * Fyy(x, y)))
for f in (F, Fx, Fy)
    @eval Enzyme.@import_frule(typeof($f), Float64, Float64)
    @eval Enzyme.@import_rrule(typeof($f), Float64, Float64)
end
