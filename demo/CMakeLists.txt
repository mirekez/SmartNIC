set(DEMO_CAPTURE_ELF "${CMAKE_CURRENT_BINARY_DIR}/capture.elf")
set(DEMO_VIDEO "${CMAKE_CURRENT_SOURCE_DIR}/output/smartnic_400g_long.avi")

find_package(ZLIB REQUIRED)

find_program(DEMO_RISCV_CC NAMES riscv32-unknown-elf-gcc
    HINTS "$ENV{RISCV_HOME}/bin" "/home/me/riscv/bin" REQUIRED)

add_custom_command(
    OUTPUT "${DEMO_CAPTURE_ELF}"
    COMMAND "${DEMO_RISCV_CC}"
        -march=rv32im_zicsr -mabi=ilp32
        -nostdlib
        -Wl,--no-relax
        "-Wl,-T,${CMAKE_CURRENT_SOURCE_DIR}/capture.ld"
        -Wl,--build-id=none
        -o "${DEMO_CAPTURE_ELF}"
        "${CMAKE_CURRENT_SOURCE_DIR}/capture.S"
    DEPENDS capture.S capture.ld
    VERBATIM)
add_custom_target(smartnic_demo_firmware DEPENDS "${DEMO_CAPTURE_ELF}")

add_executable(smartnic_400g_long_demo capture_demo.cpp)
add_dependencies(smartnic_400g_long_demo smartnic_demo_firmware)
target_compile_definitions(smartnic_400g_long_demo PRIVATE
    ENABLE_800G=0 HOST_AXI4=0 DEMO_VIDEO=1 DEMO_TRANSPARENT_VIDEO=0
    $<$<BOOL:${DEMO_SMOKE}>:DEMO_BASE_FRAME_COUNT=8>
    $<$<BOOL:${DEMO_SMOKE}>:DEMO_TRAFFIC_REPEATS=1>
    $<$<BOOL:${DEMO_SMOKE}>:DEMO_FRAME_BYTES=64>)
target_include_directories(smartnic_400g_long_demo PRIVATE
    "${PROJECT_SOURCE_DIR}"
    "${PROJECT_SOURCE_DIR}/cpphdl/include"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/common"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/spec"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/cache"
    "${PROJECT_SOURCE_DIR}/cpphdl/tribe_cpu/devices")
target_compile_options(smartnic_400g_long_demo PRIVATE
    -std=c++26 -fno-strict-aliasing -O2)
cpphdl_add_host_opt_flags(smartnic_400g_long_demo)
cpphdl_link_stdcxxexp_if_available(smartnic_400g_long_demo)
target_link_libraries(smartnic_400g_long_demo PRIVATE ZLIB::ZLIB)

file(GLOB DEMO_STDCXXEXP
    "${PROJECT_SOURCE_DIR}/cpphdl/.conda/lib/gcc/*/*/libstdc++exp.a")
if(DEMO_STDCXXEXP)
    list(GET DEMO_STDCXXEXP 0 DEMO_STDCXXEXP_LIBRARY)
    target_link_libraries(smartnic_400g_long_demo PRIVATE
        "${DEMO_STDCXXEXP_LIBRARY}")
endif()

add_custom_target(smartnic_400g_long_video
    COMMAND "$<TARGET_FILE:smartnic_400g_long_demo>"
        "${DEMO_CAPTURE_ELF}" "${DEMO_VIDEO}"
    DEPENDS smartnic_400g_long_demo smartnic_demo_firmware
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    USES_TERMINAL
    VERBATIM)

option(SMARTNIC_ENABLE_VIDEO_DEMO_TEST
    "Run the long AVI-producing 400G demo as part of CTest" OFF)
if(BUILD_TESTING AND SMARTNIC_ENABLE_VIDEO_DEMO_TEST)
    add_test(NAME smartnic_400g_long_video_demo
        COMMAND "$<TARGET_FILE:smartnic_400g_long_demo>"
            "${DEMO_CAPTURE_ELF}" "${DEMO_VIDEO}")
    set_tests_properties(smartnic_400g_long_video_demo PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        LABELS "system;capture;cpu;avalon;400g;throughput;demo"
        TIMEOUT 3600)
endif()
