cmake_minimum_required(VERSION 3.20)

# Bootstrap CppHDL before project() so a fresh SmartNIC checkout can select the
# compiler from the exported CppHDL Conda environment.  The converter itself is
# built once, below, as part of the SmartNIC build graph.
set(CPPHDL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/cpphdl")
set(CPPHDL_GIT_REPOSITORY "https://github.com/mirekez/cpphdl.git" CACHE STRING
    "CppHDL Git repository")
set(CPPHDL_GIT_TAG "main" CACHE STRING "CppHDL Git branch or tag")
option(CPPHDL_AUTO_PREPARE
    "Clone CppHDL and create its Conda environment when missing" ON)

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
    set(CPPHDL_CLANG_TOOLING_HEADER
        "${CPPHDL_CONDA_PREFIX}/include/clang/Tooling/Tooling.h")

    if(NOT EXISTS "${CPPHDL_CONDA_CXX}"
            OR NOT EXISTS "${CPPHDL_CONDA_CMAKE}"
            OR NOT EXISTS "${CPPHDL_CLANG_TOOLING_HEADER}")
        find_program(CPPHDL_CONDA_EXECUTABLE NAMES conda REQUIRED
            DOC "Conda executable used to prepare CppHDL")
        if(EXISTS "${CPPHDL_CONDA_PREFIX}/conda-meta")
            cpphdl_run_preparation_step("updating its Conda environment"
                "${CPPHDL_CONDA_EXECUTABLE}" env update
                --prefix "${CPPHDL_CONDA_PREFIX}"
                --file "${CPPHDL_ROOT}/requirements.yaml")
        else()
            cpphdl_run_preparation_step("creating its Conda environment"
                "${CPPHDL_CONDA_EXECUTABLE}" env create --yes
                --prefix "${CPPHDL_CONDA_PREFIX}"
                --file "${CPPHDL_ROOT}/requirements.yaml")
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

# CppHDL is a subdirectory here, so its own CMAKE_SOURCE_DIR is SmartNIC rather
# than cpphdl.  Pass the prepared prefix explicitly for LLVM/Clang discovery.
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

# CppHDL is kept as the project subfolder/symlink and provides both the headers
# and the C++-to-SystemVerilog converter.  SmartNIC tests stay independent of
# the much larger CppHDL example and CPU test suites.
set(CPPHDL_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(CPPHDL_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(CPPHDL_BUILD_TRIBE OFF CACHE BOOL "" FORCE)
set(CPPHDL_BUILD_HDLCPP OFF CACHE BOOL "" FORCE)
add_subdirectory("${CPPHDL_ROOT}" "${CMAKE_BINARY_DIR}/cpphdl" EXCLUDE_FROM_ALL)

include(CTest)
add_subdirectory(rtl/network)
