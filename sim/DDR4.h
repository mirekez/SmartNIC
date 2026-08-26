#pragma once

// CppHDL simulation model for a narrow DDR4 device. N is capacity in bytes
// and M is the native data width. The model accepts one request per clock and
// returns reads one clock later; it is intentionally separate from the
// synthesizable AXI4 adapter/controller logic.

#include <cpphdl.h>

using namespace cpphdl;

template<size_t N = 1024 * 1024, size_t M = 32, size_t ADDR_WIDTH = 31>
class DDR4 : public Module
{
public:
    static constexpr size_t BYTES = M / 8;
    static constexpr size_t WORDS = N / BYTES;
    static_assert(M % 8 == 0);
    static_assert(N % BYTES == 0);

    _PORT(bool) valid_in;
    _PORT(bool) write_in;
    _PORT(u<ADDR_WIDTH>) address_in;
    _PORT(logic<M>) writedata_in;
    _PORT(logic<BYTES>) byteenable_in;
    _PORT(bool) ready_out;
    _PORT(bool) readdatavalid_out;
    _PORT(logic<M>) readdata_out;

    memory<u8, BYTES, WORDS> storage;

private:
    reg<u1> read_valid_reg;
    reg<logic<M>> read_data_reg;

public:
    void _assign()
    {
        ready_out = _ASSIGN(true);
        readdatavalid_out = _ASSIGN_REG(read_valid_reg);
        readdata_out = _ASSIGN_REG(read_data_reg);
    }

    void _work(bool reset)
    {
        uint32_t byte;
        uint32_t word;
        logic<M> data;
        read_valid_reg._next = false;
        if (valid_in() && ready_out()) {
            word = (uint32_t)address_in() / BYTES;
            data = 0;
            if ((uint32_t)address_in() < N) data = storage[word];
            if (write_in()) {
                for (byte = 0; byte < BYTES; ++byte) {
                    if (byteenable_in()[byte]) {
                        data[byte * 8 + 7] = writedata_in()[byte * 8 + 7];
                        data[byte * 8 + 6] = writedata_in()[byte * 8 + 6];
                        data[byte * 8 + 5] = writedata_in()[byte * 8 + 5];
                        data[byte * 8 + 4] = writedata_in()[byte * 8 + 4];
                        data[byte * 8 + 3] = writedata_in()[byte * 8 + 3];
                        data[byte * 8 + 2] = writedata_in()[byte * 8 + 2];
                        data[byte * 8 + 1] = writedata_in()[byte * 8 + 1];
                        data[byte * 8] = writedata_in()[byte * 8];
                    }
                }
                if ((uint32_t)address_in() < N) storage[word] = data;
            }
            else {
                read_data_reg._next = data;
                read_valid_reg._next = true;
            }
        }
        if (reset) {
            read_valid_reg.clr();
            read_data_reg.clr();
        }
    }

    void _strobe()
    {
        storage.apply();
        read_valid_reg.strobe();
        read_data_reg.strobe();
    }

#ifndef SYNTHESIS
    void load_byte(uint32_t address, uint8_t value)
    {
        if (address >= N) return;
        storage.data[address / BYTES][address % BYTES] = value;
    }

    uint8_t read_byte(uint32_t address) const
    {
        if (address >= N) return 0;
        return (uint8_t)storage.data[address / BYTES][address % BYTES];
    }
#endif
};

template class DDR4<1024 * 1024, 32, 31>;
