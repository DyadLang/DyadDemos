export libtiremodel
JLLWrappers.@generate_wrapper_header("TireModel")
JLLWrappers.@declare_library_product(libtiremodel, "libtiremodel.$(Libdl.dlext)")
function __init__()
    JLLWrappers.@generate_init_header()
    JLLWrappers.@init_library_product(libtiremodel, "lib/libtiremodel.$(Libdl.dlext)", RTLD_LAZY | RTLD_DEEPBIND)
    JLLWrappers.@generate_init_footer()
end
