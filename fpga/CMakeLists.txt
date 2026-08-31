set(FPGA_TOOLCHAIN_BIN "${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin")
set(FPGA_VERILATOR "${FPGA_TOOLCHAIN_BIN}/verilator")
set(FPGA_VERILATOR_CXX "${FPGA_TOOLCHAIN_BIN}/clang++")
set(FPGA_VERILATOR_AR "${FPGA_TOOLCHAIN_BIN}/llvm-ar")
find_program(FPGA_TIMING_CXX NAMES g++ REQUIRED)
find_program(FPGA_TIMING_AR NAMES ar REQUIRED)

foreach(tool FPGA_VERILATOR FPGA_VERILATOR_CXX FPGA_VERILATOR_AR)
    if(NOT EXISTS "${${tool}}")
        message(FATAL_ERROR "Required FPGA test tool is missing: ${${tool}}")
    endif()
endforeach()

if(BUILD_TESTING)
    add_test(NAME fpga_uart_banner
        COMMAND "${CMAKE_COMMAND}"
            "-DVERILATOR=${FPGA_VERILATOR}"
            "-DVERILATOR_CXX=${FPGA_VERILATOR_CXX}"
            "-DVERILATOR_AR=${FPGA_VERILATOR_AR}"
            "-DSOURCE=${CMAKE_CURRENT_SOURCE_DIR}/rtl/uart_banner_tx.sv"
            "-DTESTBENCH=${CMAKE_CURRENT_SOURCE_DIR}/tests/uart_banner_test.cpp"
            "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/uart_banner_test"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/run_uart_banner_test.cmake")

    add_test(NAME fpga_uart_probe
        COMMAND "${CMAKE_COMMAND}"
            "-DVERILATOR=${FPGA_VERILATOR}"
            "-DVERILATOR_CXX=${FPGA_VERILATOR_CXX}"
            "-DVERILATOR_AR=${FPGA_VERILATOR_AR}"
            "-DCPPHDL=${CPPHDL_EXECUTABLE}"
            "-DCPPHDL_INCLUDE=${PROJECT_SOURCE_DIR}/cpphdl/include"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
            "-DSOURCE=${CMAKE_CURRENT_SOURCE_DIR}/UART_PROBE.h"
            "-DTESTBENCH=${CMAKE_CURRENT_SOURCE_DIR}/tests/uart_probe_test.cpp"
            "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/uart_probe_test"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/run_uart_probe_test.cmake")

    add_test(NAME fpga_uart_probe_auto
        COMMAND "${CMAKE_COMMAND}"
            "-DVERILATOR=${FPGA_VERILATOR}"
            "-DVERILATOR_CXX=${FPGA_VERILATOR_CXX}"
            "-DVERILATOR_AR=${FPGA_VERILATOR_AR}"
            "-DCPPHDL=${CPPHDL_EXECUTABLE}"
            "-DCPPHDL_INCLUDE=${PROJECT_SOURCE_DIR}/cpphdl/include"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
            "-DSOURCE=${CMAKE_CURRENT_SOURCE_DIR}/UART_PROBE.h"
            "-DTESTBENCH=${CMAKE_CURRENT_SOURCE_DIR}/tests/uart_probe_auto_test.cpp"
            "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/uart_probe_auto_test"
            -DAUTO_DUMP_CYCLES=40
            -P "${CMAKE_CURRENT_SOURCE_DIR}/run_uart_probe_test.cmake")

    add_test(NAME fpga_processing_stub
        COMMAND "${CMAKE_COMMAND}"
            "-DVERILATOR=${FPGA_VERILATOR}"
            "-DVERILATOR_CXX=${FPGA_VERILATOR_CXX}"
            "-DVERILATOR_AR=${FPGA_VERILATOR_AR}"
            "-DCPPHDL=${CPPHDL_EXECUTABLE}"
            "-DCPPHDL_INCLUDE=${PROJECT_SOURCE_DIR}/cpphdl/include"
            "-DREPO_DIR=${PROJECT_SOURCE_DIR}"
            "-DSOURCE=${PROJECT_SOURCE_DIR}/rtl/processing/ProcessingStub.h"
            "-DTESTBENCH=${PROJECT_SOURCE_DIR}/rtl/processing/tests/processing_stub_test.cpp"
            "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/processing_stub_test"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/run_processing_stub_test.cmake")

    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    add_test(NAME fpga_uart_probe_host
        COMMAND "${Python3_EXECUTABLE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_uart_probe_host.py")

    add_test(NAME fpga_gt_idle_64b66b
        COMMAND "${CMAKE_COMMAND}"
            "-DVERILATOR=${FPGA_VERILATOR}"
            "-DVERILATOR_CXX=${FPGA_TIMING_CXX}"
            "-DVERILATOR_AR=${FPGA_TIMING_AR}"
            -DVERILATOR_COMPILER=gcc
            "-DSCRAMBLER=${CMAKE_CURRENT_SOURCE_DIR}/diagnostics/scrambler_parallel.sv"
            "-DSOURCE=${CMAKE_CURRENT_SOURCE_DIR}/diagnostics/gt_idle_64b66b.sv"
            "-DTESTBENCH=${CMAKE_CURRENT_SOURCE_DIR}/tests/gt_idle_64b66b_test.sv"
            "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/gt_idle_64b66b_test"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/run_gt_idle_test.cmake")

    set_tests_properties(
        fpga_uart_banner fpga_uart_probe fpga_uart_probe_auto fpga_processing_stub
        PROPERTIES
            LABELS "fpga;verilator"
            TIMEOUT 300
            ENVIRONMENT "LIBRARY_PATH=${FPGA_TOOLCHAIN_BIN}/../lib")
    set_tests_properties(fpga_gt_idle_64b66b PROPERTIES
        LABELS "fpga;verilator" TIMEOUT 300)
    set_tests_properties(fpga_uart_probe_host PROPERTIES
        LABELS "fpga;python;uart" TIMEOUT 30)
endif()
