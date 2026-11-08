# Enzyme: ChainRules rules, imported as Enzyme forward and reverse rules. F, Fx and Fy all get
# them, so forward-over-reverse Hessians work.
import ChainRulesCore as CRC

for (f, fx, fy) in PARTIALS
    @eval CRC.frule((_, dx, dy), ::typeof($f), x, y) = ($f(x, y), $fx(x, y) * dx + $fy(x, y) * dy)
    @eval CRC.rrule(::typeof($f), x, y) = ($f(x, y), dz -> (CRC.NoTangent(), dz * $fx(x, y), dz * $fy(x, y)))
    @eval Enzyme.@import_frule(typeof($f), Float64, Float64)
    @eval Enzyme.@import_rrule(typeof($f), Float64, Float64)
end
