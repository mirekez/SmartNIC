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

set(CPU_LOOPBACK_ELF "${CMAKE_CURRENT_BINARY_DIR}/cpu_loopback.elf")
add_custom_command(
    OUTPUT "${CPU_LOOPBACK_ELF}"
    COMMAND "${CAPTURE_RISCV_CC}"
        ${CAPTURE_RISCV_CC_ARGS}
        -march=rv32im_zicsr -mabi=ilp32
        -nostdlib
        -Wl,--no-relax
        "-Wl,-T,${CMAKE_CURRENT_SOURCE_DIR}/capture.ld"
        -Wl,--build-id=none
        -o "${CPU_LOOPBACK_ELF}"
        "${CMAKE_CURRENT_SOURCE_DIR}/cpu_loopback.S"
    DEPENDS cpu_loopback.S capture.ld
    VERBATIM)
add_custom_target(cpu_loopback_firmware DEPENDS "${CPU_LOOPBACK_ELF}")

set(CPU_LOOPBACK_MULTICORE_ELF
    "${CMAKE_CURRENT_BINARY_DIR}/cpu_loopback_multicore.elf")
add_custom_command(
    OUTPUT "${CPU_LOOPBACK_MULTICORE_ELF}"
    COMMAND "${CAPTURE_RISCV_CC}"
        ${CAPTURE_RISCV_CC_ARGS}
        -DCPU_LOOPBACK_MULTICORE=1
        -march=rv32im_zicsr -mabi=ilp32
        -nostdlib
        -Wl,--no-relax
        "-Wl,-T,${CMAKE_CURRENT_SOURCE_DIR}/capture.ld"
        -Wl,--build-id=none
        -o "${CPU_LOOPBACK_MULTICORE_ELF}"
        "${CMAKE_CURRENT_SOURCE_DIR}/cpu_loopback.S"
    DEPENDS cpu_loopback.S capture.ld
    VERBATIM)
add_custom_target(cpu_loopback_multicore_firmware
    DEPENDS "${CPU_LOOPBACK_MULTICORE_ELF}")

set(L2_SWITCH_ELF "${CMAKE_CURRENT_BINARY_DIR}/l2_switch.elf")
add_custom_command(
    OUTPUT "${L2_SWITCH_ELF}"
    COMMAND "${CAPTURE_RISCV_CC}"
        ${CAPTURE_RISCV_CC_ARGS}
        -march=rv32im_zicsr -mabi=ilp32
        -nostdlib -Wl,--no-relax
        "-Wl,-T,${CMAKE_CURRENT_SOURCE_DIR}/l2_switch.ld"
        -Wl,--build-id=none
        -o "${L2_SWITCH_ELF}"
        "${CMAKE_CURRENT_SOURCE_DIR}/l2_switch.S"
    DEPENDS l2_switch.S l2_switch.ld
    VERBATIM)
add_custom_target(l2_switch_firmware DEPENDS "${L2_SWITCH_ELF}")

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
            LABELS "system;capture;cpu;axi4;${rate}${suffix}"
            TIMEOUT 3600)
    endif()
endfunction()

smartnic_add_capture_target(FALSE)
smartnic_add_capture_target(TRUE)

add_executable(l2_switch_test l2_switch.cpp)
add_dependencies(l2_switch_test l2_switch_firmware)
target_compile_definitions(l2_switch_test PRIVATE CPU_RESET_PC=0x00100000)
target_include_directories(l2_switch_test PRIVATE
    "${PROJECT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
target_compile_options(l2_switch_test PRIVATE -std=c++26 -fno-strict-aliasing)
cpphdl_add_host_opt_flags(l2_switch_test)
cpphdl_link_stdcxxexp_if_available(l2_switch_test)
if(CAPTURE_STDCXXEXP)
    target_link_libraries(l2_switch_test PRIVATE "${CAPTURE_STDCXXEXP_LIBRARY}")
endif()
if(BUILD_TESTING)
    add_test(NAME system_l2_switch
        COMMAND "$<TARGET_FILE:l2_switch_test>" "${L2_SWITCH_ELF}")
    set_tests_properties(system_l2_switch PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "system;switch;cpu;l2;ddr4;axi4"
        TIMEOUT 3600)
endif()

# Four-core MAC-lookup and forwarding benchmarks.  Firmware and harness use
# the same compile-time frame length so PacketDMA never reads beyond EOP.
function(smartnic_add_l2_switch_perf frame_bytes)
    set(firmware
        "${CMAKE_CURRENT_BINARY_DIR}/l2_switch_perf_${frame_bytes}.elf")
    set(firmware_target "l2_switch_perf_${frame_bytes}_firmware")
    set(test_target "l2_switch_perf_${frame_bytes}_test")
    add_custom_command(
        OUTPUT "${firmware}"
        COMMAND "${CAPTURE_RISCV_CC}"
            ${CAPTURE_RISCV_CC_ARGS}
            -DSUSTAINED_SWITCH=1
            -DL2_SWITCH_FRAME_BYTES=${frame_bytes}
            # Keep ingress outside the measured four-core lookup interval.
            # The 512-slot ring holds all 400 packets without reuse.
            -DL2_SWITCH_PROCESSING_LEAD=400
            -march=rv32im_zicsr -mabi=ilp32
            -nostdlib -Wl,--no-relax
            "-Wl,-T,${CMAKE_CURRENT_SOURCE_DIR}/l2_switch.ld"
            -Wl,--build-id=none
            -o "${firmware}"
            "${CMAKE_CURRENT_SOURCE_DIR}/l2_switch.S"
        DEPENDS l2_switch.S l2_switch.ld
        VERBATIM)
    add_custom_target(${firmware_target} DEPENDS "${firmware}")

    add_executable(${test_target} l2_switch.cpp)
    add_dependencies(${test_target} ${firmware_target})
    target_compile_definitions(${test_target} PRIVATE
        CPU_RESET_PC=0x00100000 SUSTAINED_SWITCH=1
        L2_SWITCH_PER_CORE_PERF=1
        L2_SWITCH_FRAME_BYTES=${frame_bytes}
        DEMO_NETWORK_INTERVAL=1 DEMO_TRAFFIC_REPEATS=10)
    target_include_directories(${test_target} PRIVATE
        "${PROJECT_SOURCE_DIR}"
        "${PROJECT_SOURCE_DIR}/cpphdl/include"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
        "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
    target_compile_options(${test_target} PRIVATE
        -std=c++26 -fno-strict-aliasing)
    cpphdl_add_host_opt_flags(${test_target})
    cpphdl_link_stdcxxexp_if_available(${test_target})
    if(CAPTURE_STDCXXEXP)
        target_link_libraries(${test_target} PRIVATE
            "${CAPTURE_STDCXXEXP_LIBRARY}")
    endif()
    if(BUILD_TESTING)
        add_test(NAME system_l2_switch_4core_${frame_bytes}
            COMMAND "$<TARGET_FILE:${test_target}>" "${firmware}")
        set_tests_properties(system_l2_switch_4core_${frame_bytes} PROPERTIES
            WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
            LABELS "system;switch;cpu;multicore;l2;dma;axi4;performance"
            TIMEOUT 3600)
    endif()
endfunction()

foreach(frame_bytes IN ITEMS 64 300 1000 1500)
    smartnic_add_l2_switch_perf(${frame_bytes})
endforeach()

add_executable(cpu_loopback_multicore_test cpu_loopback.cpp)
add_dependencies(cpu_loopback_multicore_test cpu_loopback_multicore_firmware)
target_compile_definitions(cpu_loopback_multicore_test PRIVATE
    CPU_RESET_PC=0 SMARTNIC_READ_PORTS=1 CPU_LOOPBACK_PERFORMANCE_TEST=1
    CPU_LOOPBACK_MULTICORE_TEST=1 CPU_LOOPBACK_ENFORCE_BASELINE=0)
target_include_directories(cpu_loopback_multicore_test PRIVATE
    "${PROJECT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
target_compile_options(cpu_loopback_multicore_test PRIVATE
    -std=c++26 -fno-strict-aliasing)
cpphdl_add_host_opt_flags(cpu_loopback_multicore_test)
cpphdl_link_stdcxxexp_if_available(cpu_loopback_multicore_test)
if(CAPTURE_STDCXXEXP)
    target_link_libraries(cpu_loopback_multicore_test PRIVATE
        "${CAPTURE_STDCXXEXP_LIBRARY}")
endif()
if(BUILD_TESTING)
    add_test(NAME system_cpu_loopback_multicore
        COMMAND "$<TARGET_FILE:cpu_loopback_multicore_test>"
            "${CPU_LOOPBACK_MULTICORE_ELF}")
    set_tests_properties(system_cpu_loopback_multicore PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "system;loopback;cpu;multicore;l2;dma;axi4"
        TIMEOUT 1200)
endif()

add_executable(cpu_loopback_test cpu_loopback.cpp)
add_dependencies(cpu_loopback_test cpu_loopback_firmware)
target_compile_definitions(cpu_loopback_test PRIVATE
    CPU_RESET_PC=0 SMARTNIC_READ_PORTS=1)
target_include_directories(cpu_loopback_test PRIVATE
    "${PROJECT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
target_compile_options(cpu_loopback_test PRIVATE -std=c++26 -fno-strict-aliasing)
cpphdl_add_host_opt_flags(cpu_loopback_test)
cpphdl_link_stdcxxexp_if_available(cpu_loopback_test)
if(CAPTURE_STDCXXEXP)
    target_link_libraries(cpu_loopback_test PRIVATE "${CAPTURE_STDCXXEXP_LIBRARY}")
endif()
if(BUILD_TESTING)
    add_test(NAME system_cpu_loopback
        COMMAND "$<TARGET_FILE:cpu_loopback_test>" "${CPU_LOOPBACK_ELF}")
    set_tests_properties(system_cpu_loopback PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "system;loopback;cpu;l2;dma;axi4"
        TIMEOUT 1200)
endif()
add_custom_target(run_capture_2x10g_sustained
    COMMAND "$<TARGET_FILE:capture_2x10g_sustained_test>" "${CAPTURE_ELF}"
    DEPENDS capture_2x10g_sustained_test capture_firmware
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    USES_TERMINAL
    VERBATIM)
