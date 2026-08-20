set(CAPTURE_ELF "${CMAKE_CURRENT_BINARY_DIR}/capture.elf")
find_program(CAPTURE_RISCV_CC NAMES riscv32-unknown-elf-gcc
    HINTS "$ENV{RISCV_HOME}/bin" "/home/me/riscv/bin")
set(CAPTURE_RISCV_CC_ARGS)
if(NOT CAPTURE_RISCV_CC)
    find_program(CAPTURE_RISCV_CC NAMES clang
        HINTS "${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin"
        NO_DEFAULT_PATH REQUIRED)
endif()
get_filename_component(CAPTURE_RISCV_CC_NAME "${CAPTURE_RISCV_CC}" NAME)
if(CAPTURE_RISCV_CC_NAME MATCHES "^clang")
    set(CAPTURE_RISCV_CC_ARGS
        --target=riscv32-unknown-elf
        -fuse-ld=lld)
    message(STATUS
        "RISC-V GCC not found; building capture firmware with Clang/LLD")
endif()

add_custom_command(
    OUTPUT "${CAPTURE_ELF}"
    COMMAND "${CAPTURE_RISCV_CC}"
        ${CAPTURE_RISCV_CC_ARGS}
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

function(smartnic_add_capture_target sustained)
    if(sustained)
        set(target capture_2x10g_sustained_test)
        set(rate 2x10g)
        add_executable(${target} capture.cpp)
        set(suffix _sustained)
        set(sustained_value 1)
    else()
        set(target capture_2x10g_test)
        set(rate 2x10g)
        add_executable(${target} capture.cpp)
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

    if(BUILD_TESTING)
        add_test(NAME system_capture_${rate}${suffix}
            COMMAND "$<TARGET_FILE:${target}>" "${CAPTURE_ELF}")
        set_tests_properties(system_capture_${rate}${suffix} PROPERTIES
            WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
            LABELS "system;capture;cpu;avalon;${rate}${suffix}"
            TIMEOUT 3600)
    endif()
endfunction()

smartnic_add_capture_target(FALSE)
smartnic_add_capture_target(TRUE)
add_custom_target(run_capture_2x10g_sustained
    COMMAND "$<TARGET_FILE:capture_2x10g_sustained_test>" "${CAPTURE_ELF}"
    DEPENDS capture_2x10g_sustained_test capture_firmware
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    USES_TERMINAL
    VERBATIM)
