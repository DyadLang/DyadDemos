# SparseConnectivityTracer: say that F depends on both arguments, to first and second order,
# so automatic sparsity detection can trace through it. Only F is ever traced.
import SparseConnectivityTracer as SCT

for is_zero in (:is_der1_arg1_zero_global, :is_der2_arg1_zero_global, :is_der1_arg2_zero_global,
                :is_der2_arg2_zero_global, :is_der_cross_zero_global)
    @eval SCT.$is_zero(::typeof(F)) = false
end
eval(SCT.generate_code_2_to_1(:BlackBoxDerivatives, F))
