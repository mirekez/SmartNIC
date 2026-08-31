#pragma once

#include <cpphdl.h>

using namespace cpphdl;

// Small storage leaf for UARTProbe. Native simulation uses this C++ memory;
// the FPGA build substitutes only this leaf with UARTProbeMemoryPrimitive.sv
// so Vivado receives a canonical synchronous block-RAM template.
template<size_t WIDTH = 128, size_t DEPTH = 1'024>
class UARTProbeMemory : public Module
{
public:
    _PORT(bool) write_in;
    _PORT(u<clog2(DEPTH)>) write_addr_in;
    _PORT(logic<WIDTH>) write_data_in;
    _PORT(bool) read_in;
    _PORT(u<clog2(DEPTH)>) read_addr_in;
    _PORT(logic<WIDTH>) read_data_out;

private:
    memory<logic<WIDTH>, 1, DEPTH> buffer;
    reg<logic<WIDTH>> read_data_reg;

public:
    void _assign()
    {
        read_data_out = _ASSIGN_REG(read_data_reg);
    }

    void _work(bool reset)
    {
        if (reset) {
            read_data_reg.clr();
            return;
        }
        if (write_in()) {
            buffer[write_addr_in()] = write_data_in();
        }
        if (read_in()) {
            read_data_reg._next = buffer[read_addr_in()];
        }
    }

    void _strobe()
    {
        buffer.apply();
        read_data_reg.strobe();
    }
};

template class UARTProbeMemory<>;
