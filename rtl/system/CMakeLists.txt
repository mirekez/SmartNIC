add_executable(rx_queue_test tests/rx_queue.cpp)
add_executable(tx_queue_test tests/tx_queue.cpp)
add_executable(master_dma_avalon_test tests/master_dma.cpp)
add_executable(master_dma_axi_test tests/master_dma.cpp)
add_executable(controller_avalon_test tests/controller.cpp)
add_executable(controller_axi_test tests/controller.cpp)
target_compile_definitions(master_dma_axi_test PRIVATE HOST_AXI4=1)
target_compile_definitions(controller_axi_test PRIVATE HOST_AXI4=1)

foreach(target rx_queue_test tx_queue_test master_dma_avalon_test master_dma_axi_test
    controller_avalon_test controller_axi_test)
    target_include_directories(${target} PRIVATE
        "${PROJECT_SOURCE_DIR}/cpphdl/include"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        "${PROJECT_SOURCE_DIR}/rtl/common"
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${PROJECT_SOURCE_DIR}")
    target_compile_options(${target} PRIVATE -std=c++26 -fno-strict-aliasing)
    cpphdl_add_host_opt_flags(${target})
    cpphdl_link_stdcxxexp_if_available(${target})
    cpphdl_add_converter_dependency(${target})
endforeach()

file(GLOB SMARTNIC_SYSTEM_STDCXXEXP
    "${PROJECT_SOURCE_DIR}/cpphdl/.conda/lib/gcc/*/*/libstdc++exp.a")
if(SMARTNIC_SYSTEM_STDCXXEXP)
    list(GET SMARTNIC_SYSTEM_STDCXXEXP 0 SMARTNIC_SYSTEM_STDCXXEXP_LIBRARY)
    foreach(target rx_queue_test tx_queue_test master_dma_avalon_test master_dma_axi_test
        controller_avalon_test controller_axi_test)
        target_link_libraries(${target} PRIVATE "${SMARTNIC_SYSTEM_STDCXXEXP_LIBRARY}")
    endforeach()
endif()

function(smartnic_generate_system_target target header generated_dir)
    add_custom_command(TARGET ${target} POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${generated_dir}"
        COMMAND $<TARGET_FILE:cpphdl>
            --generated-dir "${generated_dir}"
            "${CMAKE_CURRENT_SOURCE_DIR}/${header}"
            -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
            -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
            -I "${PROJECT_SOURCE_DIR}/rtl/common"
            -I "${CMAKE_CURRENT_SOURCE_DIR}"
            -I "${PROJECT_SOURCE_DIR}"
            ${CPPHDL_TOOLCHAIN_ARGS}
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        VERBATIM)
endfunction()

smartnic_generate_system_target(rx_queue_test RxQueue.h
    "${CMAKE_CURRENT_BINARY_DIR}/generated_rx_queue")
smartnic_generate_system_target(tx_queue_test TxQueue.h
    "${CMAKE_CURRENT_BINARY_DIR}/generated_tx_queue")

# Generate the complete System hierarchy in both supported host-bus forms.
# System's primary domain is the PCIe/host clock; l2_clock is the Processing
# boundary consumed by the per-queue asynchronous FIFOs.
file(STRINGS "${PROJECT_SOURCE_DIR}/Config.h" SMARTNIC_SYSTEM_ENABLE_800G_LINE
    REGEX "^#define[ \t]+ENABLE_800G[ \t]+[01]")
if(SMARTNIC_SYSTEM_ENABLE_800G_LINE MATCHES "1$")
    set(SMARTNIC_SYSTEM_L2_CLOCK_HZ 390625000)
else()
    set(SMARTNIC_SYSTEM_L2_CLOCK_HZ 195312500)
endif()
set(SMARTNIC_SYSTEM_CLOCK_HZ 250000000)

function(smartnic_add_complete_system_target target generated_dir)
    add_custom_target(${target}
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${generated_dir}"
        COMMAND $<TARGET_FILE:cpphdl>
            --generated-dir "${generated_dir}"
            --primary_clock system_clock ${SMARTNIC_SYSTEM_CLOCK_HZ}
            --secondary_clock l2_clock ${SMARTNIC_SYSTEM_L2_CLOCK_HZ}
            "${CMAKE_CURRENT_SOURCE_DIR}/System.h"
            ${ARGN}
            -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
            -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
            -I "${PROJECT_SOURCE_DIR}/rtl/common"
            -I "${CMAKE_CURRENT_SOURCE_DIR}"
            -I "${PROJECT_SOURCE_DIR}"
            ${CPPHDL_TOOLCHAIN_ARGS}
        COMMAND "${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator"
            --lint-only --Wno-fatal --Wno-WIDTH --Wno-SYMRSVDWORD
            --top-module System
            "${generated_dir}/Predef_pkg.sv"
            "${generated_dir}/SystemRingDescriptor_pkg.sv"
            "${generated_dir}/SystemRingDescriptorWord_pkg.sv"
            "${generated_dir}/MasterDmaState_pkg.sv"
            "${generated_dir}/MasterDmaDirection_pkg.sv"
            "${generated_dir}/SystemControllerFlags_pkg.sv"
            "${generated_dir}/SmartNicMemory.sv"
            "${generated_dir}/Fifo.sv"
            "${generated_dir}/PacketQueue.sv"
            "${generated_dir}/RxQueue.sv"
            "${generated_dir}/TxQueue.sv"
            "${generated_dir}/AsyncFifoL2ToSystem.sv"
            "${generated_dir}/AsyncFifoSystemToL2.sv"
            "${generated_dir}/MasterDMA.sv"
            "${generated_dir}/Controller.sv"
            "${generated_dir}/System.sv"
        DEPENDS cpphdl
            "${CMAKE_CURRENT_SOURCE_DIR}/System.h"
            "${CMAKE_CURRENT_SOURCE_DIR}/Controller.h"
            "${CMAKE_CURRENT_SOURCE_DIR}/MasterDMA.h"
            "${CMAKE_CURRENT_SOURCE_DIR}/PacketQueue.h"
            "${CMAKE_CURRENT_SOURCE_DIR}/RxQueue.h"
            "${CMAKE_CURRENT_SOURCE_DIR}/TxQueue.h"
            "${PROJECT_SOURCE_DIR}/rtl/common/AsyncFifo.h"
            "${PROJECT_SOURCE_DIR}/rtl/common/AsyncFifoImpl.inc"
            "${PROJECT_SOURCE_DIR}/rtl/common/Memory.cpp"
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        VERBATIM)
endfunction()

smartnic_add_complete_system_target(system_rtl_avalon
    "${CMAKE_CURRENT_BINARY_DIR}/generated_system_avalon")
smartnic_add_complete_system_target(system_rtl_axi
    "${CMAKE_CURRENT_BINARY_DIR}/generated_system_axi" -DHOST_AXI4=1)
add_custom_target(system_rtl DEPENDS system_rtl_avalon system_rtl_axi)

add_custom_command(TARGET master_dma_avalon_test POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${CMAKE_CURRENT_BINARY_DIR}/generated_master_dma_avalon"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${CMAKE_CURRENT_BINARY_DIR}/generated_master_dma_avalon"
        "${CMAKE_CURRENT_SOURCE_DIR}/MasterDMA.h"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        -I "${PROJECT_SOURCE_DIR}/rtl/common"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" VERBATIM)

add_custom_command(TARGET master_dma_axi_test POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${CMAKE_CURRENT_BINARY_DIR}/generated_master_dma_axi"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${CMAKE_CURRENT_BINARY_DIR}/generated_master_dma_axi"
        "${CMAKE_CURRENT_SOURCE_DIR}/MasterDMA.h"
        -DHOST_AXI4=1
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        -I "${PROJECT_SOURCE_DIR}/rtl/common"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" VERBATIM)

add_custom_command(TARGET controller_avalon_test POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${CMAKE_CURRENT_BINARY_DIR}/generated_controller_avalon"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${CMAKE_CURRENT_BINARY_DIR}/generated_controller_avalon"
        "${CMAKE_CURRENT_SOURCE_DIR}/Controller.h"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        -I "${PROJECT_SOURCE_DIR}/rtl/common"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" VERBATIM)

add_custom_command(TARGET controller_axi_test POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${CMAKE_CURRENT_BINARY_DIR}/generated_controller_axi"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${CMAKE_CURRENT_BINARY_DIR}/generated_controller_axi"
        "${CMAKE_CURRENT_SOURCE_DIR}/Controller.h"
        -DHOST_AXI4=1
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        -I "${PROJECT_SOURCE_DIR}/rtl/common"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}" VERBATIM)

if(BUILD_TESTING)
    add_test(NAME system_rx_queue COMMAND rx_queue_test)
    add_test(NAME system_tx_queue COMMAND tx_queue_test)
    add_test(NAME system_master_dma_avalon COMMAND master_dma_avalon_test)
    add_test(NAME system_master_dma_axi COMMAND master_dma_axi_test)
    add_test(NAME system_controller_avalon COMMAND controller_avalon_test)
    add_test(NAME system_controller_axi COMMAND controller_axi_test)
    foreach(test system_rx_queue system_tx_queue system_master_dma_avalon
        system_master_dma_axi system_controller_avalon system_controller_axi)
        set_tests_properties(${test} PROPERTIES
            WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
            LABELS "system;cpphdl;verilator;queue"
            TIMEOUT 900
            ENVIRONMENT
                "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}")
    endforeach()
endif()
