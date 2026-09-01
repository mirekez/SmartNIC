if(BUILD_TESTING)
    set(SMARTNIC_VERILATOR "${CPPHDL_ROOT}/.conda/bin/verilator")
    set(SMARTNIC_VERILATOR_CXX "${CPPHDL_ROOT}/.conda/bin/clang++")
    set(SMARTNIC_VERILATOR_AR "${CPPHDL_ROOT}/.conda/bin/llvm-ar")
    if(NOT EXISTS "${SMARTNIC_VERILATOR}")
        find_program(SMARTNIC_VERILATOR NAMES verilator REQUIRED)
    endif()

    add_test(NAME fpga_uart_banner
        COMMAND "${CMAKE_COMMAND}"
            "-DVERILATOR=${SMARTNIC_VERILATOR}"
            "-DVERILATOR_CXX=${SMARTNIC_VERILATOR_CXX}"
            "-DVERILATOR_AR=${SMARTNIC_VERILATOR_AR}"
            "-DSOURCE=${CMAKE_CURRENT_SOURCE_DIR}/rtl/uart_banner_tx.sv"
            "-DTESTBENCH=${CMAKE_CURRENT_SOURCE_DIR}/tests/uart_banner_test.cpp"
            "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/uart_banner_verilator"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/run_uart_banner_test.cmake")
    set_tests_properties(fpga_uart_banner PROPERTIES
        LABELS "fpga;uart;regression;verilator")

    add_test(NAME fpga_uart_probe
        COMMAND "${CMAKE_COMMAND}"
            "-DVERILATOR=${SMARTNIC_VERILATOR}"
            "-DVERILATOR_CXX=${SMARTNIC_VERILATOR_CXX}"
            "-DVERILATOR_AR=${SMARTNIC_VERILATOR_AR}"
            "-DCPPHDL=${CPPHDL_EXECUTABLE}"
            "-DCPPHDL_INCLUDE=${PROJECT_SOURCE_DIR}/cpphdl/include"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
            "-DSOURCE=${CMAKE_CURRENT_SOURCE_DIR}/UART_PROBE.h"
            "-DTESTBENCH=${CMAKE_CURRENT_SOURCE_DIR}/tests/uart_probe_test.cpp"
            "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/uart_probe_verilator"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/run_uart_probe_test.cmake")
    set_tests_properties(fpga_uart_probe PROPERTIES
        LABELS "fpga;uart;probe;cpphdl;regression;verilator")

    add_test(NAME fpga_uart_probe_autonomous
        COMMAND "${CMAKE_COMMAND}"
            "-DVERILATOR=${SMARTNIC_VERILATOR}"
            "-DVERILATOR_CXX=${SMARTNIC_VERILATOR_CXX}"
            "-DVERILATOR_AR=${SMARTNIC_VERILATOR_AR}"
            "-DCPPHDL=${CPPHDL_EXECUTABLE}"
            "-DCPPHDL_INCLUDE=${PROJECT_SOURCE_DIR}/cpphdl/include"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
            "-DSOURCE=${CMAKE_CURRENT_SOURCE_DIR}/UART_PROBE.h"
            "-DTESTBENCH=${CMAKE_CURRENT_SOURCE_DIR}/tests/uart_probe_auto_test.cpp"
            "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/uart_probe_auto_verilator"
            "-DAUTO_DUMP_CYCLES=20"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/run_uart_probe_test.cmake")
    set_tests_properties(fpga_uart_probe_autonomous PROPERTIES
        LABELS "fpga;uart;probe;cpphdl;regression;verilator")

    find_package(Python3 COMPONENTS Interpreter REQUIRED)
    add_test(NAME fpga_uart_probe_host
        COMMAND "${Python3_EXECUTABLE}"
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_uart_probe_host.py")
    set_tests_properties(fpga_uart_probe_host PROPERTIES
        LABELS "fpga;uart;probe;host;regression")

    add_test(NAME fpga_processing_stub
        COMMAND "${CMAKE_COMMAND}"
            "-DVERILATOR=${SMARTNIC_VERILATOR}"
            "-DVERILATOR_CXX=${SMARTNIC_VERILATOR_CXX}"
            "-DVERILATOR_AR=${SMARTNIC_VERILATOR_AR}"
            "-DCPPHDL=${CPPHDL_EXECUTABLE}"
            "-DCPPHDL_INCLUDE=${PROJECT_SOURCE_DIR}/cpphdl/include"
            "-DREPO_DIR=${PROJECT_SOURCE_DIR}"
            "-DSOURCE=${PROJECT_SOURCE_DIR}/rtl/processing/ProcessingStub.h"
            "-DTESTBENCH=${PROJECT_SOURCE_DIR}/rtl/processing/tests/processing_stub_test.cpp"
            "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/processing_stub_verilator"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/run_processing_stub_test.cmake")
    set_tests_properties(fpga_processing_stub PROPERTIES
        LABELS "fpga;processing;loopback;cpphdl;regression;verilator")

    # The prepared Conda Clang driver invokes its own linker, which needs the
    # matching runtime directory to resolve Verilator's -latomic dependency.
    set_tests_properties(
        fpga_uart_banner fpga_uart_probe fpga_uart_probe_autonomous
        fpga_processing_stub
        PROPERTIES ENVIRONMENT "LIBRARY_PATH=${CPPHDL_ROOT}/.conda/lib")
endif()
