#pragma once

// Module-only copy of the memory used by cpphdl/examples/basic/Fifo.cpp.

#include <cpphdl.h>
#include "ClockDomains.h"

using namespace cpphdl;

template<size_t MEM_WIDTH_BYTES, size_t MEM_DEPTH, bool SHOWAHEAD = true,
    bool FULL_WORD_WRITE = false>
#ifdef SMARTNIC_SYSTEM_MEMORY
class SmartNicMemory : public Module
#elif defined(SMARTNIC_TWO_CLOCKS)
class [[clang::annotate("CPPHDL_REPLACEMENT_FILE=SmartNicMemoryPrimitive.sv;")]]
SmartNicMemory : public Module
#else
class SmartNicMemory : public Module
#endif
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
    // Byte enables are expanded into write_mask_comb below, so storage can be
    // emitted as one packed word per address.  This avoids Vivado expanding a
    // byte/word 3-D array into individual registers during elaboration.
    memory<logic<MEM_WIDTH_BYTES * 8>, 1, MEM_DEPTH> buffer;
    logic<MEM_WIDTH_BYTES * 8> data_out_comb;
    // Keep this temporary at module scope.  CppHDL preserves parameterized
    // member widths in generated SV; a local logic<> was specialized to one
    // concrete instantiation when several Memory widths shared the module.
    logic<MEM_WIDTH_BYTES * 8> write_mask_comb;

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

    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
    {
        size_t byte;
        if (reset) {
            data_out_reg.clr();
            return;
        }
        if (write_in()) {
            if (FULL_WORD_WRITE) {
                buffer[write_addr_in()] = write_data_in();
            }
            else {
                write_mask_comb = 0;
                for (byte = 0; byte < MEM_WIDTH_BYTES; ++byte) {
                    write_mask_comb.bits(byte * 8 + 7, byte * 8) =
                        (bool)write_mask_in()[byte] ? 0xff : 0;
                }
                buffer[write_addr_in()] =
                    (buffer[write_addr_in()] & ~write_mask_comb)
                    | (write_data_in() & write_mask_comb);
            }
        }
        if (!SHOWAHEAD && read_in()) {
            data_out_reg._next = buffer[read_addr_in()];
        }
    }

#if defined(SMARTNIC_TWO_CLOCKS) && !defined(SMARTNIC_SYSTEM_MEMORY)
    void _strobe_net_clk()
    {
        buffer.apply();
        data_out_reg.strobe();
    }
#endif

    void _strobe()
    {
        buffer.apply();
        data_out_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class SmartNicMemory<160, 64, true, false>;
