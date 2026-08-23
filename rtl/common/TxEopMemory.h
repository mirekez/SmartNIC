#pragma once

// One-bit, two-read-port packet-boundary metadata store for TxFifo.  The C++
// implementation is used by native tests; FPGA conversion substitutes only
// this storage leaf with the canonical distributed-RAM shape.

#include <cpphdl.h>
#include "ClockDomains.h"

using namespace cpphdl;

template<size_t DEPTH = 2048>
#ifdef SMARTNIC_TWO_CLOCKS
class [[clang::annotate("CPPHDL_REPLACEMENT_FILE=TxEopMemoryPrimitive.sv;")]]
TxEopMemory : public Module
#else
class TxEopMemory : public Module
#endif
{
public:
    _PORT(u<clog2(DEPTH)>) write_addr_in;
    _PORT(bool) write_in;
    _PORT(bool) write_data_in;
    _PORT(u<clog2(DEPTH)>) read_addr0_in;
    _PORT(u<clog2(DEPTH)>) read_addr1_in;
    _PORT(bool) read_data0_out;
    _PORT(bool) read_data1_out;

private:
    memory<logic<1>, 1, DEPTH> buffer;

    bool read_data0_comb;
    bool& read_data0_comb_func()
    {
        read_data0_comb = buffer[read_addr0_in()][0];
        return read_data0_comb;
    }

    bool read_data1_comb;
    bool& read_data1_comb_func()
    {
        read_data1_comb = buffer[read_addr1_in()][0];
        return read_data1_comb;
    }

public:
    void _assign()
    {
        read_data0_out = _ASSIGN_COMB(read_data0_comb_func());
        read_data1_out = _ASSIGN_COMB(read_data1_comb_func());
    }

    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
    {
        if (!reset && write_in()) {
            buffer[write_addr_in()] = write_data_in();
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        buffer.apply();
    }
#endif

    void _strobe()
    {
        buffer.apply();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class TxEopMemory<2048>;
