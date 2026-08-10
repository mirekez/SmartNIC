#pragma once

// Module-only copy of the memory used by cpphdl/examples/basic/Fifo.cpp.

#include <cpphdl.h>

using namespace cpphdl;

template<size_t MEM_WIDTH_BYTES, size_t MEM_DEPTH, bool SHOWAHEAD = true>
class Memory : public Module
{
public:
    _PORT(u<clog2(MEM_DEPTH)>) write_addr_in;
    _PORT(bool) write_in;
    _PORT(logic<MEM_WIDTH_BYTES * 8>) write_data_in;
    _PORT(logic<MEM_WIDTH_BYTES>) write_mask_in;
    _PORT(u<clog2(MEM_DEPTH)>) read_addr_in;
    _PORT(bool) read_in;
    _PORT(logic<MEM_WIDTH_BYTES * 8>) read_data_out;

private:
    reg<logic<MEM_WIDTH_BYTES * 8>> data_out_reg;
    memory<u8, MEM_WIDTH_BYTES, MEM_DEPTH> buffer;
    logic<MEM_WIDTH_BYTES * 8> data_out_comb;

    logic<MEM_WIDTH_BYTES * 8>& data_out_comb_func()
    {
        if (SHOWAHEAD) {
            data_out_comb = buffer[read_addr_in()];
        }
        else {
            data_out_comb = data_out_reg;
        }
        return data_out_comb;
    }

public:
    void _assign()
    {
        read_data_out = _ASSIGN_COMB(data_out_comb_func());
    }

    void _work(bool reset)
    {
        size_t byte;
        logic<MEM_WIDTH_BYTES * 8> mask;
        if (reset) {
            data_out_reg.clr();
            return;
        }
        if (write_in()) {
            mask = 0;
            for (byte = 0; byte < MEM_WIDTH_BYTES; ++byte) {
                mask.bits(byte * 8 + 7, byte * 8) =
                    (bool)write_mask_in()[byte] ? 0xff : 0;
            }
            buffer[write_addr_in()] = (buffer[write_addr_in()] & ~mask)
                | (write_data_in() & mask);
        }
        if (!SHOWAHEAD && read_in()) {
            data_out_reg._next = buffer[read_addr_in()];
        }
    }

    void _strobe()
    {
        buffer.apply();
        data_out_reg.strobe();
    }
};
