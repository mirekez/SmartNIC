#pragma once

// Single-clock packet-preserving byte-width gearbox.  It deliberately has no
// asynchronous FIFO: source and destination are both clocked at 156.25 MHz.

#include <cpphdl.h>

using namespace cpphdl;

template<size_t SRC_WIDTH, size_t DST_WIDTH>
class PacketStream : public Module
{
public:
    static constexpr size_t SRC_BYTES = SRC_WIDTH / 8;
    static constexpr size_t DST_BYTES = DST_WIDTH / 8;
    static constexpr size_t BUFFER_BYTES = 64;
    static constexpr size_t BUFFER_BITS = BUFFER_BYTES * 8;

    static_assert(SRC_WIDTH % 8 == 0 && DST_WIDTH % 8 == 0,
        "PacketStream widths must contain whole bytes");
    static_assert(SRC_BYTES <= BUFFER_BYTES && DST_BYTES <= BUFFER_BYTES,
        "PacketStream endpoint width exceeds its buffer");

    _PORT(bool) valid_in;
    _PORT(logic<SRC_WIDTH>) data_in;
    _PORT(logic<SRC_BYTES>) keep_in;
    _PORT(bool) sop_in;
    _PORT(bool) eop_in;
    _PORT(bool) ready_out;

    _PORT(bool) valid_out;
    _PORT(logic<DST_WIDTH>) data_out;
    _PORT(logic<DST_BYTES>) keep_out;
    _PORT(bool) sop_out;
    _PORT(bool) eop_out;
    _PORT(bool) ready_in;

private:
    reg<logic<BUFFER_BITS>> data_reg;
    reg<u<7>> count_reg;
    reg<u1> sop_reg;
    reg<u1> eop_reg;

    bool output_valid_value()
    {
        return (uint32_t)count_reg >= DST_BYTES
            || ((bool)eop_reg && (uint32_t)count_reg != 0);
    }

    bool& ready_comb_func()
    {
        uint32_t count = (uint32_t)count_reg;
        bool eop = eop_reg;
        if (output_valid_value() && ready_in()) {
            count -= count > DST_BYTES ? DST_BYTES : count;
            if (count == 0) eop = false;
        }
        ready_comb = !eop && count + SRC_BYTES <= BUFFER_BYTES;
        return ready_comb;
    }

    bool ready_comb;
    bool valid_comb;
    bool eop_comb;
    logic<DST_WIDTH> data_comb;
    logic<DST_BYTES> keep_comb;

    logic<DST_WIDTH>& data_comb_func()
    {
        uint32_t byte;
        data_comb = 0;
        for (byte = 0; byte < DST_BYTES; ++byte) {
            if (byte < (uint32_t)count_reg) {
                data_comb.bits(byte * 8 + 7, byte * 8) =
                    data_reg.bits(byte * 8 + 7, byte * 8);
            }
        }
        return data_comb;
    }

    logic<DST_BYTES>& keep_comb_func()
    {
        uint32_t byte;
        keep_comb = 0;
        for (byte = 0; byte < DST_BYTES; ++byte) {
            keep_comb[byte] = byte < (uint32_t)count_reg;
        }
        return keep_comb;
    }

    bool& valid_comb_func()
    {
        valid_comb = output_valid_value();
        return valid_comb;
    }

    bool& eop_comb_func()
    {
        eop_comb = (bool)eop_reg && (uint32_t)count_reg <= DST_BYTES;
        return eop_comb;
    }

public:
    void _assign()
    {
        ready_out = _ASSIGN_COMB(ready_comb_func());
        valid_out = _ASSIGN_COMB(valid_comb_func());
        data_out = _ASSIGN_COMB(data_comb_func());
        keep_out = _ASSIGN_COMB(keep_comb_func());
        sop_out = _ASSIGN_REG(sop_reg);
        eop_out = _ASSIGN_COMB(eop_comb_func());
    }

    void _work(bool reset)
    {
        logic<BUFFER_BITS> data = data_reg;
        uint32_t count = (uint32_t)count_reg;
        uint32_t remove;
        uint32_t byte;
        bool sop = sop_reg;
        bool eop = eop_reg;

        if (output_valid_value() && ready_in()) {
            remove = count > DST_BYTES ? DST_BYTES : count;
            for (byte = 0; byte < BUFFER_BYTES; ++byte) {
                if (byte + remove < count) {
                    data.bits(byte * 8 + 7, byte * 8) =
                        data.bits((byte + remove) * 8 + 7,
                            (byte + remove) * 8);
                }
                else data.bits(byte * 8 + 7, byte * 8) = 0;
            }
            count -= remove;
            sop = false;
            if (count == 0) eop = false;
        }

        if (valid_in() && ready_comb_func()) {
            for (byte = 0; byte < SRC_BYTES; ++byte) {
                if ((bool)keep_in()[byte]) {
                    data.bits(count * 8 + 7, count * 8) =
                        data_in().bits(byte * 8 + 7, byte * 8);
                    ++count;
                }
            }
            if (sop_in()) sop = true;
            if (eop_in()) eop = true;
        }

        data_reg._next = data;
        count_reg._next = count;
        sop_reg._next = sop;
        eop_reg._next = eop;
        if (reset) {
            data_reg.clr();
            count_reg.clr();
            sop_reg.clr();
            eop_reg.clr();
        }
    }

    void _strobe()
    {
        data_reg.strobe();
        count_reg.strobe();
        sop_reg.strobe();
        eop_reg.strobe();
    }
};

template class PacketStream<64, 256>;
template class PacketStream<256, 64>;
