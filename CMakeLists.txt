cmake_minimum_required(VERSION 3.20)

# Bootstrap CppHDL before project() so a fresh SmartNIC checkout can select the
# compiler from the exported CppHDL Conda environment. SmartNIC normally uses
# the converter already built in that checkout.
set(CPPHDL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/cpphdl")
set(CPPHDL_GIT_REPOSITORY "https://github.com/mirekez/cpphdl.git" CACHE STRING
    "CppHDL Git repository")
set(CPPHDL_GIT_TAG "main" CACHE STRING "CppHDL Git branch or tag")
option(CPPHDL_AUTO_PREPARE
    "Clone and minimally prepare CppHDL when required" ON)
set(CPPHDL_BUILD_DIR "${CPPHDL_ROOT}/build" CACHE PATH
    "Standalone minimal CppHDL build directory")
set(CPPHDL_EXECUTABLE "${CPPHDL_BUILD_DIR}/cpphdl" CACHE FILEPATH
    "CppHDL converter executable")
set(CPPHDL_MINIFORGE_VERSION "26.3.2-2" CACHE STRING
    "Miniforge release used when Conda is not installed on the host")

function(cpphdl_run_preparation_step description)
    message(STATUS "CppHDL: ${description}")
    execute_process(
        COMMAND ${ARGN}
        RESULT_VARIABLE step_result
        COMMAND_ECHO STDOUT)
    if(NOT step_result EQUAL 0)
        message(FATAL_ERROR "CppHDL preparation failed while ${description}")
    endif()
endfunction()

function(cpphdl_run_retryable_preparation_step description)
    foreach(attempt RANGE 1 3)
        message(STATUS "CppHDL: ${description} (attempt ${attempt}/3)")
        execute_process(
            COMMAND ${ARGN}
            RESULT_VARIABLE step_result
            COMMAND_ECHO STDOUT)
        if(step_result EQUAL 0)
            return()
        endif()
    endforeach()
    message(FATAL_ERROR "CppHDL preparation failed while ${description}")
endfunction()

function(cpphdl_clone repository tag destination)
    foreach(attempt RANGE 1 3)
        message(STATUS
            "CppHDL: cloning ${repository} into ${destination} (attempt ${attempt}/3)")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -c http.version=HTTP/1.1 clone
                --depth 1 --branch "${tag}" "${repository}" "${destination}"
            RESULT_VARIABLE clone_result
            COMMAND_ECHO STDOUT)
        if(clone_result EQUAL 0)
            return()
        endif()
    endforeach()
    message(FATAL_ERROR
        "CppHDL preparation failed while cloning ${repository} into ${destination}")
endfunction()

function(cpphdl_bootstrap_conda prefix out_executable)
    if(EXISTS "${prefix}" AND NOT EXISTS "${prefix}/bin/conda")
        message(FATAL_ERROR
            "CppHDL Conda prefix ${prefix} exists but is incomplete. Remove "
            "that incomplete directory and configure again.")
    endif()

    execute_process(
        COMMAND uname -s
        OUTPUT_VARIABLE host_system
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE uname_system_result)
    execute_process(
        COMMAND uname -m
        OUTPUT_VARIABLE host_arch
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE uname_arch_result)
    if(NOT uname_system_result EQUAL 0 OR NOT uname_arch_result EQUAL 0
            OR NOT host_system STREQUAL "Linux")
        message(FATAL_ERROR
            "Automatic Miniforge bootstrap currently supports Linux. Install "
            "Conda manually or provide CPPHDL_CONDA_EXECUTABLE.")
    endif()

    if(host_arch STREQUAL "x86_64")
        set(installer_sha256
            "42260ffe3830fb953d5eee1bbb32229ff06aa7c3833c1ed7a9a0420a95685d94")
    elseif(host_arch STREQUAL "aarch64")
        set(installer_sha256
            "f4096a92482b30f04534cddb63d8bc929118318deffac71d90fb89dc52359d22")
    elseif(host_arch STREQUAL "ppc64le")
        set(installer_sha256
            "8b3527cd4c70e6eb4a6c2c4c41de34c2480f0a5200de2ecb7fe385d186af0869")
    else()
        message(FATAL_ERROR
            "Automatic Miniforge bootstrap does not support Linux ${host_arch}. "
            "Install Conda manually or provide CPPHDL_CONDA_EXECUTABLE.")
    endif()

    set(installer_name
        "Miniforge3-${CPPHDL_MINIFORGE_VERSION}-Linux-${host_arch}.sh")
    set(installer_url
        "https://github.com/conda-forge/miniforge/releases/download/${CPPHDL_MINIFORGE_VERSION}/${installer_name}")
    set(installer_path "${CMAKE_BINARY_DIR}/${installer_name}")
    message(STATUS "CppHDL: downloading Miniforge from ${installer_url}")
    file(DOWNLOAD "${installer_url}" "${installer_path}"
        EXPECTED_HASH "SHA256=${installer_sha256}"
        STATUS download_status
        TLS_VERIFY ON
        SHOW_PROGRESS)
    list(GET download_status 0 download_result)
    list(GET download_status 1 download_message)
    if(NOT download_result EQUAL 0)
        file(REMOVE "${installer_path}")
        message(FATAL_ERROR
            "CppHDL Miniforge download failed: ${download_message}")
    endif()

    cpphdl_run_preparation_step("installing Miniforge into ${prefix}"
        /bin/bash "${installer_path}" -b -p "${prefix}")
    file(REMOVE "${installer_path}")
    if(NOT EXISTS "${prefix}/bin/conda")
        message(FATAL_ERROR
            "Miniforge installation did not produce ${prefix}/bin/conda")
    endif()
    set(${out_executable} "${prefix}/bin/conda" PARENT_SCOPE)
endfunction()

if(CPPHDL_AUTO_PREPARE)
    if(NOT EXISTS "${CPPHDL_ROOT}/CMakeLists.txt")
        find_package(Git REQUIRED)
        cpphdl_clone("${CPPHDL_GIT_REPOSITORY}" "${CPPHDL_GIT_TAG}"
            "${CPPHDL_ROOT}")
    endif()

    set(CPPHDL_CONDA_PREFIX "${CPPHDL_ROOT}/.conda")
    set(CPPHDL_CONDA_CC "${CPPHDL_CONDA_PREFIX}/bin/clang")
    set(CPPHDL_CONDA_CXX "${CPPHDL_CONDA_PREFIX}/bin/clang++")
    set(CPPHDL_CONDA_CMAKE "${CPPHDL_CONDA_PREFIX}/bin/cmake")
    set(CPPHDL_CONDA_LLD "${CPPHDL_CONDA_PREFIX}/bin/ld.lld")
    set(CPPHDL_CLANG_TOOLING_HEADER
        "${CPPHDL_CONDA_PREFIX}/include/clang/Tooling/Tooling.h")

    set(CPPHDL_CONDA_ENV_INCOMPLETE OFF)
    if(NOT EXISTS "${CPPHDL_CONDA_CXX}"
            OR NOT EXISTS "${CPPHDL_CONDA_CMAKE}"
            OR NOT EXISTS "${CPPHDL_CLANG_TOOLING_HEADER}")
        set(CPPHDL_CONDA_ENV_INCOMPLETE ON)
    endif()
    if(CPPHDL_CONDA_ENV_INCOMPLETE OR NOT EXISTS "${CPPHDL_CONDA_LLD}")
        find_program(CPPHDL_CONDA_EXECUTABLE NAMES conda
            DOC "Conda executable used to prepare CppHDL")
        if(NOT CPPHDL_CONDA_EXECUTABLE)
            cpphdl_bootstrap_conda("${CPPHDL_CONDA_PREFIX}"
                CPPHDL_CONDA_EXECUTABLE)
            set(CPPHDL_CONDA_EXECUTABLE "${CPPHDL_CONDA_EXECUTABLE}"
                CACHE FILEPATH "Conda executable used to prepare CppHDL" FORCE)
        endif()
        if(CPPHDL_CONDA_ENV_INCOMPLETE)
            if(EXISTS "${CPPHDL_CONDA_PREFIX}/conda-meta")
                cpphdl_run_retryable_preparation_step(
                    "updating its Conda environment"
                    "${CPPHDL_CONDA_EXECUTABLE}" env update
                    --prefix "${CPPHDL_CONDA_PREFIX}"
                    --file "${CPPHDL_ROOT}/requirements.yaml")
            else()
                cpphdl_run_retryable_preparation_step(
                    "creating its Conda environment"
                    "${CPPHDL_CONDA_EXECUTABLE}" env create --yes
                    --prefix "${CPPHDL_CONDA_PREFIX}"
                    --file "${CPPHDL_ROOT}/requirements.yaml")
            endif()
        endif()
        if(NOT EXISTS "${CPPHDL_CONDA_LLD}")
            cpphdl_run_retryable_preparation_step(
                "installing its minimal RISC-V linker"
                "${CPPHDL_CONDA_EXECUTABLE}" install --yes
                --freeze-installed
                --prefix "${CPPHDL_CONDA_PREFIX}"
                --channel conda-forge "lld=21.1.3")
        endif()
    endif()

    # The converter is required while SmartNIC targets are built.  Prepare it
    # as a standalone, converter-only CppHDL build so a first `cmake ..` does
    # not rely on an already activated environment or build the CppHDL tests,
    # examples, hdlcpp, or Tribe CPU test suite.
    if(NOT EXISTS "${CPPHDL_EXECUTABLE}")
        cpphdl_run_preparation_step("configuring its minimal converter build"
            "${CPPHDL_CONDA_CMAKE}"
            -S "${CPPHDL_ROOT}"
            -B "${CPPHDL_BUILD_DIR}"
            -G "Unix Makefiles"
            "-DCMAKE_BUILD_TYPE=Release"
            "-DCMAKE_C_COMPILER=${CPPHDL_CONDA_CC}"
            "-DCMAKE_CXX_COMPILER=${CPPHDL_CONDA_CXX}"
            "-DCMAKE_MAKE_PROGRAM=${CPPHDL_CONDA_PREFIX}/bin/make"
            "-DCPPHDL_USE_LOCAL_CONDA=ON"
            "-DCPPHDL_LOCAL_CONDA_PREFIX=${CPPHDL_CONDA_PREFIX}"
            "-DCPPHDL_FETCH_LLVM=OFF"
            "-DCPPHDL_BUILD_EXAMPLES=OFF"
            "-DCPPHDL_BUILD_TESTS=OFF"
            "-DCPPHDL_BUILD_TRIBE=OFF"
            "-DCPPHDL_BUILD_HDLCPP=OFF"
            "-DBUILD_TESTING=OFF")
        cpphdl_run_preparation_step("building its converter"
            "${CPPHDL_CONDA_CMAKE}" --build "${CPPHDL_BUILD_DIR}"
            --target cpphdl --parallel)
        if(NOT EXISTS "${CPPHDL_EXECUTABLE}")
            message(FATAL_ERROR
                "CppHDL preparation completed without producing "
                "${CPPHDL_EXECUTABLE}")
        endif()
    endif()
elseif(NOT EXISTS "${CPPHDL_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR
        "CppHDL is missing at ${CPPHDL_ROOT}. Enable CPPHDL_AUTO_PREPARE "
        "or provide a checkout in the top project folder.")
endif()

if(NOT DEFINED CMAKE_C_COMPILER AND EXISTS "${CPPHDL_ROOT}/.conda/bin/clang")
    set(CMAKE_C_COMPILER "${CPPHDL_ROOT}/.conda/bin/clang"
        CACHE FILEPATH "C compiler" FORCE)
endif()
if(NOT DEFINED CMAKE_CXX_COMPILER AND EXISTS "${CPPHDL_ROOT}/.conda/bin/clang++")
    set(CMAKE_CXX_COMPILER "${CPPHDL_ROOT}/.conda/bin/clang++"
        CACHE FILEPATH "C++ compiler" FORCE)
endif()

# Keep the prepared prefix explicit for CppHDL-compatible project helpers.
set(CPPHDL_USE_LOCAL_CONDA ON CACHE BOOL "" FORCE)
set(CPPHDL_LOCAL_CONDA_PREFIX "${CPPHDL_ROOT}/.conda" CACHE PATH "" FORCE)

project(smartnic LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Preparation-only RTL dependency.  Unlike FetchContent SOURCE_DIR, this does
# not treat the source-tree checkout as disposable during reconfiguration.
set(ETH_PCS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/eth_pcs")
set(ETH_PCS_GIT_REPOSITORY "https://github.com/mirekez/eth_pcs.git" CACHE STRING
    "Ethernet PCS Git repository")
set(ETH_PCS_GIT_TAG "main" CACHE STRING "Ethernet PCS Git branch or tag")
option(ETH_PCS_AUTO_PREPARE "Clone Ethernet PCS when it is missing" ON)
if(ETH_PCS_AUTO_PREPARE AND NOT EXISTS "${ETH_PCS_ROOT}/CMakeLists.txt")
    find_package(Git REQUIRED)
    foreach(attempt RANGE 1 3)
        message(STATUS
            "Ethernet PCS: cloning ${ETH_PCS_GIT_REPOSITORY} into ${ETH_PCS_ROOT} (attempt ${attempt}/3)")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -c http.version=HTTP/1.1 clone
                --depth 1 --branch "${ETH_PCS_GIT_TAG}"
                "${ETH_PCS_GIT_REPOSITORY}" "${ETH_PCS_ROOT}"
            RESULT_VARIABLE ETH_PCS_CLONE_RESULT
            COMMAND_ECHO STDOUT)
        if(ETH_PCS_CLONE_RESULT EQUAL 0)
            break()
        endif()
    endforeach()
    if(NOT ETH_PCS_CLONE_RESULT EQUAL 0)
        message(FATAL_ERROR
            "Ethernet PCS preparation failed while cloning ${ETH_PCS_GIT_REPOSITORY}")
    endif()
elseif(NOT EXISTS "${ETH_PCS_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR
        "Ethernet PCS is missing at ${ETH_PCS_ROOT}. Enable ETH_PCS_AUTO_PREPARE "
        "or provide a checkout in the top project folder.")
endif()

# CppHDL is a prepared build tool, not part of the SmartNIC target graph.
if(NOT EXISTS "${CPPHDL_EXECUTABLE}")
    message(FATAL_ERROR
        "CppHDL converter is missing at ${CPPHDL_EXECUTABLE}. Enable "
        "CPPHDL_AUTO_PREPARE or provide CPPHDL_EXECUTABLE explicitly.")
endif()
message(STATUS "Using prepared CppHDL converter: ${CPPHDL_EXECUTABLE}")
add_executable(cpphdl IMPORTED GLOBAL)
set_target_properties(cpphdl PROPERTIES
    IMPORTED_LOCATION "${CPPHDL_EXECUTABLE}")
set(CPPHDL_CONVERTER_DEPENDENCY "${CPPHDL_EXECUTABLE}")

set(CPPHDL_HOST_OPT_FLAGS "" CACHE STRING
    "Optional optimization flags for SmartNIC host simulations")
file(GLOB CPPHDL_STDCXXEXP_CANDIDATES
    "${CPPHDL_ROOT}/.conda/lib/gcc/*/*/libstdc++exp.a")
if(CPPHDL_STDCXXEXP_CANDIDATES)
    list(GET CPPHDL_STDCXXEXP_CANDIDATES 0 CPPHDL_STDCXXEXP)
endif()

function(cpphdl_link_stdcxxexp_if_available target)
    if(CPPHDL_STDCXXEXP)
        target_link_libraries(${target} PRIVATE "${CPPHDL_STDCXXEXP}")
    endif()
endfunction()

function(cpphdl_add_host_opt_flags target)
    if(CPPHDL_HOST_OPT_FLAGS)
        separate_arguments(CPPHDL_HOST_OPT_FLAGS_LIST NATIVE_COMMAND
            "${CPPHDL_HOST_OPT_FLAGS}")
        target_compile_options(${target} PRIVATE
            ${CPPHDL_HOST_OPT_FLAGS_LIST})
    endif()
endfunction()

function(cpphdl_add_converter_dependency target)
    # Relink the owning simulation if the external converter changes so its
    # POST_BUILD RTL generation cannot remain stale.
    set_property(TARGET ${target} APPEND PROPERTY
        LINK_DEPENDS "${CPPHDL_EXECUTABLE}")
endfunction()

# The selected compiler already knows its implicit system include paths.
set(CPPHDL_TOOLCHAIN_ARGS "")

include(CTest)
add_subdirectory(rtl/network)
add_subdirectory(rtl/processing)
add_subdirectory(rtl/system)
add_subdirectory(test)
