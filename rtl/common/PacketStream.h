#pragma once

// Fixed-ratio, single-clock packet gearbox. SmartNIC only uses 64<->256;
// expressing those four fixed lanes directly avoids synthesizing a general
// byte-compacting barrel shifter.

#include <cpphdl.h>

using namespace cpphdl;

template<size_t SRC_WIDTH, size_t DST_WIDTH>
class PacketStream : public Module
{
public:
    static constexpr size_t SRC_BYTES = SRC_WIDTH / 8;
    static constexpr size_t DST_BYTES = DST_WIDTH / 8;
    static constexpr size_t WIDE_WIDTH = 256;
    static constexpr size_t WIDE_BYTES = WIDE_WIDTH / 8;
    static constexpr size_t LANE_WIDTH = 64;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t LANES = WIDE_WIDTH / LANE_WIDTH;

    static_assert((SRC_WIDTH == LANE_WIDTH && DST_WIDTH == WIDE_WIDTH)
            || (SRC_WIDTH == WIDE_WIDTH && DST_WIDTH == LANE_WIDTH),
        "PacketStream supports the SmartNIC 64<->256 gearboxes");

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
    reg<logic<WIDE_WIDTH>> data_reg;
    reg<logic<WIDE_BYTES>> keep_reg;
    reg<u<2>> lane_reg;
    reg<u<2>> last_lane_reg;
    reg<u1> valid_reg;
    reg<u1> sop_reg;
    reg<u1> eop_reg;

    bool ready_comb;
    bool valid_comb;
    bool sop_comb;
    bool eop_comb;
    logic<DST_WIDTH> data_comb;
    logic<DST_BYTES> keep_comb;

    bool last_output_lane()
    {
        if (SRC_WIDTH < DST_WIDTH) return true;
        return (uint32_t)lane_reg == (uint32_t)last_lane_reg;
    }

    bool& ready_comb_func()
    {
        ready_comb = !(bool)valid_reg
            || (ready_in() && last_output_lane());
        return ready_comb;
    }

    bool& valid_comb_func()
    {
        valid_comb = valid_reg;
        return valid_comb;
    }

    logic<DST_WIDTH>& data_comb_func()
    {
        data_comb = 0;
        if (SRC_WIDTH < DST_WIDTH) {
            data_comb = data_reg;
        }
        else {
            if ((uint32_t)lane_reg == 0)
                data_comb = data_reg.bits(63, 0);
            else if ((uint32_t)lane_reg == 1)
                data_comb = data_reg.bits(127, 64);
            else if ((uint32_t)lane_reg == 2)
                data_comb = data_reg.bits(191, 128);
            else
                data_comb = data_reg.bits(255, 192);
        }
        return data_comb;
    }

    logic<DST_BYTES>& keep_comb_func()
    {
        keep_comb = 0;
        if (SRC_WIDTH < DST_WIDTH) {
            keep_comb = keep_reg;
        }
        else {
            if ((uint32_t)lane_reg == 0)
                keep_comb = keep_reg.bits(7, 0);
            else if ((uint32_t)lane_reg == 1)
                keep_comb = keep_reg.bits(15, 8);
            else if ((uint32_t)lane_reg == 2)
                keep_comb = keep_reg.bits(23, 16);
            else
                keep_comb = keep_reg.bits(31, 24);
        }
        return keep_comb;
    }

    bool& sop_comb_func()
    {
        if (SRC_WIDTH < DST_WIDTH) sop_comb = sop_reg;
        else sop_comb = sop_reg && (uint32_t)lane_reg == 0;
        return sop_comb;
    }

    bool& eop_comb_func()
    {
        if (SRC_WIDTH < DST_WIDTH) eop_comb = eop_reg;
        else eop_comb = eop_reg && last_output_lane();
        return eop_comb;
    }

public:
    void _assign()
    {
        ready_out = _ASSIGN_COMB(ready_comb_func());
        valid_out = _ASSIGN_COMB(valid_comb_func());
        data_out = _ASSIGN_COMB(data_comb_func());
        keep_out = _ASSIGN_COMB(keep_comb_func());
        sop_out = _ASSIGN_COMB(sop_comb_func());
        eop_out = _ASSIGN_COMB(eop_comb_func());
    }

    void _work(bool reset)
    {
        bool output_fire;
        bool input_fire;
        bool word_complete;
        uint32_t lane;
        uint32_t last_lane;
        logic<WIDE_WIDTH> data;
        logic<WIDE_BYTES> keep;

        output_fire = (bool)valid_reg && ready_in();
        input_fire = valid_in() && ready_comb_func();

        if (SRC_WIDTH < DST_WIDTH) {
            lane = output_fire ? 0 : (uint32_t)lane_reg;
            data = output_fire ? (logic<WIDE_WIDTH>)0 : data_reg;
            keep = output_fire ? (logic<WIDE_BYTES>)0 : keep_reg;

            if (output_fire) {
                valid_reg._next = false;
                // SOP/EOP describe the buffered wide word, not the packet as
                // a whole.  Clear them when that word is consumed so a
                // following word cannot inherit its framing markers.
                sop_reg._next = false;
                eop_reg._next = false;
            }
            if (input_fire) {
                if (lane == 0) {
                    data.bits(63, 0) = data_in();
                    keep.bits(7, 0) = keep_in();
                }
                else if (lane == 1) {
                    data.bits(127, 64) = data_in();
                    keep.bits(15, 8) = keep_in();
                }
                else if (lane == 2) {
                    data.bits(191, 128) = data_in();
                    keep.bits(23, 16) = keep_in();
                }
                else {
                    data.bits(255, 192) = data_in();
                    keep.bits(31, 24) = keep_in();
                }
                if (sop_in()) sop_reg._next = true;
                word_complete = eop_in() || lane == LANES - 1;
                if (word_complete) {
                    valid_reg._next = true;
                    eop_reg._next = eop_in();
                    lane_reg._next = 0;
                }
                else lane_reg._next = lane + 1;
                data_reg._next = data;
                keep_reg._next = keep;
            }
        }
        else {
            if (output_fire) {
                if (last_output_lane()) valid_reg._next = false;
                else lane_reg._next = lane_reg + 1;
            }
            if (input_fire) {
                last_lane = 0;
                if ((uint64_t)keep_in().bits(31, 24) != 0) last_lane = 3;
                else if ((uint64_t)keep_in().bits(23, 16) != 0) last_lane = 2;
                else if ((uint64_t)keep_in().bits(15, 8) != 0) last_lane = 1;
                data_reg._next = data_in();
                keep_reg._next = keep_in();
                lane_reg._next = 0;
                last_lane_reg._next = last_lane;
                valid_reg._next = (uint64_t)keep_in() != 0;
                sop_reg._next = sop_in();
                eop_reg._next = eop_in();
            }
        }

        if (reset) {
            data_reg.clr();
            keep_reg.clr();
            lane_reg.clr();
            last_lane_reg.clr();
            valid_reg.clr();
            sop_reg.clr();
            eop_reg.clr();
        }
    }

    void _strobe()
    {
        data_reg.strobe();
        keep_reg.strobe();
        lane_reg.strobe();
        last_lane_reg.strobe();
        valid_reg.strobe();
        sop_reg.strobe();
        eop_reg.strobe();
    }
};

template class PacketStream<64, 256>;
template class PacketStream<256, 64>;
