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

function(smartnic_add_capture_target rate sustained)
    if(sustained)
        set(target capture_${rate}_throughput_test)
        add_executable(${target} capture.cpp)
        set(suffix _throughput)
        set(sustained_value 1)
    else()
        set(target capture_${rate}_test)
        add_executable(${target} capture.cpp)
        set(suffix "")
        set(sustained_value 0)
    endif()
    add_dependencies(${target} capture_firmware)
    if(rate EQUAL 800)
        target_compile_definitions(${target} PRIVATE ENABLE_800G=1
            SUSTAINED_CAPTURE=${sustained_value})
    else()
        target_compile_definitions(${target} PRIVATE ENABLE_800G=0
            SUSTAINED_CAPTURE=${sustained_value})
    endif()
    target_include_directories(${target} PRIVATE
        "${PROJECT_SOURCE_DIR}"
        "${PROJECT_SOURCE_DIR}/cpphdl/include"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
    target_compile_options(${target} PRIVATE -std=c++26 -fno-strict-aliasing -O2)
    cpphdl_add_host_opt_flags(${target})
    cpphdl_link_stdcxxexp_if_available(${target})
    if(CAPTURE_STDCXXEXP)
        list(GET CAPTURE_STDCXXEXP 0 CAPTURE_STDCXXEXP_LIBRARY)
        target_link_libraries(${target} PRIVATE "${CAPTURE_STDCXXEXP_LIBRARY}")
    endif()

    if(BUILD_TESTING)
        add_test(NAME system_capture_${rate}${suffix}
            COMMAND "$<TARGET_FILE:${target}>" "${CAPTURE_ELF}")
        set_tests_properties(system_capture_${rate}${suffix} PROPERTIES
            WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
            LABELS "system;capture;cpu;avalon;${rate}g${suffix}"
            TIMEOUT 3600)
    endif()
endfunction()

foreach(rate 400 800)
    smartnic_add_capture_target(${rate} FALSE)
    if(rate EQUAL 400)
        smartnic_add_capture_target(${rate} TRUE)
        add_custom_target(run_capture_${rate}_throughput
            COMMAND "$<TARGET_FILE:capture_${rate}_throughput_test>" "${CAPTURE_ELF}"
            DEPENDS capture_${rate}_throughput_test capture_firmware
            WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
            USES_TERMINAL
            VERBATIM)
    endif()
endforeach()
