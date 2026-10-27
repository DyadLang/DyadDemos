export libtiremodel
JLLWrappers.@generate_wrapper_header("TireModel")
JLLWrappers.@declare_library_product(libtiremodel, "libtiremodel.so")
function __init__()
    # Also rebuild when a user removes build products but keeps Julia's cache.
    build_tiremodel()
    JLLWrappers.@generate_init_header()
    JLLWrappers.@init_library_product(libtiremodel, "lib/libtiremodel.so", RTLD_LAZY | RTLD_DEEPBIND)
    JLLWrappers.@generate_init_footer()
end
