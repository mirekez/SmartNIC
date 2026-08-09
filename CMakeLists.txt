cmake_minimum_required(VERSION 3.20)
project(smartnic LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# CppHDL is kept as the project subfolder/symlink and provides both the headers
# and the C++-to-SystemVerilog converter.  SmartNIC tests stay independent of
# the much larger CppHDL example and CPU test suites.
set(CPPHDL_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(CPPHDL_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(CPPHDL_BUILD_TRIBE OFF CACHE BOOL "" FORCE)
set(CPPHDL_BUILD_HDLCPP OFF CACHE BOOL "" FORCE)
add_subdirectory(cpphdl "${CMAKE_BINARY_DIR}/cpphdl" EXCLUDE_FROM_ALL)

include(CTest)
add_subdirectory(rtl/network)
