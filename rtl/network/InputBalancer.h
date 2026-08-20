#pragma once

// Two independent 64-bit 10GbE receive channels. Each channel keeps its own
// packet state and elastic FIFO; bytes from different MACs are never combined
// into one logical packet stream.

#include <cpphdl.h>
#include <algorithm>
#include "../common/ClockDomains.h"
#include "../common/Fifo.cpp"

using namespace cpphdl;

extern long _system_clock;

#define INPUT_BALANCER_FOR_EACH_LANE(M) M(0) M(1)

template<size_t LANE_WIDTH = 64>
class InputBalancer : public Module
{
public:
    static constexpr size_t LANES = 2;
    static constexpr size_t FIFO_WORDS = 2048;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t INPUT_BITS = LANES * LANE_WIDTH;
    static constexpr size_t INPUT_BYTES = LANES * LANE_BYTES;
    static constexpr size_t ENTRY_BYTES =
        (LANE_WIDTH + 3 * LANE_BYTES) / 8;
    static constexpr size_t ENTRY_BITS = ENTRY_BYTES * 8;
    static constexpr size_t KEEP_OFFSET = LANE_WIDTH;
    static constexpr size_t SOP_OFFSET = KEEP_OFFSET + LANE_BYTES;
    static constexpr size_t EOP_OFFSET = SOP_OFFSET + LANE_BYTES;

    static_assert(LANE_WIDTH == 64,
        "InputBalancer supports 64-bit 10GbE MAC words");
    static_assert((FIFO_WORDS & (FIFO_WORDS - 1)) == 0,
        "FIFO_WORDS must be a power of two");

    _PORT(bool) valid_in;
    _PORT(logic<INPUT_BITS>) data_in;
    _PORT(logic<INPUT_BYTES>) keep_in;
    _PORT(logic<INPUT_BYTES>) sop_in;
    _PORT(logic<INPUT_BYTES>) eop_in;
    _PORT(bool) ready_out;

    _PORT(logic<INPUT_BITS>) data_out;
    _PORT(logic<INPUT_BYTES>) keep_out;
    _PORT(logic<INPUT_BYTES>) sop_out;
    _PORT(logic<INPUT_BYTES>) eop_out;
    _PORT(logic<LANES>) valid_out;
    _PORT(logic<LANES>) ready_in;
    _PORT(bool) protocol_error_out;

private:
    // OUTPUT_REG gives each FIFO a registered show-ahead word. The CppHDL
    // SmartNicMemory then has a synchronous read boundary suitable for BRAM.
    Fifo<ENTRY_BYTES, FIFO_WORDS, true, true> fifos[LANES];
    reg<u1> in_frame_reg[LANES];
    reg<u1> protocol_error_reg;

    bool lane_present(size_t lane)
    {
        return (uint64_t)keep_in().bits(
            lane * LANE_BYTES + LANE_BYTES - 1,
            lane * LANE_BYTES) != 0;
    }

    bool lane_pop(size_t lane)
    {
        return !fifos[lane].empty_out() && (bool)ready_in()[lane];
    }

    _LAZY_COMB(input_ready_comb, bool)
        size_t lane;
        input_ready_comb = true;
        if (!valid_in()) {
            return input_ready_comb;
        }
        for (lane = 0; lane < LANES; ++lane) {
            if (lane_present(lane) && fifos[lane].full_out()
                && !lane_pop(lane)) {
                input_ready_comb = false;
            }
        }
        return input_ready_comb;
    }

#define INPUT_BALANCER_DECLARE_ENTRY(number) \
    bool fifo_write_##number##_comb; \
    bool& fifo_write_##number##_comb_func() \
    { \
        fifo_write_##number##_comb = valid_in() \
            && input_ready_comb_func() && lane_present(number); \
        return fifo_write_##number##_comb; \
    } \
    bool fifo_read_##number##_comb; \
    bool& fifo_read_##number##_comb_func() \
    { \
        fifo_read_##number##_comb = lane_pop(number); \
        return fifo_read_##number##_comb; \
    } \
    logic<ENTRY_BITS> input_entry_##number##_comb; \
    logic<ENTRY_BITS>& input_entry_##number##_comb_func() \
    { \
        input_entry_##number##_comb = 0; \
        input_entry_##number##_comb.bits(LANE_WIDTH - 1, 0) = \
            data_in().bits(number * LANE_WIDTH + LANE_WIDTH - 1, \
                number * LANE_WIDTH); \
        input_entry_##number##_comb.bits( \
            KEEP_OFFSET + LANE_BYTES - 1, KEEP_OFFSET) = \
            keep_in().bits(number * LANE_BYTES + LANE_BYTES - 1, \
                number * LANE_BYTES); \
        input_entry_##number##_comb.bits( \
            SOP_OFFSET + LANE_BYTES - 1, SOP_OFFSET) = \
            sop_in().bits(number * LANE_BYTES + LANE_BYTES - 1, \
                number * LANE_BYTES); \
        input_entry_##number##_comb.bits( \
            EOP_OFFSET + LANE_BYTES - 1, EOP_OFFSET) = \
            eop_in().bits(number * LANE_BYTES + LANE_BYTES - 1, \
                number * LANE_BYTES); \
        return input_entry_##number##_comb; \
    }
    INPUT_BALANCER_FOR_EACH_LANE(INPUT_BALANCER_DECLARE_ENTRY)
#undef INPUT_BALANCER_DECLARE_ENTRY

    _LAZY_COMB(output_data_comb, logic<INPUT_BITS>)
        size_t lane;
        logic<ENTRY_BITS> entry;
        output_data_comb = 0;
        for (lane = 0; lane < LANES; ++lane) {
            entry = fifos[lane].read_data_out();
            output_data_comb.bits(lane * LANE_WIDTH + LANE_WIDTH - 1,
                lane * LANE_WIDTH) = entry.bits(LANE_WIDTH - 1, 0);
        }
        return output_data_comb;
    }

    _LAZY_COMB(output_keep_comb, logic<INPUT_BYTES>)
        size_t lane;
        logic<ENTRY_BITS> entry;
        output_keep_comb = 0;
        for (lane = 0; lane < LANES; ++lane) {
            entry = fifos[lane].read_data_out();
            output_keep_comb.bits(lane * LANE_BYTES + LANE_BYTES - 1,
                lane * LANE_BYTES) = entry.bits(
                    KEEP_OFFSET + LANE_BYTES - 1, KEEP_OFFSET);
        }
        return output_keep_comb;
    }

    _LAZY_COMB(output_sop_comb, logic<INPUT_BYTES>)
        size_t lane;
        logic<ENTRY_BITS> entry;
        output_sop_comb = 0;
        for (lane = 0; lane < LANES; ++lane) {
            entry = fifos[lane].read_data_out();
            output_sop_comb.bits(lane * LANE_BYTES + LANE_BYTES - 1,
                lane * LANE_BYTES) = entry.bits(
                    SOP_OFFSET + LANE_BYTES - 1, SOP_OFFSET);
        }
        return output_sop_comb;
    }

    _LAZY_COMB(output_eop_comb, logic<INPUT_BYTES>)
        size_t lane;
        logic<ENTRY_BITS> entry;
        output_eop_comb = 0;
        for (lane = 0; lane < LANES; ++lane) {
            entry = fifos[lane].read_data_out();
            output_eop_comb.bits(lane * LANE_BYTES + LANE_BYTES - 1,
                lane * LANE_BYTES) = entry.bits(
                    EOP_OFFSET + LANE_BYTES - 1, EOP_OFFSET);
        }
        return output_eop_comb;
    }

    _LAZY_COMB(output_valid_comb, logic<LANES>)
        size_t lane;
        output_valid_comb = 0;
        for (lane = 0; lane < LANES; ++lane) {
            output_valid_comb[lane] = !fifos[lane].empty_out();
        }
        return output_valid_comb;
    }

public:
#ifndef SYNTHESIS
    uint32_t debug_total_words() const
    {
        return fifos[0].debug_count() + fifos[1].debug_count();
    }

    uint32_t debug_max_words() const
    {
        return std::max(fifos[0].debug_count(), fifos[1].debug_count());
    }
#endif

    void _assign()
    {
#define INPUT_BALANCER_BIND_LANE(number) \
        fifos[number].write_in = \
            _ASSIGN_COMB(fifo_write_##number##_comb_func()); \
        fifos[number].write_data_in = \
            _ASSIGN_COMB(input_entry_##number##_comb_func()); \
        fifos[number].read_in = \
            _ASSIGN_COMB(fifo_read_##number##_comb_func()); \
        fifos[number].clear_in = _ASSIGN(false); \
        fifos[number].__inst_name = __inst_name + "/lane" \
            + std::to_string(number); \
        fifos[number]._assign();
        INPUT_BALANCER_FOR_EACH_LANE(INPUT_BALANCER_BIND_LANE)
#undef INPUT_BALANCER_BIND_LANE

        ready_out = _ASSIGN_COMB(input_ready_comb_func());
        data_out = _ASSIGN_COMB(output_data_comb_func());
        keep_out = _ASSIGN_COMB(output_keep_comb_func());
        sop_out = _ASSIGN_COMB(output_sop_comb_func());
        eop_out = _ASSIGN_COMB(output_eop_comb_func());
        valid_out = _ASSIGN_COMB(output_valid_comb_func());
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
    }

    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
    {
        size_t lane;
        size_t byte;
        bool seen_zero;
        bool sop_seen;
        bool eop_seen;
        bool last_valid;
        bool keep;
        bool sop;
        bool eop;

        for (lane = 0; lane < LANES; ++lane) {
            fifos[lane]._work(reset);
        }
        if (reset) {
            for (lane = 0; lane < LANES; ++lane) {
                in_frame_reg[lane]._next = 0;
            }
            protocol_error_reg._next = 0;
            return;
        }

        for (lane = 0; lane < LANES; ++lane) {
            if (valid_in() && input_ready_comb_func()
                && lane_present(lane)) {
                seen_zero = false;
                sop_seen = false;
                eop_seen = false;
                last_valid = false;
                for (byte = 0; byte < LANE_BYTES; ++byte) {
                    const size_t flat = lane * LANE_BYTES + byte;
                    keep = (bool)keep_in()[flat];
                    sop = (bool)sop_in()[flat];
                    eop = (bool)eop_in()[flat];
                    if (!keep) {
                        seen_zero = true;
                        if (sop || eop) protocol_error_reg._next = 1;
                    }
                    else {
                        if (seen_zero) protocol_error_reg._next = 1;
                        if (sop_seen && sop) protocol_error_reg._next = 1;
                        if (eop_seen && eop) protocol_error_reg._next = 1;
                        sop_seen = sop_seen || sop;
                        eop_seen = eop_seen || eop;
                        last_valid = eop;
                    }
                }
                if (sop_seen == (bool)in_frame_reg[lane]) {
                    protocol_error_reg._next = 1;
                }
                if (eop_seen && !last_valid) {
                    protocol_error_reg._next = 1;
                }
                if (eop_seen && !(bool)in_frame_reg[lane] && !sop_seen) {
                    protocol_error_reg._next = 1;
                }
                in_frame_reg[lane]._next = !eop_seen;
            }
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        for (size_t lane = 0; lane < LANES; ++lane) {
            fifos[lane]._strobe();
            in_frame_reg[lane].strobe();
        }
        protocol_error_reg.strobe();
    }
#endif

    void _strobe()
    {
        for (size_t lane = 0; lane < LANES; ++lane) {
            fifos[lane]._strobe();
            in_frame_reg[lane].strobe();
        }
        protocol_error_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class InputBalancer<64>;

#undef INPUT_BALANCER_FOR_EACH_LANE
