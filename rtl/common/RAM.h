#pragma once

// Local copy of cpphdl/tribe_cpu/common/RAM.h.  Network-level memories use
// this common copy so the RTL does not depend on a CPU implementation path.

#include <cpphdl.h>
#include "ClockDomains.h"

using namespace cpphdl;

template<size_t WIDTH, size_t DEPTH>
class SmartNicRAM : public Module
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
    memory<u8, (WIDTH + 7) / 8, DEPTH> buffer;

public:
    void _work(bool reset)
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
