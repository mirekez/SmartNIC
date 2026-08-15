add_executable(input_balancer_tests tests/input_balancer.cpp)
add_executable(packet_parser_tests tests/packet_parser.cpp)
add_executable(rx_ram_tests tests/rx_ram.cpp)
add_executable(output_merger_tests tests/ouput_merger.cpp)
add_executable(network_basic_tests tests/network_basic.cpp)
add_executable(smartnic_test ../tests/smartnic_test.cpp)

set(SMARTNIC_PRIMARY_CLOCK net_clk 156250000)
set(SMARTNIC_SECONDARY_CLOCK l2_clk 156250000)

target_include_directories(input_balancer_tests PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_include_directories(packet_parser_tests PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}"
)

target_include_directories(rx_ram_tests PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/rtl/common"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}"
)

target_include_directories(network_basic_tests PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/rtl/common"
    "${PROJECT_SOURCE_DIR}/rtl/testing"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}"
)

target_include_directories(smartnic_test PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/eth_pcs/rtl"
    "${PROJECT_SOURCE_DIR}/rtl/common"
    "${PROJECT_SOURCE_DIR}/rtl/network"
    "${PROJECT_SOURCE_DIR}/rtl"
    "${PROJECT_SOURCE_DIR}"
)

target_include_directories(output_merger_tests PRIVATE
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/rtl/common"
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}"
)

include(CheckCXXCompilerFlag)
foreach(flag -std=c++26 -std=c++2c -std=c++23)
    check_cxx_compiler_flag("${flag}" SMARTNIC_HAS_${flag})
    if(SMARTNIC_HAS_${flag})
        target_compile_options(input_balancer_tests PRIVATE "${flag}")
        break()
    endif()
endforeach()

foreach(flag -std=c++26 -std=c++2c -std=c++23)
    if(SMARTNIC_HAS_${flag})
        target_compile_options(output_merger_tests PRIVATE "${flag}")
        break()
    endif()
endforeach()

foreach(flag -std=c++26 -std=c++2c -std=c++23)
    if(SMARTNIC_HAS_${flag})
        target_compile_options(network_basic_tests PRIVATE "${flag}")
        target_compile_options(smartnic_test PRIVATE "${flag}")
        break()
    endif()
endforeach()

foreach(flag -std=c++26 -std=c++2c -std=c++23)
    if(SMARTNIC_HAS_${flag})
        target_compile_options(rx_ram_tests PRIVATE "${flag}")
        break()
    endif()
endforeach()

foreach(flag -std=c++26 -std=c++2c -std=c++23)
    if(SMARTNIC_HAS_${flag})
        target_compile_options(packet_parser_tests PRIVATE "${flag}")
        break()
    endif()
endforeach()

target_compile_options(input_balancer_tests PRIVATE -fno-strict-aliasing)
target_compile_options(packet_parser_tests PRIVATE -fno-strict-aliasing)
target_compile_options(rx_ram_tests PRIVATE -fno-strict-aliasing)
target_compile_options(output_merger_tests PRIVATE -fno-strict-aliasing)
target_compile_options(network_basic_tests PRIVATE -fno-strict-aliasing)
target_compile_options(smartnic_test PRIVATE -fno-strict-aliasing)
cpphdl_add_host_opt_flags(input_balancer_tests)
cpphdl_add_host_opt_flags(packet_parser_tests)
cpphdl_add_host_opt_flags(rx_ram_tests)
cpphdl_add_host_opt_flags(output_merger_tests)
cpphdl_add_host_opt_flags(network_basic_tests)
cpphdl_add_host_opt_flags(smartnic_test)
cpphdl_link_stdcxxexp_if_available(input_balancer_tests)
cpphdl_link_stdcxxexp_if_available(packet_parser_tests)
cpphdl_link_stdcxxexp_if_available(rx_ram_tests)
cpphdl_link_stdcxxexp_if_available(output_merger_tests)
cpphdl_link_stdcxxexp_if_available(network_basic_tests)
cpphdl_link_stdcxxexp_if_available(smartnic_test)
cpphdl_add_converter_dependency(input_balancer_tests)
cpphdl_add_converter_dependency(packet_parser_tests)
cpphdl_add_converter_dependency(rx_ram_tests)
cpphdl_add_converter_dependency(output_merger_tests)
cpphdl_add_converter_dependency(network_basic_tests)
cpphdl_add_converter_dependency(smartnic_test)

# The exported conda GCC runtime keeps the C++23 stacktrace support library in
# its versioned GCC directory, outside CMake's default find_library paths.
file(GLOB SMARTNIC_STDCXXEXP
    "${PROJECT_SOURCE_DIR}/cpphdl/.conda/lib/gcc/*/*/libstdc++exp.a")
if(SMARTNIC_STDCXXEXP)
    list(GET SMARTNIC_STDCXXEXP 0 SMARTNIC_STDCXXEXP_LIBRARY)
    target_link_libraries(input_balancer_tests PRIVATE "${SMARTNIC_STDCXXEXP_LIBRARY}")
    target_link_libraries(packet_parser_tests PRIVATE "${SMARTNIC_STDCXXEXP_LIBRARY}")
    target_link_libraries(rx_ram_tests PRIVATE "${SMARTNIC_STDCXXEXP_LIBRARY}")
    target_link_libraries(output_merger_tests PRIVATE "${SMARTNIC_STDCXXEXP_LIBRARY}")
    target_link_libraries(network_basic_tests PRIVATE "${SMARTNIC_STDCXXEXP_LIBRARY}")
    target_link_libraries(smartnic_test PRIVATE "${SMARTNIC_STDCXXEXP_LIBRARY}")
endif()

set(SMARTNIC_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated_smartnic")
add_custom_command(
    TARGET smartnic_test
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${SMARTNIC_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --primary_clock ${SMARTNIC_PRIMARY_CLOCK}
        --secondary_clock ${SMARTNIC_SECONDARY_CLOCK}
        --generated-dir "${SMARTNIC_GENERATED_DIR}"
        "${PROJECT_SOURCE_DIR}/rtl/SmartNIC.h"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/rtl/common"
        -I "${PROJECT_SOURCE_DIR}/rtl/network"
        -I "${PROJECT_SOURCE_DIR}/rtl"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    COMMAND "${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator"
        --lint-only -Wno-fatal --top-module SmartNIC
        -I"${SMARTNIC_GENERATED_DIR}"
        "${SMARTNIC_GENERATED_DIR}/Predef_pkg.sv"
        "${SMARTNIC_GENERATED_DIR}/PacketParserFields_pkg.sv"
        "${SMARTNIC_GENERATED_DIR}/PacketParserWord_pkg.sv"
        "${SMARTNIC_GENERATED_DIR}/PacketParserCursor_pkg.sv"
        "${SMARTNIC_GENERATED_DIR}/PacketParserFlags_pkg.sv"
        "${SMARTNIC_GENERATED_DIR}/RxRAMWritePair_pkg.sv"
        "${SMARTNIC_GENERATED_DIR}/RxDescriptor_pkg.sv"
        "${SMARTNIC_GENERATED_DIR}/RxDescriptorWord_pkg.sv"
        "${SMARTNIC_GENERATED_DIR}/RxDescriptorFlags_pkg.sv"
        "${SMARTNIC_GENERATED_DIR}/SmartNicMemory.sv"
        "${SMARTNIC_GENERATED_DIR}/Fifo.sv"
        "${SMARTNIC_GENERATED_DIR}/SmartNicRAM.sv"
        "${SMARTNIC_GENERATED_DIR}/InputBalancer.sv"
        "${SMARTNIC_GENERATED_DIR}/PacketParser.sv"
        "${SMARTNIC_GENERATED_DIR}/RxRAM.sv"
        "${SMARTNIC_GENERATED_DIR}/RxFifo.sv"
        "${SMARTNIC_GENERATED_DIR}/TxFifo.sv"
        "${SMARTNIC_GENERATED_DIR}/OutputMerger.sv"
        "${SMARTNIC_GENERATED_DIR}/Network.sv"
        "${SMARTNIC_GENERATED_DIR}/PacketStream.sv"
        "${SMARTNIC_GENERATED_DIR}/SmartNIC.sv"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

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

set(NETWORK_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated_network")
add_custom_command(
    TARGET network_basic_tests
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${NETWORK_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${NETWORK_GENERATED_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/network_basic.cpp"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/rtl/common"
        -I "${PROJECT_SOURCE_DIR}/rtl/testing"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

set(OUTPUT_MERGER_GENERATED_DIR
    "${CMAKE_CURRENT_BINARY_DIR}/generated_output_merger")
add_custom_command(
    TARGET output_merger_tests
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${OUTPUT_MERGER_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${OUTPUT_MERGER_GENERATED_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/ouput_merger.cpp"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/rtl/common"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

set(RX_RAM_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated_rx_ram")
add_custom_command(
    TARGET rx_ram_tests
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${RX_RAM_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${RX_RAM_GENERATED_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/rx_ram.cpp"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${PROJECT_SOURCE_DIR}/rtl/common"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

set(PACKET_PARSER_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated_parser")
add_custom_command(
    TARGET packet_parser_tests
    POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${PACKET_PARSER_GENERATED_DIR}"
    COMMAND $<TARGET_FILE:cpphdl>
        --generated-dir "${PACKET_PARSER_GENERATED_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/packet_parser.cpp"
        -I "${PROJECT_SOURCE_DIR}/cpphdl/include"
        -I "${CMAKE_CURRENT_SOURCE_DIR}"
        -I "${PROJECT_SOURCE_DIR}"
        ${CPPHDL_TOOLCHAIN_ARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    VERBATIM
)

if(BUILD_TESTING)
    add_test(NAME network_input_balancer COMMAND input_balancer_tests)
    add_test(NAME network_packet_parser COMMAND packet_parser_tests)
    add_test(NAME network_rx_ram COMMAND rx_ram_tests)
    add_test(NAME network_output_merger COMMAND output_merger_tests)
    add_test(NAME network_basic COMMAND network_basic_tests)
    add_test(NAME smartnic_integration COMMAND smartnic_test)
    # Elaborate the exact checked-in FPGA Network composition.  The normal
    # tests convert fresh RTL into the build tree, so this also catches stale
    # generated interfaces among PacketParser, RxFifo, Fifo, and Network.
    add_test(NAME network_fpga_rtl_lint
        COMMAND "${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator"
            --lint-only
            -Wno-fatal
            -Wno-TIMESCALEMOD
            -Wno-WIDTHEXPAND
            -Wno-WIDTHTRUNC
            --top-module Network
            -I${PROJECT_SOURCE_DIR}/rtl/generated
            "${PROJECT_SOURCE_DIR}/rtl/generated/Predef_pkg.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/PacketParserFields_pkg.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/PacketParserWord_pkg.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/PacketParserCursor_pkg.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/PacketParserFlags_pkg.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/RxRAMWritePair_pkg.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/RxDescriptor_pkg.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/RxDescriptorWord_pkg.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/RxDescriptorFlags_pkg.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/SmartNicMemory.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/Fifo.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/SmartNicRAM.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/InputBalancer.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/PacketParser.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/RxRAM.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/RxFifo.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/TxFifo.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/OutputMerger.sv"
            "${PROJECT_SOURCE_DIR}/rtl/generated/Network.sv"
    )
    set_tests_properties(network_input_balancer PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "network;cpphdl;verilator"
        TIMEOUT 900
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
    set_tests_properties(network_packet_parser PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "network;cpphdl;verilator"
        TIMEOUT 900
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
    set_tests_properties(network_rx_ram PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "network;cpphdl;verilator"
        TIMEOUT 900
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
    set_tests_properties(network_output_merger PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "network;cpphdl;verilator"
        TIMEOUT 1200
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
    set_tests_properties(network_basic PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "network;cpphdl;verilator;integration"
        TIMEOUT 1200
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
    set_tests_properties(smartnic_integration PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "smartnic;network;cpphdl;sync;verilator;integration"
        TIMEOUT 1200
        ENVIRONMENT
            "CONDA_PREFIX=${PROJECT_SOURCE_DIR}/cpphdl/.conda;CPPHDL_VERILATOR=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/verilator;CPPHDL_VERILATOR_CXX=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin/clang++;CPPHDL_VERILATOR_CFLAGS=-O0;PATH=${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin:$ENV{PATH}"
    )
    set_tests_properties(network_fpga_rtl_lint PROPERTIES
        WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
        LABELS "network;fpga;verilator;regression"
        TIMEOUT 120
    )
endif()
