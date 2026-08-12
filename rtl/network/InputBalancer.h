#pragma once

// Eight-lane Ethernet input balancer for 8x160-bit 400G and 8x320-bit 800G
// streams at 312.5 MHz.  PCS lane reconstruction and ordering are upstream.
//
// The input is one ordered aggregate stream.  Byte-qualified SOP/EOP masks
// allow several frame boundaries, including EOP followed by SOP, in one clock.
// Frames are assigned round-robin to output streams that have room reserved for
// a maximum frame.  Per-output byte packers remove input IPG holes and retain
// both boundary masks when an old frame stops and a new frame starts in one
// output word.  Eight-bank FIFOs accept the worst-case eight words for one
// destination in a single aggregate input clock.

#include <cpphdl.h>
#include <algorithm>
#include "../common/ClockDomains.h"

using namespace cpphdl;

extern long _system_clock;

// Keep the physical storage explicit: every output has eight independently
// writable banks, so one aggregate beat can enqueue eight consecutive words.
#define INPUT_BALANCER_FOR_EACH_BANK(M) \
    M(0, 0) M(0, 1) M(0, 2) M(0, 3) M(0, 4) M(0, 5) M(0, 6) M(0, 7) \
    M(1, 0) M(1, 1) M(1, 2) M(1, 3) M(1, 4) M(1, 5) M(1, 6) M(1, 7) \
    M(2, 0) M(2, 1) M(2, 2) M(2, 3) M(2, 4) M(2, 5) M(2, 6) M(2, 7) \
    M(3, 0) M(3, 1) M(3, 2) M(3, 3) M(3, 4) M(3, 5) M(3, 6) M(3, 7) \
    M(4, 0) M(4, 1) M(4, 2) M(4, 3) M(4, 4) M(4, 5) M(4, 6) M(4, 7) \
    M(5, 0) M(5, 1) M(5, 2) M(5, 3) M(5, 4) M(5, 5) M(5, 6) M(5, 7) \
    M(6, 0) M(6, 1) M(6, 2) M(6, 3) M(6, 4) M(6, 5) M(6, 6) M(6, 7) \
    M(7, 0) M(7, 1) M(7, 2) M(7, 3) M(7, 4) M(7, 5) M(7, 6) M(7, 7)

template<size_t LANE_WIDTH = 160>
class InputBalancer : public Module
{
public:
    static constexpr size_t LANES = 8;
    static constexpr size_t FIFO_WORDS = 1024;
    static constexpr size_t MAX_FRAME_BYTES = 9216;
    static constexpr size_t FLUSH_CYCLES = 8;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t INPUT_BITS = LANES * LANE_WIDTH;
    static constexpr size_t INPUT_BYTES = LANES * LANE_BYTES;
    static constexpr size_t FIFO_BANKS = LANES;
    static constexpr size_t FIFO_BANK_DEPTH = FIFO_WORDS / FIFO_BANKS;
    static constexpr size_t MAX_LANE_WIDTH = 320;
    static constexpr size_t MAX_LANE_BYTES = MAX_LANE_WIDTH / 8;
    static constexpr size_t POINTER_BITS = clog2(FIFO_WORDS);
    static constexpr size_t COUNT_BITS = clog2(FIFO_WORDS + 1);
    static constexpr size_t PACK_COUNT_BITS = clog2(LANE_BYTES + 1);
    static constexpr size_t AGE_BITS = clog2(FLUSH_CYCLES + 1);
    static constexpr size_t RESERVED_WORDS =
        (MAX_FRAME_BYTES + LANE_BYTES - 1) / LANE_BYTES + LANES;
    static constexpr size_t ELIGIBLE_WORDS = FIFO_WORDS - RESERVED_WORDS;

    static_assert(LANE_WIDTH == 160 || LANE_WIDTH == 320,
        "InputBalancer supports the 400G 160-bit and 800G 320-bit lane widths");
    static_assert((LANE_WIDTH % 8) == 0, "lane width must be byte aligned");
    static_assert((FIFO_WORDS & (FIFO_WORDS - 1)) == 0,
        "FIFO_WORDS must be a power of two");
    static_assert((FIFO_WORDS % FIFO_BANKS) == 0,
        "FIFO_WORDS must divide evenly over eight banks");
    static_assert(RESERVED_WORDS < FIFO_WORDS,
        "FIFO must reserve one complete maximum-sized frame");
    static_assert(FLUSH_CYCLES > 0, "partial-word flush timeout must be nonzero");

    // Lane 0 and byte 0 are earliest on the wire.  SOP/EOP bits qualify the
    // corresponding valid byte; keep=0 represents reconstructed IPG/idle.
    _PORT(bool) valid_in;
    _PORT(logic<INPUT_BITS>) data_in;
    _PORT(logic<INPUT_BYTES>) keep_in;
    _PORT(logic<INPUT_BYTES>) sop_in;
    _PORT(logic<INPUT_BYTES>) eop_in;
    _PORT(bool) ready_out;

    // Output stream n occupies slice n*LANE_WIDTH +: LANE_WIDTH.  keep/SOP/EOP
    // use the equivalent byte slice.  ready_in is one bit per output stream.
    _PORT(logic<INPUT_BITS>) data_out;
    _PORT(logic<INPUT_BYTES>) keep_out;
    _PORT(logic<INPUT_BYTES>) sop_out;
    _PORT(logic<INPUT_BYTES>) eop_out;
    _PORT(logic<LANES>) valid_out;
    _PORT(logic<LANES>) ready_in;

    // Sticky indication of malformed boundary masks or an internal overflow.
    _PORT(bool) protocol_error_out;

private:
    // Each logical FIFO is split by low pointer bits.  Up to eight consecutive
    // pushes therefore write distinct banks while every output still pops one
    // word per clock.  Explicit CppHDL memories avoid whole-array next-state
    // copies and retain symbolic widths in both generated specializations.
#define INPUT_BALANCER_DECLARE_BANK(output, bank) \
    memory<logic<MAX_LANE_WIDTH>, 1, FIFO_BANK_DEPTH> data_##output##_##bank; \
    memory<logic<MAX_LANE_BYTES>, 1, FIFO_BANK_DEPTH> keep_##output##_##bank; \
    memory<logic<MAX_LANE_BYTES>, 1, FIFO_BANK_DEPTH> sop_##output##_##bank; \
    memory<logic<MAX_LANE_BYTES>, 1, FIFO_BANK_DEPTH> eop_##output##_##bank;
    INPUT_BALANCER_FOR_EACH_BANK(INPUT_BALANCER_DECLARE_BANK)
#undef INPUT_BALANCER_DECLARE_BANK

    reg<u<POINTER_BITS>> head_reg[LANES];
    reg<u<POINTER_BITS>> tail_reg[LANES];
    reg<u<COUNT_BITS>> count_reg[LANES];

    // Packers compact bytes belonging to each output independently.  A word
    // ending at EOP is held briefly so a later SOP can share the same clock.
    reg<logic<LANE_WIDTH>> pack_data_reg[LANES];
    reg<logic<LANE_BYTES>> pack_keep_reg[LANES];
    reg<logic<LANE_BYTES>> pack_sop_reg[LANES];
    reg<logic<LANE_BYTES>> pack_eop_reg[LANES];
    reg<u<PACK_COUNT_BITS>> pack_count_reg[LANES];
    reg<u1> pack_boundary_reg[LANES];
    reg<u<AGE_BITS>> pack_age_reg[LANES];

    reg<u<3>> rr_reg;
    reg<u<3>> frame_dest_reg;
    reg<u1> in_frame_reg;
    reg<u1> protocol_error_reg;

    uint32_t occupancy_after_pop(size_t output)
    {
        uint32_t count = (uint32_t)count_reg[output];
        if (count != 0 && (bool)ready_in()[output]) {
            --count;
        }
        if ((uint32_t)pack_count_reg[output] != 0) {
            ++count;
        }
        return count;
    }

    bool output_eligible(size_t output)
    {
        return occupancy_after_pop(output) <= ELIGIBLE_WORDS;
    }

    // The source can advance when the active frame has worst-case push room
    // and every SOP visible in this clock can reserve a distinct destination.
    _LAZY_COMB(input_ready_comb, bool)
        size_t output;
        size_t byte;
        uint32_t eligible;
        uint32_t starts;
        uint32_t active_count;

        input_ready_comb = true;
        active_count = 0;
        if (!valid_in()) {
            return input_ready_comb;
        }

        eligible = 0;
        for (output = 0; output < LANES; ++output) {
            if (output_eligible(output)) {
                ++eligible;
            }
        }
        starts = 0;
        for (byte = 0; byte < INPUT_BYTES; ++byte) {
            if ((bool)keep_in()[byte] && (bool)sop_in()[byte]) {
                ++starts;
            }
        }
        if (starts > eligible) {
            input_ready_comb = false;
        }

        if ((bool)in_frame_reg) {
            active_count = (uint32_t)count_reg[(uint32_t)frame_dest_reg];
            if (active_count != 0 && (bool)ready_in()[(uint32_t)frame_dest_reg]) {
                --active_count;
            }
            if (active_count > FIFO_WORDS - LANES) {
                input_ready_comb = false;
            }
        }
        return input_ready_comb;
    }

    _LAZY_COMB(output_data_comb, logic<INPUT_BITS>)
        size_t output;
        size_t lane_bit;
        uint32_t logical;
        uint32_t bank;
        uint32_t row;
        logic<MAX_LANE_WIDTH> entry;

        output_data_comb = 0;
        logical = 0;
        bank = 0;
        row = 0;
        entry = 0;
        for (output = 0; output < LANES; ++output) {
            if ((uint32_t)count_reg[output] != 0) {
                logical = (uint32_t)head_reg[output];
                bank = logical & (FIFO_BANKS - 1);
                row = logical >> 3;
#define INPUT_BALANCER_READ_DATA(output_number, bank_number) \
                if (output == output_number && bank == bank_number) { \
                    entry = data_##output_number##_##bank_number[row]; \
                }
                INPUT_BALANCER_FOR_EACH_BANK(INPUT_BALANCER_READ_DATA)
#undef INPUT_BALANCER_READ_DATA
                for (lane_bit = 0; lane_bit < LANE_WIDTH; ++lane_bit) {
                    output_data_comb[output * LANE_WIDTH + lane_bit] = entry[lane_bit];
                }
            }
        }
        return output_data_comb;
    }

    _LAZY_COMB(output_keep_comb, logic<INPUT_BYTES>)
        size_t output;
        size_t lane_byte;
        uint32_t logical;
        uint32_t bank;
        uint32_t row;
        logic<MAX_LANE_BYTES> entry;

        output_keep_comb = 0;
        logical = 0;
        bank = 0;
        row = 0;
        entry = 0;
        for (output = 0; output < LANES; ++output) {
            if ((uint32_t)count_reg[output] != 0) {
                logical = (uint32_t)head_reg[output];
                bank = logical & (FIFO_BANKS - 1);
                row = logical >> 3;
#define INPUT_BALANCER_READ_KEEP(output_number, bank_number) \
                    if (output == output_number && bank == bank_number) { \
                        entry = keep_##output_number##_##bank_number[row]; \
                    }
                INPUT_BALANCER_FOR_EACH_BANK(INPUT_BALANCER_READ_KEEP)
#undef INPUT_BALANCER_READ_KEEP
                for (lane_byte = 0; lane_byte < LANE_BYTES; ++lane_byte) {
                    output_keep_comb[output * LANE_BYTES + lane_byte] = entry[lane_byte];
                }
            }
        }
        return output_keep_comb;
    }

    _LAZY_COMB(output_sop_comb, logic<INPUT_BYTES>)
        size_t output;
        size_t lane_byte;
        uint32_t logical;
        uint32_t bank;
        uint32_t row;
        logic<MAX_LANE_BYTES> entry;

        output_sop_comb = 0;
        logical = 0;
        bank = 0;
        row = 0;
        entry = 0;
        for (output = 0; output < LANES; ++output) {
            if ((uint32_t)count_reg[output] != 0) {
                logical = (uint32_t)head_reg[output];
                bank = logical & (FIFO_BANKS - 1);
                row = logical >> 3;
#define INPUT_BALANCER_READ_SOP(output_number, bank_number) \
                    if (output == output_number && bank == bank_number) { \
                        entry = sop_##output_number##_##bank_number[row]; \
                    }
                INPUT_BALANCER_FOR_EACH_BANK(INPUT_BALANCER_READ_SOP)
#undef INPUT_BALANCER_READ_SOP
                for (lane_byte = 0; lane_byte < LANE_BYTES; ++lane_byte) {
                    output_sop_comb[output * LANE_BYTES + lane_byte] = entry[lane_byte];
                }
            }
        }
        return output_sop_comb;
    }

    _LAZY_COMB(output_eop_comb, logic<INPUT_BYTES>)
        size_t output;
        size_t lane_byte;
        uint32_t logical;
        uint32_t bank;
        uint32_t row;
        logic<MAX_LANE_BYTES> entry;

        output_eop_comb = 0;
        logical = 0;
        bank = 0;
        row = 0;
        entry = 0;
        for (output = 0; output < LANES; ++output) {
            if ((uint32_t)count_reg[output] != 0) {
                logical = (uint32_t)head_reg[output];
                bank = logical & (FIFO_BANKS - 1);
                row = logical >> 3;
#define INPUT_BALANCER_READ_EOP(output_number, bank_number) \
                    if (output == output_number && bank == bank_number) { \
                        entry = eop_##output_number##_##bank_number[row]; \
                    }
                INPUT_BALANCER_FOR_EACH_BANK(INPUT_BALANCER_READ_EOP)
#undef INPUT_BALANCER_READ_EOP
                for (lane_byte = 0; lane_byte < LANE_BYTES; ++lane_byte) {
                    output_eop_comb[output * LANE_BYTES + lane_byte] = entry[lane_byte];
                }
            }
        }
        return output_eop_comb;
    }

    _LAZY_COMB(output_valid_comb, logic<LANES>)
        size_t output;
        output_valid_comb = 0;
        for (output = 0; output < LANES; ++output) {
            output_valid_comb[output] = (uint32_t)count_reg[output] != 0;
        }
        return output_valid_comb;
    }

public:
#ifndef SYNTHESIS
    uint32_t debug_total_words() const
    {
        uint32_t total = 0;
        for (uint32_t output = 0; output < LANES; ++output) {
            total += (uint32_t)count_reg[output];
        }
        return total;
    }

    uint32_t debug_max_words() const
    {
        uint32_t maximum = 0;
        for (uint32_t output = 0; output < LANES; ++output) {
            maximum = std::max(maximum, (uint32_t)count_reg[output]);
        }
        return maximum;
    }
#endif

    void _assign()
    {
        ready_out = _ASSIGN_COMB(input_ready_comb_func());
        data_out = _ASSIGN_COMB(output_data_comb_func());
        keep_out = _ASSIGN_COMB(output_keep_comb_func());
        sop_out = _ASSIGN_COMB(output_sop_comb_func());
        eop_out = _ASSIGN_COMB(output_eop_comb_func());
        valid_out = _ASSIGN_COMB(output_valid_comb_func());
        protocol_error_out = _ASSIGN_REG(protocol_error_reg);
    }

    void _work(bool reset)
    {
        size_t output;
        size_t byte;
        size_t offset;
        uint32_t head[LANES];
        uint32_t tail[LANES];
        uint32_t count[LANES];
        uint32_t pushes[LANES];
        uint32_t pack_count[LANES];
        uint32_t pack_age[LANES];
        bool pack_boundary[LANES];
        bool appended[LANES];
        bool reserved[LANES];
        bool in_frame;
        bool found;
        bool keep;
        bool sop;
        bool eop;
        uint32_t rr;
        uint32_t dest;
        uint32_t candidate;
        uint32_t logical;
        uint32_t bank;
        uint32_t row;
        uint8_t input_byte;

        if (reset) {
            for (output = 0; output < LANES; ++output) {
                head_reg[output]._next = 0;
                tail_reg[output]._next = 0;
                count_reg[output]._next = 0;
                pack_data_reg[output]._next = 0;
                pack_keep_reg[output]._next = 0;
                pack_sop_reg[output]._next = 0;
                pack_eop_reg[output]._next = 0;
                pack_count_reg[output]._next = 0;
                pack_boundary_reg[output]._next = 0;
                pack_age_reg[output]._next = 0;
            }
            rr_reg._next = 0;
            frame_dest_reg._next = 0;
            in_frame_reg._next = 0;
            protocol_error_reg._next = 0;
            return;
        }

        for (output = 0; output < LANES; ++output) {
            head[output] = (uint32_t)head_reg[output];
            tail[output] = (uint32_t)tail_reg[output];
            count[output] = (uint32_t)count_reg[output];
            pushes[output] = 0;
            pack_count[output] = (uint32_t)pack_count_reg[output];
            pack_age[output] = (uint32_t)pack_age_reg[output];
            pack_data_reg[output]._next = pack_data_reg[output];
            pack_keep_reg[output]._next = pack_keep_reg[output];
            pack_sop_reg[output]._next = pack_sop_reg[output];
            pack_eop_reg[output]._next = pack_eop_reg[output];
            pack_boundary[output] = (bool)pack_boundary_reg[output];
            appended[output] = false;
            reserved[output] = false;

            if (count[output] != 0 && (bool)ready_in()[output]) {
                head[output] = (head[output] + 1) & (FIFO_WORDS - 1);
                --count[output];
            }
        }

        rr = (uint32_t)rr_reg;
        dest = (uint32_t)frame_dest_reg;
        in_frame = (bool)in_frame_reg;

        if (valid_in() && input_ready_comb_func()) {
            // Scan in exact wire order.  This loop both identifies frames and
            // compacts their bytes into the independently selected stream.
            for (byte = 0; byte < INPUT_BYTES; ++byte) {
                keep = (bool)keep_in()[byte];
                sop = (bool)sop_in()[byte];
                eop = (bool)eop_in()[byte];

                if (!keep) {
                    if (sop || eop) {
                        protocol_error_reg._next = 1;
                    }
                }
                else {
                    if (sop) {
                        if (in_frame) {
                            protocol_error_reg._next = 1;
                        }
                        found = false;
                        candidate = rr;
                        for (offset = 0; offset < LANES; ++offset) {
                            candidate = (rr + offset) & (LANES - 1);
                            if (!found && !reserved[candidate]
                                && output_eligible(candidate)) {
                                dest = candidate;
                                found = true;
                            }
                        }
                        if (!found) {
                            protocol_error_reg._next = 1;
                        }
                        else {
                            reserved[dest] = true;
                            rr = (dest + 1) & (LANES - 1);
                        }
                        in_frame = true;
                    }
                    else if (!in_frame) {
                        protocol_error_reg._next = 1;
                    }

                    input_byte = (uint8_t)data_in().bits(byte * 8 + 7, byte * 8);
                    // Single-bit assignments keep the generated part-select
                    // width constant in both LANE_WIDTH specializations.
                    for (offset = 0; offset < 8; ++offset) {
                        pack_data_reg[dest]._next[pack_count[dest] * 8 + offset] =
                            (input_byte >> offset) & 1;
                    }
                    pack_keep_reg[dest]._next[pack_count[dest]] = 1;
                    pack_sop_reg[dest]._next[pack_count[dest]] = sop;
                    pack_eop_reg[dest]._next[pack_count[dest]] = eop;
                    ++pack_count[dest];
                    appended[dest] = true;
                    pack_age[dest] = 0;
                    pack_boundary[dest] = eop;

                    if (pack_count[dest] == LANE_BYTES) {
                        logical = (tail[dest] + pushes[dest]) & (FIFO_WORDS - 1);
                        bank = logical & (FIFO_BANKS - 1);
                        row = logical >> 3;
#define INPUT_BALANCER_WRITE_DEST(output_number, bank_number) \
                        if (dest == output_number && bank == bank_number) { \
                            data_##output_number##_##bank_number[row] = pack_data_reg[dest]._next; \
                            keep_##output_number##_##bank_number[row] = pack_keep_reg[dest]._next; \
                            sop_##output_number##_##bank_number[row] = pack_sop_reg[dest]._next; \
                            eop_##output_number##_##bank_number[row] = pack_eop_reg[dest]._next; \
                        }
                        INPUT_BALANCER_FOR_EACH_BANK(INPUT_BALANCER_WRITE_DEST)
#undef INPUT_BALANCER_WRITE_DEST
                        ++pushes[dest];
                        pack_data_reg[dest]._next = 0;
                        pack_keep_reg[dest]._next = 0;
                        pack_sop_reg[dest]._next = 0;
                        pack_eop_reg[dest]._next = 0;
                        pack_count[dest] = 0;
                        pack_boundary[dest] = false;
                    }

                    if (eop) {
                        if (!in_frame) {
                            protocol_error_reg._next = 1;
                        }
                        in_frame = false;
                    }
                }
            }
        }

        for (output = 0; output < LANES; ++output) {
            // A completed partial word waits for another frame so EOP and SOP
            // can share a beat.  The timeout bounds latency for sparse traffic.
            if (pack_count[output] != 0 && pack_boundary[output]
                && !appended[output]) {
                if (pack_age[output] + 1 >= FLUSH_CYCLES) {
                    logical = (tail[output] + pushes[output]) & (FIFO_WORDS - 1);
                    bank = logical & (FIFO_BANKS - 1);
                    row = logical >> 3;
#define INPUT_BALANCER_WRITE_OUTPUT(output_number, bank_number) \
                    if (output == output_number && bank == bank_number) { \
                        data_##output_number##_##bank_number[row] = pack_data_reg[output]._next; \
                        keep_##output_number##_##bank_number[row] = pack_keep_reg[output]._next; \
                        sop_##output_number##_##bank_number[row] = pack_sop_reg[output]._next; \
                        eop_##output_number##_##bank_number[row] = pack_eop_reg[output]._next; \
                    }
                    INPUT_BALANCER_FOR_EACH_BANK(INPUT_BALANCER_WRITE_OUTPUT)
#undef INPUT_BALANCER_WRITE_OUTPUT
                    ++pushes[output];
                    pack_data_reg[output]._next = 0;
                    pack_keep_reg[output]._next = 0;
                    pack_sop_reg[output]._next = 0;
                    pack_eop_reg[output]._next = 0;
                    pack_count[output] = 0;
                    pack_boundary[output] = false;
                    pack_age[output] = 0;
                }
                else {
                    ++pack_age[output];
                }
            }

            if (count[output] + pushes[output] > FIFO_WORDS) {
                protocol_error_reg._next = 1;
            }
            else {
                count[output] += pushes[output];
            }
            tail[output] = (tail[output] + pushes[output]) & (FIFO_WORDS - 1);

            head_reg[output]._next = u<POINTER_BITS>(head[output]);
            tail_reg[output]._next = u<POINTER_BITS>(tail[output]);
            count_reg[output]._next = u<COUNT_BITS>(count[output]);
            pack_count_reg[output]._next = u<PACK_COUNT_BITS>(pack_count[output]);
            pack_boundary_reg[output]._next = pack_boundary[output];
            pack_age_reg[output]._next = u<AGE_BITS>(pack_age[output]);
        }

        rr_reg._next = u<3>(rr);
        frame_dest_reg._next = u<3>(dest);
        in_frame_reg._next = in_frame;
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        size_t output;
#define INPUT_BALANCER_APPLY_BANK(output_number, bank_number) \
        data_##output_number##_##bank_number.apply(); \
        keep_##output_number##_##bank_number.apply(); \
        sop_##output_number##_##bank_number.apply(); \
        eop_##output_number##_##bank_number.apply();
        INPUT_BALANCER_FOR_EACH_BANK(INPUT_BALANCER_APPLY_BANK)
#undef INPUT_BALANCER_APPLY_BANK
        for (output = 0; output < LANES; ++output) {
            head_reg[output].strobe();
            tail_reg[output].strobe();
            count_reg[output].strobe();
            pack_data_reg[output].strobe();
            pack_keep_reg[output].strobe();
            pack_sop_reg[output].strobe();
            pack_eop_reg[output].strobe();
            pack_count_reg[output].strobe();
            pack_boundary_reg[output].strobe();
            pack_age_reg[output].strobe();
        }
        rr_reg.strobe();
        frame_dest_reg.strobe();
        in_frame_reg.strobe();
        protocol_error_reg.strobe();
    }
#endif

    void _strobe()
    {
        size_t output;
#define INPUT_BALANCER_APPLY_LEGACY_BANK(output_number, bank_number) \
        data_##output_number##_##bank_number.apply(); \
        keep_##output_number##_##bank_number.apply(); \
        sop_##output_number##_##bank_number.apply(); \
        eop_##output_number##_##bank_number.apply();
        INPUT_BALANCER_FOR_EACH_BANK(INPUT_BALANCER_APPLY_LEGACY_BANK)
#undef INPUT_BALANCER_APPLY_LEGACY_BANK
        for (output = 0; output < LANES; ++output) {
            head_reg[output].strobe(); tail_reg[output].strobe();
            count_reg[output].strobe(); pack_data_reg[output].strobe();
            pack_keep_reg[output].strobe(); pack_sop_reg[output].strobe();
            pack_eop_reg[output].strobe(); pack_count_reg[output].strobe();
            pack_boundary_reg[output].strobe(); pack_age_reg[output].strobe();
        }
        rr_reg.strobe(); frame_dest_reg.strobe(); in_frame_reg.strobe();
        protocol_error_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class InputBalancer<160>;
template class InputBalancer<320>;

#undef INPUT_BALANCER_FOR_EACH_BANK
