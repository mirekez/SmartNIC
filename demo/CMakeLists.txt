set(DEMO_CAPTURE_ELF "${CMAKE_CURRENT_BINARY_DIR}/capture.elf")
set(DEMO_VIDEO "${CMAKE_CURRENT_SOURCE_DIR}/output/smartnic_2x10g_capture_4core_v4.avi")

find_path(SMARTNIC_ZLIB_INCLUDE_DIR zlib.h
    PATHS "${CPPHDL_ROOT}/.conda/include" NO_DEFAULT_PATH NO_CACHE)
find_library(SMARTNIC_ZLIB_LIBRARY z
    PATHS "${CPPHDL_ROOT}/.conda/lib" "${CPPHDL_ROOT}/.conda/lib64"
    NO_DEFAULT_PATH NO_CACHE)
if(SMARTNIC_ZLIB_INCLUDE_DIR AND SMARTNIC_ZLIB_LIBRARY)
    set(ZLIB_INCLUDE_DIR "${SMARTNIC_ZLIB_INCLUDE_DIR}")
    set(ZLIB_LIBRARY "${SMARTNIC_ZLIB_LIBRARY}")
endif()
find_package(ZLIB REQUIRED)

find_program(DEMO_RISCV_GCC NAMES riscv32-unknown-elf-gcc
    HINTS "$ENV{RISCV_HOME}/bin" "/home/me/riscv/bin")
set(DEMO_RISCV_CC_ARGS)
if(DEMO_RISCV_GCC)
    set(DEMO_RISCV_CC "${DEMO_RISCV_GCC}")
else()
    find_program(DEMO_RISCV_CLANG NAMES clang
        HINTS "${PROJECT_SOURCE_DIR}/cpphdl/.conda/bin"
        NO_DEFAULT_PATH REQUIRED)
    set(DEMO_RISCV_CC "${DEMO_RISCV_CLANG}")
    set(DEMO_RISCV_CC_ARGS --target=riscv32-unknown-elf -fuse-ld=lld)
    message(STATUS "RISC-V GCC not found; building demo firmware with Clang/LLD")
endif()

add_custom_command(
    OUTPUT "${DEMO_CAPTURE_ELF}"
    COMMAND "${DEMO_RISCV_CC}" ${DEMO_RISCV_CC_ARGS}
        -march=rv32im_zicsr -mabi=ilp32 -nostdlib -Wl,--no-relax
        "-Wl,-T,${CMAKE_CURRENT_SOURCE_DIR}/capture.ld"
        -Wl,--build-id=none -o "${DEMO_CAPTURE_ELF}"
        "${CMAKE_CURRENT_SOURCE_DIR}/capture.S"
    DEPENDS capture.S capture.ld
    VERBATIM)
add_custom_target(smartnic_demo_firmware DEPENDS "${DEMO_CAPTURE_ELF}")

# Compile the actual full-system capture test with visualization enabled.
add_executable(smartnic_capture_demo "${PROJECT_SOURCE_DIR}/test/capture.cpp")
add_dependencies(smartnic_capture_demo smartnic_demo_firmware)
target_compile_definitions(smartnic_capture_demo PRIVATE
    SUSTAINED_CAPTURE=0 DEMO_VIDEO=1 DEMO_TRANSPARENT_VIDEO=0
    DEMO_CAPTURE_INTERVAL=40 DEMO_BASE_FRAME_COUNT=32
    DEMO_NETWORK_INTERVAL=20
    DEMO_TRAFFIC_REPEATS=10 DEMO_FRAME_BYTES=1516
    DEMO_IPG_BYTES=384 DEMO_VIDEO_DECIMATION=12)
target_include_directories(smartnic_capture_demo PRIVATE
    "${PROJECT_SOURCE_DIR}" "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
target_compile_options(smartnic_capture_demo PRIVATE
    -std=c++26 -fno-strict-aliasing -O2)
cpphdl_add_host_opt_flags(smartnic_capture_demo)
cpphdl_link_stdcxxexp_if_available(smartnic_capture_demo)
target_link_libraries(smartnic_capture_demo PRIVATE ZLIB::ZLIB)

add_custom_target(smartnic_capture_video
    COMMAND "$<TARGET_FILE:smartnic_capture_demo>"
        "${DEMO_CAPTURE_ELF}" "${DEMO_VIDEO}"
    DEPENDS smartnic_capture_demo smartnic_demo_firmware
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    USES_TERMINAL VERBATIM)

# Learning-switch demonstration: the real l2_switch regression and firmware,
# augmented only with observers that render accepted RTL handshakes.
set(DEMO_L2_SWITCH_ELF "${CMAKE_CURRENT_BINARY_DIR}/l2_switch_sustained.elf")
set(DEMO_L2_SWITCH_VIDEO
    "${CMAKE_CURRENT_SOURCE_DIR}/output/smartnic_l2_switch_all_packets_v15.avi")
add_custom_command(
    OUTPUT "${DEMO_L2_SWITCH_ELF}"
    COMMAND "${DEMO_RISCV_CC}" ${DEMO_RISCV_CC_ARGS}
        -DSUSTAINED_SWITCH=1
        -march=rv32im_zicsr -mabi=ilp32 -nostdlib -Wl,--no-relax
        "-Wl,-T,${PROJECT_SOURCE_DIR}/test/l2_switch.ld"
        -Wl,--build-id=none -o "${DEMO_L2_SWITCH_ELF}"
        "${PROJECT_SOURCE_DIR}/test/l2_switch.S"
    DEPENDS "${PROJECT_SOURCE_DIR}/test/l2_switch.S"
        "${PROJECT_SOURCE_DIR}/test/l2_switch.ld"
    VERBATIM)
add_custom_target(smartnic_l2_switch_firmware
    DEPENDS "${DEMO_L2_SWITCH_ELF}")
add_executable(smartnic_l2_switch_demo
    "${PROJECT_SOURCE_DIR}/test/l2_switch.cpp")
add_dependencies(smartnic_l2_switch_demo smartnic_l2_switch_firmware)
target_compile_definitions(smartnic_l2_switch_demo PRIVATE
    SUSTAINED_SWITCH=1 DEMO_VIDEO=1 DEMO_L2_SWITCH=1
    CPU_RESET_PC=0x00100000
    DEMO_SWITCH_LEARNING_PACKETS=0 DEMO_TRANSPARENT_VIDEO=0
    DEMO_NETWORK_INTERVAL=1 DEMO_TRAFFIC_REPEATS=10
    DEMO_VIDEO_DECIMATION=12)
target_include_directories(smartnic_l2_switch_demo PRIVATE
    "${PROJECT_SOURCE_DIR}" "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
target_compile_options(smartnic_l2_switch_demo PRIVATE
    -std=c++26 -fno-strict-aliasing -O2)
cpphdl_add_host_opt_flags(smartnic_l2_switch_demo)
cpphdl_link_stdcxxexp_if_available(smartnic_l2_switch_demo)
target_link_libraries(smartnic_l2_switch_demo PRIVATE ZLIB::ZLIB)

add_custom_target(smartnic_l2_switch_video
    COMMAND "$<TARGET_FILE:smartnic_l2_switch_demo>"
        "${DEMO_L2_SWITCH_ELF}" "${DEMO_L2_SWITCH_VIDEO}"
    DEPENDS smartnic_l2_switch_demo smartnic_l2_switch_firmware
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    USES_TERMINAL VERBATIM)

# Fast, non-rendering version of the same sustained workload for performance
# debugging and CI. It uses the identical firmware, traffic and assertions.
add_executable(smartnic_l2_switch_sustained_check
    "${PROJECT_SOURCE_DIR}/test/l2_switch.cpp")
add_dependencies(smartnic_l2_switch_sustained_check
    smartnic_l2_switch_firmware)
target_compile_definitions(smartnic_l2_switch_sustained_check PRIVATE
    SUSTAINED_SWITCH=1 DEMO_VIDEO=0 CPU_RESET_PC=0x00100000
    DEMO_NETWORK_INTERVAL=1
    DEMO_TRAFFIC_REPEATS=10)
target_include_directories(smartnic_l2_switch_sustained_check PRIVATE
    "${PROJECT_SOURCE_DIR}" "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
target_compile_options(smartnic_l2_switch_sustained_check PRIVATE
    -std=c++26 -fno-strict-aliasing -O2)
cpphdl_add_host_opt_flags(smartnic_l2_switch_sustained_check)
cpphdl_link_stdcxxexp_if_available(smartnic_l2_switch_sustained_check)
if(BUILD_TESTING)
    add_test(NAME system_l2_switch_sustained_80pct
        COMMAND "$<TARGET_FILE:smartnic_l2_switch_sustained_check>"
            "${DEMO_L2_SWITCH_ELF}")
    set_tests_properties(system_l2_switch_sustained_80pct PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "system;switch;cpu;l2;ddr4;throughput;80pct"
        TIMEOUT 3600)
endif()
