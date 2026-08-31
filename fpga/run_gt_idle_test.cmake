foreach(required VERILATOR VERILATOR_CXX VERILATOR_AR VERILATOR_COMPILER
        SCRAMBLER SOURCE TESTBENCH OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "Missing required argument ${required}")
    endif()
endforeach()

file(REMOVE_RECURSE "${OUTPUT_DIR}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "CXX=${VERILATOR_CXX}"
        "${VERILATOR}" --binary --build --timing --Wno-fatal
        --compiler "${VERILATOR_COMPILER}"
        -MAKEFLAGS
            "CXX=${VERILATOR_CXX} LINK=${VERILATOR_CXX} AR=${VERILATOR_AR}"
        --top-module gt_idle_64b66b_test
        --Mdir "${OUTPUT_DIR}"
        "${SCRAMBLER}" "${SOURCE}" "${TESTBENCH}"
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_output
    ERROR_VARIABLE compile_error)
if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR
        "GT idle Verilator build failed:\n${compile_output}\n${compile_error}")
endif()

execute_process(
    COMMAND "${OUTPUT_DIR}/Vgt_idle_64b66b_test"
    RESULT_VARIABLE test_result
    OUTPUT_VARIABLE test_output
    ERROR_VARIABLE test_error)
message("${test_output}")
if(NOT test_result EQUAL 0)
    message(FATAL_ERROR
        "GT idle simulation failed:\n${test_output}\n${test_error}")
endif()
