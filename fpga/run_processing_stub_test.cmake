foreach(required VERILATOR VERILATOR_CXX VERILATOR_AR CPPHDL CPPHDL_INCLUDE
        REPO_DIR SOURCE TESTBENCH OUTPUT_DIR)
    if(NOT DEFINED ${required})
        message(FATAL_ERROR "Missing required argument ${required}")
    endif()
endforeach()

file(REMOVE_RECURSE "${OUTPUT_DIR}")
file(MAKE_DIRECTORY "${OUTPUT_DIR}/generated")
execute_process(
    COMMAND "${CPPHDL}" --generated-dir "${OUTPUT_DIR}/generated"
        --primary_clock clk 156250000 "${SOURCE}"
        -I "${CPPHDL_INCLUDE}"
        -I "${REPO_DIR}/rtl/processing"
        -I "${REPO_DIR}/rtl/network"
        -I "${REPO_DIR}/fpga" -I "${REPO_DIR}"
    RESULT_VARIABLE convert_result
    OUTPUT_VARIABLE convert_output
    ERROR_VARIABLE convert_error)
if(NOT convert_result EQUAL 0)
    message(FATAL_ERROR
        "ProcessingStub CppHDL conversion failed:\n${convert_output}\n${convert_error}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env "CXX=${VERILATOR_CXX}"
        "${VERILATOR}" --cc --exe --build --Wno-fatal --compiler clang
        -Wno-BLKSEQ -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
        -MAKEFLAGS
            "CXX=${VERILATOR_CXX} LINK=${VERILATOR_CXX} AR=${VERILATOR_AR}"
        --top-module ProcessingStub
        --Mdir "${OUTPUT_DIR}/obj"
        "${OUTPUT_DIR}/generated/Predef_pkg.sv"
        "${OUTPUT_DIR}/generated/UARTProbeMemory.sv"
        "${OUTPUT_DIR}/generated/UARTProbe.sv"
        "${OUTPUT_DIR}/generated/ProcessingStub.sv" "${TESTBENCH}"
    RESULT_VARIABLE compile_result
    OUTPUT_VARIABLE compile_output
    ERROR_VARIABLE compile_error)
if(NOT compile_result EQUAL 0)
    message(FATAL_ERROR
        "ProcessingStub Verilator build failed:\n${compile_output}\n${compile_error}")
endif()

execute_process(
    COMMAND "${OUTPUT_DIR}/obj/VProcessingStub"
    RESULT_VARIABLE test_result
    OUTPUT_VARIABLE test_output
    ERROR_VARIABLE test_error)
message("${test_output}")
if(NOT test_result EQUAL 0)
    message(FATAL_ERROR
        "ProcessingStub simulation failed:\n${test_output}\n${test_error}")
endif()
