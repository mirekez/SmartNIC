add_executable(input_balancer_tests tests/input_balancer.cpp)

target_include_directories(input_balancer_tests PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)

include(CheckCXXCompilerFlag)
foreach(flag -std=c++26 -std=c++2c -std=c++23)
    check_cxx_compiler_flag("${flag}" SMARTNIC_HAS_${flag})
    if(SMARTNIC_HAS_${flag})
        target_compile_options(input_balancer_tests PRIVATE "${flag}")
        break()
    endif()
endforeach()

target_compile_options(input_balancer_tests PRIVATE -fno-strict-aliasing)
cpphdl_add_host_opt_flags(input_balancer_tests)
cpphdl_link_stdcxxexp_if_available(input_balancer_tests)
cpphdl_add_converter_dependency(input_balancer_tests)

# The exported conda GCC runtime keeps the C++23 stacktrace support library in
# its versioned GCC directory, outside CMake's default find_library paths.
file(GLOB SMARTNIC_STDCXXEXP
    "${PROJECT_SOURCE_DIR}/cpphdl/.conda/lib/gcc/*/*/libstdc++exp.a")
if(SMARTNIC_STDCXXEXP)
    list(GET SMARTNIC_STDCXXEXP 0 SMARTNIC_STDCXXEXP_LIBRARY)
    target_link_libraries(input_balancer_tests PRIVATE "${SMARTNIC_STDCXXEXP_LIBRARY}")
endif()

set(INPUT_BALANCER_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
add_custom_command(
    TARGET input_balancer_tests
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${INPUT_BALANCER_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${INPUT_BALANCER_GENERATED_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/input_balancer.cpp"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

if(BUILD_TESTING)
    add_test(NAME network_input_balancer COMMAND input_balancer_tests)
    set_tests_properties(network_input_balancer PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "network;cpphdl;verilator"
        TIMEOUT 900
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
endif()
