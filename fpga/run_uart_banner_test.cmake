if(NOT DEFINED VERILATOR OR NOT EXISTS "${VERILATOR}")
    message(FATAL_ERROR "Verilator executable is missing: ${VERILATOR}")
endif()
if(NOT DEFINED VERILATOR_CXX OR NOT EXISTS "${VERILATOR_CXX}")
    message(FATAL_ERROR "Verilator C++ compiler is missing: ${VERILATOR_CXX}")
endif()
foreach(required SOURCE TESTBENCH OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "Missing required argument ${required}")
    endif()
endforeach()

file(REMOVE_RECURSE "${OUTPUT_DIR}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "CXX=${VERILATOR_CXX}"
        "${VERILATOR}" --cc --exe --build --Wno-fatal --compiler clang
        -MAKEFLAGS
            "CXX=${VERILATOR_CXX} LINK=${VERILATOR_CXX} AR=${VERILATOR_AR}"
        --top-module uart_banner_tx
        -GCLOCK_HZ=1152000 -GBAUD=115200 -GREPEAT_GAP_BITS=3
        --Mdir "${OUTPUT_DIR}"
        "${SOURCE}" "${TESTBENCH}"
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_output
    ERROR_VARIABLE compile_error)
if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR
        "UART banner Verilator build failed:\n${compile_output}\n${compile_error}")
endif()

execute_process(
    COMMAND "${OUTPUT_DIR}/Vuart_banner_tx"
    RESULT_VARIABLE test_result
    OUTPUT_VARIABLE test_output
    ERROR_VARIABLE test_error)
message("${test_output}")
if(NOT test_result EQUAL 0)
    message(FATAL_ERROR
        "UART banner simulation failed:\n${test_output}\n${test_error}")
endif()
