#pragma once

// Test-only Avalon host endpoint. The driver port is one Avalon master for
// System register/ring access. The DMA port is one Avalon slave backed by host
// memory and is addressed by System::MasterDMA.

#include "../Config.h"
#include "../rtl/common/Avalon.h"

using namespace cpphdl;

template<size_t MEMORY_BYTES = 4 * 1024 * 1024>
class AvalonHost : public Module
{
public:
    static constexpr size_t DATA_WIDTH = HOST_DATA_WIDTH;
    static constexpr size_t DATA_BYTES = DATA_WIDTH / 8;
    static constexpr size_t WORDS = MEMORY_BYTES / DATA_BYTES;
    static constexpr size_t WORD_BITS = clog2(WORDS);

    static_assert(MEMORY_BYTES % DATA_BYTES == 0);
    static_assert((WORDS & (WORDS - 1)) == 0);

    AvalonIf<32, DATA_WIDTH> control_out;
    AvalonIf<HOST_ADDR_WIDTH, DATA_WIDTH> dma;

    _PORT(bool) driver_read_in;
    _PORT(bool) driver_write_in;
    _PORT(u32) driver_address_in;
    _PORT(logic<DATA_WIDTH>) driver_writedata_in;
    _PORT(logic<DATA_BYTES>) driver_byteenable_in;
    _PORT(bool) driver_waitrequest_out;
    _PORT(logic<DATA_WIDTH>) driver_readdata_out;
    _PORT(bool) driver_readdatavalid_out;
    _PORT(bool) protocol_error_out;

    memory<u8, DATA_BYTES, WORDS> memory;

private:
    reg<logic<DATA_WIDTH>> dma_read_data_reg;
    reg<u1> dma_read_valid_reg;
    reg<u1> protocol_error_reg;

    bool dma_address_valid()
    {
        return (uint64_t)dma.address_in() < MEMORY_BYTES;
    }

public:
    void _assign()
    {
        control_out.address_in = driver_address_in;
        control_out.read_in = driver_read_in;
        control_out.write_in = driver_write_in;
        control_out.writedata_in = driver_writedata_in;
        control_out.byteenable_in = driver_byteenable_in;
        driver_waitrequest_out = control_out.waitrequest_out;
        driver_readdata_out = control_out.readdata_out;
        driver_readdatavalid_out = control_out.readdatavalid_out;

        dma.waitrequest_out = _ASSIGN(false);
        dma.readdata_out = _ASSIGN_REG(dma_read_data_reg);
        dma.readdatavalid_out = _ASSIGN_REG(dma_read_valid_reg);
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
    }

    void _work_system_clock(bool reset)
    {
        uint32_t word;
        uint32_t byte;
        logic<DATA_WIDTH> old_word;
        logic<DATA_WIDTH> new_word;

        dma_read_valid_reg.clr();
        if ((dma.read_in() || dma.write_in()) && !dma_address_valid()) {
            protocol_error_reg._next = true;
        }
        if (dma.write_in() && dma_address_valid()) {
            word = (uint64_t)dma.address_in() / DATA_BYTES;
            old_word = memory[word];
            new_word = old_word;
            for (byte = 0; byte < DATA_BYTES; ++byte) {
                if (dma.byteenable_in()[byte]) {
                    new_word.bits(byte * 8 + 7, byte * 8) =
                        dma.writedata_in().bits(byte * 8 + 7, byte * 8);
                }
            }
            memory[word] = new_word;
        }
        if (dma.read_in() && dma_address_valid()) {
            word = (uint64_t)dma.address_in() / DATA_BYTES;
            dma_read_data_reg._next = memory[word];
            dma_read_valid_reg._next = true;
        }
        if (reset) {
            dma_read_data_reg.clr();
            dma_read_valid_reg.clr();
            protocol_error_reg.clr();
        }
    }

    void _strobe_system_clock()
    {
        memory.apply();
        dma_read_data_reg.strobe();
        dma_read_valid_reg.strobe();
        protocol_error_reg.strobe();
    }

#ifndef SYNTHESIS
    uint8_t read_byte(uint64_t address) const
    {
        if (address >= MEMORY_BYTES) return 0;
        return (uint8_t)memory.data[address / DATA_BYTES][address % DATA_BYTES];
    }
#endif
};
