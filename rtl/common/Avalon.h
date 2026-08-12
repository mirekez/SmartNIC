#pragma once

// Minimal Avalon-MM interface used at the SmartNIC host boundary. Directions
// are declared once from the input/target side. A containing interface whose
// name ends in `_out` reverses every leaf when CppHDL emits module ports.

#include <cpphdl.h>

using namespace cpphdl;

template<size_t ADDR_WIDTH, size_t DATA_WIDTH>
struct AvalonIf : Interface
{
    _PORT(u<ADDR_WIDTH>) address_in;
    _PORT(bool) read_in;
    _PORT(bool) write_in;
    _PORT(logic<DATA_WIDTH>) writedata_in;
    _PORT(logic<DATA_WIDTH / 8>) byteenable_in;
    _PORT(bool) waitrequest_out;
    _PORT(logic<DATA_WIDTH>) readdata_out;
    _PORT(bool) readdatavalid_out;
};
