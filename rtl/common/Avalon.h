#pragma once

// Minimal Avalon-MM interfaces used at the SmartNIC host boundary.  The
// master supports one outstanding read and one held write request; the slave
// exposes a conventional waitrequest/readdatavalid register interface.

#include <cpphdl.h>

using namespace cpphdl;

template<size_t ADDR_WIDTH, size_t DATA_WIDTH>
struct AvalonMasterIf : Interface
{
    _PORT(u<ADDR_WIDTH>) address_out;
    _PORT(bool) read_out;
    _PORT(bool) write_out;
    _PORT(logic<DATA_WIDTH>) writedata_out;
    _PORT(logic<DATA_WIDTH / 8>) byteenable_out;
    _PORT(bool) waitrequest_in;
    _PORT(logic<DATA_WIDTH>) readdata_in;
    _PORT(bool) readdatavalid_in;
};

template<size_t ADDR_WIDTH, size_t DATA_WIDTH>
struct AvalonSlaveIf : Interface
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
