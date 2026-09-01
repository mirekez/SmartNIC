#pragma once

// Small asynchronous-read, synchronous-write storage leaf. Native and
// Verilator tests use this CppHDL implementation; the FPGA preparation flow
// substitutes only the equivalent canonical Xilinx LUTRAM implementation.

#include <cpphdl.h>

using namespace cpphdl;

template<size_t WIDTH = 32, size_t DEPTH = 64>
class [[clang::annotate(
    "CPPHDL_REPLACEMENT_FILE=AsyncReadRamPrimitive.sv;")]]
AsyncReadRam : public Module
{
public:
    static_assert(DEPTH >= 2 && (DEPTH & (DEPTH - 1)) == 0,
        "AsyncReadRam depth must be a power of two");

    _PORT(u<clog2(DEPTH)>) write_addr_in;
    _PORT(bool) write_in;
    _PORT(logic<WIDTH>) write_data_in;
    _PORT(u<clog2(DEPTH)>) read_addr_in;
    _PORT(logic<WIDTH>) read_data_out;

private:
    memory<logic<WIDTH>, 1, DEPTH> buffer;
    logic<WIDTH> read_data_comb;

    logic<WIDTH>& read_data_comb_func()
    {
        read_data_comb = buffer[(uint32_t)read_addr_in()];
        return read_data_comb;
    }

public:
#ifndef SYNTHESIS
    logic<WIDTH> debug_read(uint32_t address)
    {
        return buffer[address & (DEPTH - 1)];
    }
#endif

    void _assign()
    {
        read_data_out = _ASSIGN_COMB(read_data_comb_func());
    }

    void _work(bool reset)
    {
        if (!reset && write_in())
            buffer[(uint32_t)write_addr_in()] = write_data_in();
    }

    void _work_l2_clock(bool) {}

    void _strobe()
    {
        buffer.apply();
    }

    void _strobe_l2_clock() {}
};

template class AsyncReadRam<32, 64>;
