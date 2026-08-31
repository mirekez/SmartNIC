foreach(required VERILATOR VERILATOR_CXX VERILATOR_AR CPPHDL SOURCE TESTBENCH
        OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "Missing required argument ${required}")
    endif()
endforeach()

file(REMOVE_RECURSE "${OUTPUT_DIR}")
file(MAKE_DIRECTORY "${OUTPUT_DIR}/generated")
set(probe_parameters
    -GCLOCK_HZ=1000 -GBAUD=100 -GSAMPLE_DIV=4 -GDEPTH=4)
if(DEFINED AUTO_DUMP_CYCLES)
    list(APPEND probe_parameters "-GAUTO_DUMP_CYCLES=${AUTO_DUMP_CYCLES}")
endif()

execute_process(
    COMMAND "${CPPHDL}" --generated-dir "${OUTPUT_DIR}/generated"
        "${SOURCE}" -I "${CPPHDL_INCLUDE}" -I "${SOURCE_DIR}"
    RESULT_VARIABLE convert_result
    OUTPUT_VARIABLE convert_output
    ERROR_VARIABLE convert_error)
if(NOT convert_result EQUAL 0)
    message(FATAL_ERROR
        "UART probe CppHDL conversion failed:\n${convert_output}\n${convert_error}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "CXX=${VERILATOR_CXX}"
        "${VERILATOR}" --cc --exe --build --Wno-fatal --compiler clang
        -Wno-BLKSEQ -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
        -MAKEFLAGS
            "CXX=${VERILATOR_CXX} LINK=${VERILATOR_CXX} AR=${VERILATOR_AR}"
        --top-module UARTProbe
        ${probe_parameters}
        --Mdir "${OUTPUT_DIR}/obj"
        "${OUTPUT_DIR}/generated/Predef_pkg.sv"
        "${OUTPUT_DIR}/generated/UARTProbeMemory.sv"
        "${OUTPUT_DIR}/generated/UARTProbe.sv" "${TESTBENCH}"
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_output
    ERROR_VARIABLE compile_error)
if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR
        "UART probe Verilator build failed:\n${compile_output}\n${compile_error}")
endif()

execute_process(
    COMMAND "${OUTPUT_DIR}/obj/VUARTProbe"
    RESULT_VARIABLE test_result
    OUTPUT_VARIABLE test_output
    ERROR_VARIABLE test_error)
message("${test_output}")
if(NOT test_result EQUAL 0)
    message(FATAL_ERROR
        "UART probe simulation failed:\n${test_output}\n${test_error}")
endif()
