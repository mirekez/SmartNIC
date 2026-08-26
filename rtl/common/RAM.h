#pragma once

// Local copy of cpphdl/tribe_cpu/common/RAM.h.  Network-level memories use
// this common copy so the RTL does not depend on a CPU implementation path.

#include <cpphdl.h>
#include "ClockDomains.h"

using namespace cpphdl;

template<size_t WIDTH, size_t DEPTH>
#ifdef SMARTNIC_TWO_CLOCKS
class [[clang::annotate("CPPHDL_REPLACEMENT_FILE=SmartNicRAMPrimitive.sv;")]]
SmartNicRAM : public Module
#else
class SmartNicRAM : public Module
#endif
{
public:
    _PORT(u<clog2(DEPTH)>) write_addr_in;
    _PORT(u<clog2(DEPTH)>) read_addr_in;
    _PORT(logic<WIDTH>) data_in;
    _PORT(bool) wr_in;
    _PORT(bool) rd_in;
    _PORT(logic<WIDTH>) q_out = _ASSIGN_REG(q_out_reg);
    int id_in;

private:
    reg<logic<WIDTH>> q_out_reg;
    // This RAM is always read and written as a complete word. Independent
    // addresses describe a simple dual-port BRAM, while the singleton memory
    // element emits the two-dimensional packed-word array Vivado expects.
    // (* ram_style = "block" *)
    memory<logic<WIDTH>, 1, DEPTH> buffer;

public:
    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
    {
        if (reset) {
            q_out_reg.clr();
            return;
        }
        if (wr_in()) {
            buffer[write_addr_in()] = data_in();
        }
        if (rd_in()) {
            q_out_reg._next = buffer[read_addr_in()];
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        buffer.apply();
        q_out_reg.strobe();
    }
#endif

    void _strobe()
    {
        buffer.apply();
        q_out_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class SmartNicRAM<160, 4096>;
template class SmartNicRAM<320, 4096>;
