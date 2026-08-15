add_executable(descriptor_fetcher_test tests/decoder_fetcher.cpp)
add_executable(packet_dma_test tests/packet_dma.cpp)
add_executable(cpu_test tests/cpu.cpp)

set(SMARTNIC_L2_CLOCK_HZ 156250000)
set(SMARTNIC_CPU_CLOCK_HZ 312500000)

target_include_directories(descriptor_fetcher_test PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${PROJECT_SOURCE_DIR}/rtl/network"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}"
)
target_include_directories(packet_dma_test PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}"
)
target_include_directories(cpu_test PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}"
)

include(CheckCXXCompilerFlag)
foreach(flag -std=c++26 -std=c++2c -std=c++23)
    check_cxx_compiler_flag("${flag}" SMARTNIC_PROCESSING_HAS_${flag})
    if(SMARTNIC_PROCESSING_HAS_${flag})
        target_compile_options(descriptor_fetcher_test PRIVATE "${flag}")
        target_compile_options(packet_dma_test PRIVATE "${flag}")
        target_compile_options(cpu_test PRIVATE "${flag}")
        break()
    endif()
endforeach()
target_compile_options(descriptor_fetcher_test PRIVATE -fno-strict-aliasing)
target_compile_options(packet_dma_test PRIVATE -fno-strict-aliasing)
target_compile_options(cpu_test PRIVATE -fno-strict-aliasing)
cpphdl_add_host_opt_flags(descriptor_fetcher_test)
cpphdl_add_host_opt_flags(packet_dma_test)
cpphdl_add_host_opt_flags(cpu_test)
cpphdl_link_stdcxxexp_if_available(descriptor_fetcher_test)
cpphdl_link_stdcxxexp_if_available(packet_dma_test)
cpphdl_link_stdcxxexp_if_available(cpu_test)
cpphdl_add_converter_dependency(descriptor_fetcher_test)
cpphdl_add_converter_dependency(packet_dma_test)
cpphdl_add_converter_dependency(cpu_test)
file(GLOB SMARTNIC_PROCESSING_STDCXXEXP
    "${PROJECT_SOURCE_DIR}/cpphdl/.conda/lib/gcc/*/*/libstdc++exp.a")
if(SMARTNIC_PROCESSING_STDCXXEXP)
    list(GET SMARTNIC_PROCESSING_STDCXXEXP 0 SMARTNIC_PROCESSING_STDCXXEXP_LIBRARY)
    target_link_libraries(descriptor_fetcher_test PRIVATE
        "${SMARTNIC_PROCESSING_STDCXXEXP_LIBRARY}")
    target_link_libraries(packet_dma_test PRIVATE
        "${SMARTNIC_PROCESSING_STDCXXEXP_LIBRARY}")
    target_link_libraries(cpu_test PRIVATE
        "${SMARTNIC_PROCESSING_STDCXXEXP_LIBRARY}")
endif()

set(DESCRIPTOR_FETCHER_GENERATED_DIR
    "${CMAKE_CURRENT_BINARY_DIR}/generated_descriptor_fetcher")
add_custom_command(
    TARGET descriptor_fetcher_test
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${DESCRIPTOR_FETCHER_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${DESCRIPTOR_FETCHER_GENERATED_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}/DescriptorFetcher.h"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        -I "${PROJECT_SOURCE_DIR}/rtl/network"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

set(PACKET_DMA_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated_packet_dma")
add_custom_command(
    TARGET packet_dma_test
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${PACKET_DMA_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${PACKET_DMA_GENERATED_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}/PacketDMA.h"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

set(CPU_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated_cpu")
add_custom_command(
    TARGET cpu_test
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${CPU_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${CPU_GENERATED_DIR}"
        --primary_clock clk ${SMARTNIC_CPU_CLOCK_HZ}
        --secondary_clock l2_clock ${SMARTNIC_L2_CLOCK_HZ}
        "${CMAKE_CURRENT_SOURCE_DIR}/CPU.h"
        -DMULTICORE
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

set(PROCESSING_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated_processing")
add_custom_target(processing_rtl
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${PROCESSING_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${PROCESSING_GENERATED_DIR}"
        --primary_clock clk ${SMARTNIC_CPU_CLOCK_HZ}
        --secondary_clock l2_clock ${SMARTNIC_L2_CLOCK_HZ}
        "${CMAKE_CURRENT_SOURCE_DIR}/Processing.h"
        -DMULTICORE
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    DEPENDS "${CPPHDL_CONVERTER_DEPENDENCY}"
        "${CMAKE_CURRENT_SOURCE_DIR}/Processing.h"
        "${CMAKE_CURRENT_SOURCE_DIR}/CPU.h"
        "${CMAKE_CURRENT_SOURCE_DIR}/DescriptorFetcher.h"
        "${CMAKE_CURRENT_SOURCE_DIR}/PacketDMA.h"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

if(BUILD_TESTING)
    add_test(NAME processing_descriptor_fetcher COMMAND descriptor_fetcher_test)
    add_test(NAME processing_packet_dma COMMAND packet_dma_test)
    add_test(NAME processing_cpu COMMAND cpu_test)
    set_tests_properties(processing_descriptor_fetcher PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "processing;cpphdl;verilator"
        TIMEOUT 900
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
    set_tests_properties(processing_packet_dma PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "processing;cpphdl;verilator;dma"
        TIMEOUT 900
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
    set_tests_properties(processing_cpu PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "processing;cpphdl;verilator;cpu"
        TIMEOUT 1800
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
endif()
