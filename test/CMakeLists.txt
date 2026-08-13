set(CAPTURE_ELF "${CMAKE_CURRENT_BINARY_DIR}/capture.elf")
find_program(CAPTURE_RISCV_CC NAMES riscv32-unknown-elf-gcc
    HINTS "$ENV{RISCV_HOME}/bin" "/home/me/riscv/bin" REQUIRED)

add_custom_command(
    OUTPUT "${CAPTURE_ELF}"
    COMMAND "${CAPTURE_RISCV_CC}"
        -march=rv32im_zicsr -mabi=ilp32
        -nostdlib
        -Wl,--no-relax
        "-Wl,-T,${CMAKE_CURRENT_SOURCE_DIR}/capture.ld"
        -Wl,--build-id=none
        -o "${CAPTURE_ELF}"
        "${CMAKE_CURRENT_SOURCE_DIR}/capture.S"
    DEPENDS capture.S capture.ld
    VERBATIM)
add_custom_target(capture_firmware DEPENDS "${CAPTURE_ELF}")

file(GLOB CAPTURE_STDCXXEXP
    "${PROJECT_SOURCE_DIR}/cpphdl/.conda/lib/gcc/*/*/libstdc++exp.a")

option(SMARTNIC_ENABLE_SUSTAINED_CAPTURE_TESTS
    "Register the long 2x10G throughput assertion in CTest"
    OFF)

function(smartnic_add_capture_target sustained)
    set(cdc_available TRUE)
    foreach(required_header
            "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common/Axi4Cdc.h"
            "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache/L1MemCdc.h")
        if(NOT EXISTS "${required_header}")
            set(cdc_available FALSE)
        endif()
    endforeach()
    if(sustained)
        set(target capture_20g_throughput_test)
        if(SMARTNIC_ENABLE_SUSTAINED_CAPTURE_TESTS AND cdc_available)
            add_executable(${target} capture.cpp)
        else()
            add_executable(${target} EXCLUDE_FROM_ALL capture.cpp)
        endif()
        set(suffix _throughput)
        set(sustained_value 1)
    else()
        set(target capture_20g_test)
        if(cdc_available)
            add_executable(${target} capture.cpp)
        else()
            add_executable(${target} EXCLUDE_FROM_ALL capture.cpp)
        endif()
        set(suffix "")
        set(sustained_value 0)
    endif()
    add_dependencies(${target} capture_firmware)
    target_compile_definitions(${target} PRIVATE
        SUSTAINED_CAPTURE=${sustained_value})
    target_include_directories(${target} PRIVATE
        "${PROJECT_SOURCE_DIR}"
        "${PROJECT_SOURCE_DIR}/cpphdl/include"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
    target_compile_options(${target} PRIVATE -std=c++26 -fno-strict-aliasing)
    cpphdl_add_host_opt_flags(${target})
    cpphdl_link_stdcxxexp_if_available(${target})
    if(CAPTURE_STDCXXEXP)
        list(GET CAPTURE_STDCXXEXP 0 CAPTURE_STDCXXEXP_LIBRARY)
        target_link_libraries(${target} PRIVATE "${CAPTURE_STDCXXEXP_LIBRARY}")
    endif()

    if(BUILD_TESTING AND cdc_available
            AND (NOT sustained OR SMARTNIC_ENABLE_SUSTAINED_CAPTURE_TESTS))
        add_test(NAME system_capture_20g${suffix}
            COMMAND "$<TARGET_FILE:${target}>" "${CAPTURE_ELF}")
        set_tests_properties(system_capture_20g${suffix} PROPERTIES
            WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
            LABELS "system;capture;cpu;avalon;20g${suffix}"
            TIMEOUT 3600)
    endif()
endfunction()

smartnic_add_capture_target(FALSE)
smartnic_add_capture_target(TRUE)
add_custom_target(run_capture_20g_throughput
    COMMAND "$<TARGET_FILE:capture_20g_throughput_test>" "${CAPTURE_ELF}"
    DEPENDS capture_20g_throughput_test capture_firmware
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    USES_TERMINAL
    VERBATIM)
