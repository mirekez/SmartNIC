#pragma once

// Two packet-committed TxFifos merged into one ordered 2-lane Ethernet
// stream.  Packets are selected round-robin at frame boundaries.  A one-word
// carry absorbs arbitrary output alignment; the merger inserts exactly the
// configured IPG whenever another committed packet is immediately available.

#include "TxFifo.h"
#include "../common/ClockDomains.h"

using namespace cpphdl;

#define OUTPUT_MERGER_FOR_EACH_STREAM(M) M(0) M(1)

template<size_t LANE_WIDTH = 64, size_t FIFO_WORDS = 2048,
    size_t MIN_IPG_BYTES = 12>
class OutputMerger : public Module
{
public:
    static constexpr size_t STREAMS = 2;
    static constexpr size_t WINDOW_WORDS = 8;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t OUTPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t OUTPUT_BYTES = STREAMS * LANE_BYTES;
    static constexpr size_t MAX_LANE_WIDTH = 64;
    static constexpr size_t MAX_LANE_BYTES = MAX_LANE_WIDTH / 8;
    static constexpr size_t OFFSET_BITS = clog2(LANE_BYTES);
    static constexpr size_t GAP_BITS = clog2(MIN_IPG_BYTES + 1);

    _PORT(logic<STREAMS>) tx_valid_in;
    _PORT(logic<STREAMS * LANE_WIDTH>) tx_data_in;
    _PORT(logic<STREAMS * LANE_BYTES>) tx_keep_in;
    _PORT(logic<STREAMS>) tx_sop_in;
    _PORT(logic<STREAMS>) tx_eop_in;
    _PORT(logic<STREAMS>) tx_ready_out;
    _PORT(logic<STREAMS>) tx_almost_full_out;
    _PORT(logic<STREAMS>) tx_protocol_error_out;

    _PORT(bool) valid_out;
    _PORT(logic<OUTPUT_BITS>) data_out;
    _PORT(logic<OUTPUT_BYTES>) keep_out;
    _PORT(logic<OUTPUT_BYTES>) sop_out;
    _PORT(logic<OUTPUT_BYTES>) eop_out;
    _PORT(bool) ready_in;
    _PORT(bool) protocol_error_out;

private:
    static constexpr size_t FIFO_DATA_BITS =
        STREAMS * WINDOW_WORDS * LANE_WIDTH;
    static constexpr size_t FIFO_KEEP_BITS =
        STREAMS * WINDOW_WORDS * LANE_BYTES;
    static constexpr size_t FIFO_FLAG_BITS = STREAMS * WINDOW_WORDS;
    static constexpr size_t MAX_FIFO_DATA_BITS =
        STREAMS * WINDOW_WORDS * MAX_LANE_WIDTH;
    static constexpr size_t MAX_FIFO_KEEP_BITS =
        STREAMS * WINDOW_WORDS * MAX_LANE_BYTES;
    static constexpr size_t READ_COUNT_BITS = STREAMS * 4;

    static constexpr size_t RESULT_DATA = 0;
    static constexpr size_t RESULT_KEEP = RESULT_DATA + OUTPUT_BITS;
    static constexpr size_t RESULT_SOP = RESULT_KEEP + OUTPUT_BYTES;
    static constexpr size_t RESULT_EOP = RESULT_SOP + OUTPUT_BYTES;
    static constexpr size_t RESULT_VALID = RESULT_EOP + OUTPUT_BYTES;
    static constexpr size_t RESULT_NEXT_RR = RESULT_VALID + 1;
    static constexpr size_t RESULT_NEXT_ACTIVE = RESULT_NEXT_RR + 3;
    static constexpr size_t RESULT_NEXT_STREAM = RESULT_NEXT_ACTIVE + 1;
    static constexpr size_t RESULT_NEXT_GAP = RESULT_NEXT_STREAM + 3;
    static constexpr size_t RESULT_NEXT_CARRY_VALID =
        RESULT_NEXT_GAP + GAP_BITS;
    static constexpr size_t RESULT_NEXT_CARRY_OFFSET =
        RESULT_NEXT_CARRY_VALID + 1;
    static constexpr size_t RESULT_NEXT_CARRY_DATA =
        RESULT_NEXT_CARRY_OFFSET + OFFSET_BITS;
    static constexpr size_t RESULT_NEXT_CARRY_KEEP =
        RESULT_NEXT_CARRY_DATA + LANE_WIDTH;
    static constexpr size_t RESULT_NEXT_CARRY_SOP =
        RESULT_NEXT_CARRY_KEEP + LANE_BYTES;
    static constexpr size_t RESULT_NEXT_CARRY_EOP =
        RESULT_NEXT_CARRY_SOP + 1;
    static constexpr size_t RESULT_ERROR = RESULT_NEXT_CARRY_EOP + 1;
    static constexpr size_t RESULT_BITS = RESULT_ERROR + 1;

    TxFifo<LANE_WIDTH, FIFO_WORDS> fifos[STREAMS];

    reg<u<3>> rr_reg;
    reg<u1> active_reg;
    reg<u<3>> stream_reg;
    reg<u<GAP_BITS>> gap_reg;
    reg<u1> carry_valid_reg;
    reg<u<OFFSET_BITS>> carry_offset_reg;
    reg<logic<LANE_WIDTH>> carry_data_reg;
    reg<logic<LANE_BYTES>> carry_keep_reg;
    reg<u1> carry_sop_reg;
    reg<u1> carry_eop_reg;
    reg<u1> protocol_error_reg;

    logic<STREAMS> tx_ready_comb;
    logic<STREAMS> tx_almost_full_comb;
    logic<STREAMS> tx_fifo_error_comb;
    logic<READ_COUNT_BITS> merge_read_counts_comb;
#define OUTPUT_MERGER_DECLARE_INPUT(number) \
    logic<LANE_WIDTH> tx_data_##number##_comb; \
    logic<LANE_WIDTH>& tx_data_##number##_comb_func() \
    { \
        size_t bit; \
        for (bit = 0; bit < LANE_WIDTH; ++bit) \
            tx_data_##number##_comb[bit] = tx_data_in()[number * LANE_WIDTH + bit]; \
        return tx_data_##number##_comb; \
    } \
    logic<LANE_BYTES> tx_keep_##number##_comb; \
    logic<LANE_BYTES>& tx_keep_##number##_comb_func() \
    { \
        size_t byte; \
        for (byte = 0; byte < LANE_BYTES; ++byte) \
            tx_keep_##number##_comb[byte] = tx_keep_in()[number * LANE_BYTES + byte]; \
        return tx_keep_##number##_comb; \
    }
    OUTPUT_MERGER_FOR_EACH_STREAM(OUTPUT_MERGER_DECLARE_INPUT)
#undef OUTPUT_MERGER_DECLARE_INPUT

    logic<STREAMS>& tx_ready_comb_func()
    {
        size_t stream;
        tx_ready_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            tx_ready_comb[stream] = fifos[stream].ready_out();
        }
        return tx_ready_comb;
    }

    logic<STREAMS>& tx_almost_full_comb_func()
    {
        size_t stream;
        tx_almost_full_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            tx_almost_full_comb[stream] = fifos[stream].almost_full_out();
        }
        return tx_almost_full_comb;
    }

    logic<STREAMS>& tx_fifo_error_comb_func()
    {
        size_t stream;
        tx_fifo_error_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            tx_fifo_error_comb[stream] = fifos[stream].protocol_error_out();
        }
        return tx_fifo_error_comb;
    }

    _LAZY_COMB(fifo_data_comb, logic<FIFO_DATA_BITS>)
        size_t stream;
        size_t bit;
        logic<WINDOW_WORDS * MAX_LANE_WIDTH> value;
        fifo_data_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            value = fifos[stream].data_out();
            for (bit = 0; bit < WINDOW_WORDS * LANE_WIDTH; ++bit) {
                fifo_data_comb[stream * WINDOW_WORDS * LANE_WIDTH + bit] =
                    value[bit];
            }
        }
        return fifo_data_comb;
    }

    _LAZY_COMB(fifo_keep_comb, logic<FIFO_KEEP_BITS>)
        size_t stream;
        size_t bit;
        logic<WINDOW_WORDS * MAX_LANE_BYTES> value;
        fifo_keep_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            value = fifos[stream].keep_out();
            for (bit = 0; bit < WINDOW_WORDS * LANE_BYTES; ++bit) {
                fifo_keep_comb[stream * WINDOW_WORDS * LANE_BYTES + bit] =
                    value[bit];
            }
        }
        return fifo_keep_comb;
    }

    _LAZY_COMB(fifo_sop_comb, logic<FIFO_FLAG_BITS>)
        size_t stream;
        size_t slot;
        logic<WINDOW_WORDS> value;
        fifo_sop_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            value = fifos[stream].sop_out();
            for (slot = 0; slot < WINDOW_WORDS; ++slot) {
                fifo_sop_comb[stream * WINDOW_WORDS + slot] = value[slot];
            }
        }
        return fifo_sop_comb;
    }

    _LAZY_COMB(fifo_eop_comb, logic<FIFO_FLAG_BITS>)
        size_t stream;
        size_t slot;
        logic<WINDOW_WORDS> value;
        fifo_eop_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            value = fifos[stream].eop_out();
            for (slot = 0; slot < WINDOW_WORDS; ++slot) {
                fifo_eop_comb[stream * WINDOW_WORDS + slot] = value[slot];
            }
        }
        return fifo_eop_comb;
    }

    _LAZY_COMB(fifo_valid_comb, logic<FIFO_FLAG_BITS>)
        size_t stream;
        size_t slot;
        logic<WINDOW_WORDS> value;
        fifo_valid_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            value = fifos[stream].valid_out();
            for (slot = 0; slot < WINDOW_WORDS; ++slot) {
                fifo_valid_comb[stream * WINDOW_WORDS + slot] = value[slot];
            }
        }
        return fifo_valid_comb;
    }

    _LAZY_COMB(merge_result_comb, logic<RESULT_BITS>)
        size_t output_byte;
        size_t bit;
        size_t scan;
        size_t remaining;
        uint32_t rr;
        uint32_t selected;
        uint32_t candidate;
        uint32_t slot;
        uint32_t byte_index;
        uint32_t gap;
        bool active;
        bool loaded;
        bool found;
        bool any_data;
        bool last_byte;
        bool error;
        bool blocked;
        bool expect_sop;
        bool word_sop;
        bool word_eop;
        logic<READ_COUNT_BITS> read_counts;
        logic<MAX_LANE_WIDTH> word_data;
        logic<MAX_LANE_BYTES> word_keep;
        logic<MAX_FIFO_DATA_BITS> all_data;
        logic<MAX_FIFO_KEEP_BITS> all_keep;
        logic<FIFO_FLAG_BITS> all_sop;
        logic<FIFO_FLAG_BITS> all_eop;
        logic<FIFO_FLAG_BITS> all_valid;

        merge_result_comb = 0;
        read_counts = 0;
        merge_read_counts_comb = 0;
        all_valid = fifo_valid_comb_func();
        rr = (uint32_t)rr_reg;
        selected = (uint32_t)stream_reg;
        candidate = 0;
        slot = 0;
        last_byte = false;
        active = (bool)active_reg;
        expect_sop = !active;
        gap = (uint32_t)gap_reg;
        loaded = (bool)carry_valid_reg;
        byte_index = (uint32_t)carry_offset_reg;
        word_data = carry_data_reg;
        word_keep = carry_keep_reg;
        word_sop = (bool)carry_sop_reg;
        word_eop = (bool)carry_eop_reg;
        any_data = false;
        error = false;
        blocked = false;

        // RX-only operation should not pay for copying the very wide TX read
        // windows.  With no active packet or committed FIFO word, valid_out is
        // simply low and no state can advance.
        found = false;
        for (scan = 0; scan < FIFO_FLAG_BITS; ++scan) {
            if ((bool)all_valid[scan]) found = true;
        }
        if (!active && gap == 0 && !found) {
            return merge_result_comb;
        }
        all_data = fifo_data_comb_func();
        all_keep = fifo_keep_comb_func();
        all_sop = fifo_sop_comb_func();
        all_eop = fifo_eop_comb_func();

        for (output_byte = 0; output_byte < OUTPUT_BYTES; ++output_byte) {
            if (!blocked) {
                if (gap != 0) {
                    --gap;
                }
                else {
                    if (!active) {
                        found = false;
                        for (scan = 0; scan < STREAMS; ++scan) {
                            candidate = (rr + scan) & (STREAMS - 1);
                            slot = 0;
                            for (bit = 0; bit < 4; ++bit) {
                                if ((bool)read_counts[candidate * 4 + bit]) {
                                    slot |= 1u << bit;
                                }
                            }
                            if (!found && slot < WINDOW_WORDS
                                && (bool)all_valid[
                                    candidate * WINDOW_WORDS + slot]) {
                                selected = candidate;
                                found = true;
                            }
                        }
                        if (!found) {
                            blocked = true;
                        }
                        else {
                            active = true;
                            expect_sop = true;
                            loaded = false;
                        }
                    }

                    if (!blocked && !loaded) {
                        slot = 0;
                        for (bit = 0; bit < 4; ++bit) {
                            if ((bool)read_counts[selected * 4 + bit]) {
                                slot |= 1u << bit;
                            }
                        }
                        if (slot >= WINDOW_WORDS
                            || !(bool)all_valid[
                                selected * WINDOW_WORDS + slot]) {
                            error = true;
                            blocked = true;
                        }
                        else {
                            word_data = 0;
                            word_keep = 0;
                            for (bit = 0; bit < LANE_WIDTH; ++bit) {
                                word_data[bit] = all_data[
                                    (selected * WINDOW_WORDS + slot)
                                    * LANE_WIDTH + bit];
                            }
                            for (bit = 0; bit < LANE_BYTES; ++bit) {
                                word_keep[bit] = all_keep[
                                    (selected * WINDOW_WORDS + slot)
                                    * LANE_BYTES + bit];
                            }
                            word_sop = (bool)all_sop[
                                selected * WINDOW_WORDS + slot];
                            word_eop = (bool)all_eop[
                                selected * WINDOW_WORDS + slot];
                            for (bit = 0; bit < 4; ++bit) {
                                read_counts[selected * 4 + bit] =
                                    ((slot + 1) >> bit) & 1;
                            }
                            byte_index = 0;
                            loaded = true;
                            if (word_sop != expect_sop) error = true;
                            expect_sop = false;
                        }
                    }

                    if (!blocked && !(bool)word_keep[byte_index]) {
                        error = true;
                        blocked = true;
                    }
                    if (!blocked) {
                        for (bit = 0; bit < 8; ++bit) {
                            merge_result_comb[
                                RESULT_DATA + output_byte * 8 + bit] =
                                word_data[byte_index * 8 + bit];
                        }
                        merge_result_comb[RESULT_KEEP + output_byte] = 1;
                        merge_result_comb[RESULT_SOP + output_byte] =
                            word_sop && byte_index == 0;
                        any_data = true;

                        last_byte = true;
                        // Keep the loop's initialization and trip count static
                        // so Vivado can unroll it.  A data-dependent initial
                        // value makes the synthesizer's convergence check fail.
                        for (remaining = 0;
                             remaining < LANE_BYTES; ++remaining) {
                            if (remaining > byte_index
                                && (bool)word_keep[remaining]) {
                                last_byte = false;
                            }
                        }
                        if (word_eop && last_byte) {
                            merge_result_comb[RESULT_EOP + output_byte] = 1;
                            active = false;
                            expect_sop = true;
                            loaded = false;
                            byte_index = 0;
                            gap = MIN_IPG_BYTES;
                            rr = (selected + 1) & (STREAMS - 1);
                        }
                        else {
                            ++byte_index;
                            if (byte_index == LANE_BYTES) {
                                loaded = false;
                                byte_index = 0;
                            }
                        }
                    }
                    if (blocked && !any_data) {
                        loaded = false;
                    }
                }
            }
        }

        for (bit = 0; bit < READ_COUNT_BITS; ++bit) {
            merge_read_counts_comb[bit] = read_counts[bit];
        }
        merge_result_comb[RESULT_VALID] = any_data;
        merge_result_comb.bits(RESULT_NEXT_RR + 2, RESULT_NEXT_RR) = rr;
        merge_result_comb[RESULT_NEXT_ACTIVE] = active;
        merge_result_comb.bits(RESULT_NEXT_STREAM + 2,
            RESULT_NEXT_STREAM) = selected;
        merge_result_comb.bits(RESULT_NEXT_GAP + GAP_BITS - 1,
            RESULT_NEXT_GAP) = gap;
        merge_result_comb[RESULT_NEXT_CARRY_VALID] = loaded;
        merge_result_comb.bits(
            RESULT_NEXT_CARRY_OFFSET + OFFSET_BITS - 1,
            RESULT_NEXT_CARRY_OFFSET) = byte_index;
        if (loaded) {
            merge_result_comb.bits(RESULT_NEXT_CARRY_DATA + LANE_WIDTH - 1,
                RESULT_NEXT_CARRY_DATA) = word_data;
            merge_result_comb.bits(RESULT_NEXT_CARRY_KEEP + LANE_BYTES - 1,
                RESULT_NEXT_CARRY_KEEP) = word_keep;
            merge_result_comb[RESULT_NEXT_CARRY_SOP] = word_sop;
            merge_result_comb[RESULT_NEXT_CARRY_EOP] = word_eop;
        }
        merge_result_comb[RESULT_ERROR] = error;
        return merge_result_comb;
    }

    logic<OUTPUT_BITS> output_data_comb;
    logic<OUTPUT_BITS>& output_data_comb_func()
    {
        output_data_comb = merge_result_comb_func().bits(
            RESULT_DATA + OUTPUT_BITS - 1, RESULT_DATA);
        return output_data_comb;
    }

    logic<OUTPUT_BYTES> output_keep_comb;
    logic<OUTPUT_BYTES>& output_keep_comb_func()
    {
        output_keep_comb = merge_result_comb_func().bits(
            RESULT_KEEP + OUTPUT_BYTES - 1, RESULT_KEEP);
        return output_keep_comb;
    }

    logic<OUTPUT_BYTES> output_sop_comb;
    logic<OUTPUT_BYTES>& output_sop_comb_func()
    {
        output_sop_comb = merge_result_comb_func().bits(
            RESULT_SOP + OUTPUT_BYTES - 1, RESULT_SOP);
        return output_sop_comb;
    }

    logic<OUTPUT_BYTES> output_eop_comb;
    logic<OUTPUT_BYTES>& output_eop_comb_func()
    {
        output_eop_comb = merge_result_comb_func().bits(
            RESULT_EOP + OUTPUT_BYTES - 1, RESULT_EOP);
        return output_eop_comb;
    }

    bool output_valid_comb;
    bool& output_valid_comb_func()
    {
        output_valid_comb = (bool)merge_result_comb_func()[RESULT_VALID];
        return output_valid_comb;
    }

#define OUTPUT_MERGER_DECLARE_READ_COUNT(number) \
    u<4> read_count_##number##_comb; \
    u<4>& read_count_##number##_comb_func() \
    { \
        read_count_##number##_comb = 0; \
        if (output_valid_comb_func() && ready_in()) { \
            read_count_##number##_comb = \
                ((uint32_t)(uint64_t)merge_read_counts_comb \
                    >> (number * 4)) & 15; \
        } \
        return read_count_##number##_comb; \
    }
    OUTPUT_MERGER_FOR_EACH_STREAM(OUTPUT_MERGER_DECLARE_READ_COUNT)
#undef OUTPUT_MERGER_DECLARE_READ_COUNT

    bool error_comb;
    bool& error_comb_func()
    {
        error_comb = (bool)protocol_error_reg
            || fifos[0].protocol_error_out()
            || fifos[1].protocol_error_out();
        return error_comb;
    }

public:
    void _assign()
    {
#define OUTPUT_MERGER_BIND_FIFO(number) \
        fifos[number].valid_in = _ASSIGN((bool)tx_valid_in()[number]); \
        fifos[number].data_in = _ASSIGN_COMB(tx_data_##number##_comb_func()); \
        fifos[number].keep_in = _ASSIGN_COMB(tx_keep_##number##_comb_func()); \
        fifos[number].sop_in = _ASSIGN((bool)tx_sop_in()[number]); \
        fifos[number].eop_in = _ASSIGN((bool)tx_eop_in()[number]); \
        fifos[number].read_count_in = _ASSIGN_COMB(read_count_##number##_comb_func()); \
        fifos[number].clear_in = _ASSIGN(false); \
        fifos[number].__inst_name = __inst_name + "/tx_fifo" + std::to_string(number); \
        fifos[number]._assign();
        OUTPUT_MERGER_FOR_EACH_STREAM(OUTPUT_MERGER_BIND_FIFO)
#undef OUTPUT_MERGER_BIND_FIFO

        tx_ready_out = _ASSIGN_COMB(tx_ready_comb_func());
        tx_almost_full_out = _ASSIGN_COMB(tx_almost_full_comb_func());
        tx_protocol_error_out = _ASSIGN_COMB(tx_fifo_error_comb_func());
        valid_out = _ASSIGN_COMB(output_valid_comb_func());
        data_out = _ASSIGN_COMB(output_data_comb_func());
        keep_out = _ASSIGN_COMB(output_keep_comb_func());
        sop_out = _ASSIGN_COMB(output_sop_comb_func());
        eop_out = _ASSIGN_COMB(output_eop_comb_func());
        protocol_error_out = _ASSIGN_COMB(error_comb_func());
    }

    void SMARTNIC_NETWORK_WORK_METHOD(bool reset)
    {
        size_t stream;
        if (reset) {
            rr_reg.clr();
            active_reg.clr();
            stream_reg.clr();
            gap_reg.clr();
            carry_valid_reg.clr();
            carry_offset_reg.clr();
            carry_data_reg.clr();
            carry_keep_reg.clr();
            carry_sop_reg.clr();
            carry_eop_reg.clr();
            protocol_error_reg.clr();
            for (stream = 0; stream < STREAMS; ++stream) {
                fifos[stream]._work(true);
            }
            return;
        }

        if ((bool)merge_result_comb_func()[RESULT_VALID] && ready_in()) {
            rr_reg._next = merge_result_comb_func().bits(
                RESULT_NEXT_RR + 2, RESULT_NEXT_RR);
            active_reg._next = (bool)merge_result_comb_func()[
                RESULT_NEXT_ACTIVE];
            stream_reg._next = merge_result_comb_func().bits(
                RESULT_NEXT_STREAM + 2,
                RESULT_NEXT_STREAM);
            gap_reg._next = merge_result_comb_func().bits(
                RESULT_NEXT_GAP + GAP_BITS - 1,
                RESULT_NEXT_GAP);
            carry_valid_reg._next = (bool)merge_result_comb_func()[
                RESULT_NEXT_CARRY_VALID];
            carry_offset_reg._next = merge_result_comb_func().bits(
                RESULT_NEXT_CARRY_OFFSET + OFFSET_BITS - 1,
                RESULT_NEXT_CARRY_OFFSET);
            carry_data_reg._next = merge_result_comb_func().bits(
                RESULT_NEXT_CARRY_DATA + LANE_WIDTH - 1,
                RESULT_NEXT_CARRY_DATA);
            carry_keep_reg._next = merge_result_comb_func().bits(
                RESULT_NEXT_CARRY_KEEP + LANE_BYTES - 1,
                RESULT_NEXT_CARRY_KEEP);
            carry_sop_reg._next = (bool)merge_result_comb_func()[
                RESULT_NEXT_CARRY_SOP];
            carry_eop_reg._next = (bool)merge_result_comb_func()[
                RESULT_NEXT_CARRY_EOP];
            if ((bool)merge_result_comb_func()[RESULT_ERROR]) {
                protocol_error_reg._next = 1;
            }
        }
        for (stream = 0; stream < STREAMS; ++stream) {
            fifos[stream]._work(false);
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        size_t stream;
        for (stream = 0; stream < STREAMS; ++stream) {
            fifos[stream]._strobe();
        }
        rr_reg.strobe();
        active_reg.strobe();
        stream_reg.strobe();
        gap_reg.strobe();
        carry_valid_reg.strobe();
        carry_offset_reg.strobe();
        carry_data_reg.strobe();
        carry_keep_reg.strobe();
        carry_sop_reg.strobe();
        carry_eop_reg.strobe();
        protocol_error_reg.strobe();
    }
#endif

    void _strobe()
    {
        size_t stream;
        for (stream = 0; stream < STREAMS; ++stream) fifos[stream]._strobe();
        rr_reg.strobe(); active_reg.strobe(); stream_reg.strobe();
        gap_reg.strobe(); carry_valid_reg.strobe(); carry_offset_reg.strobe();
        carry_data_reg.strobe(); carry_keep_reg.strobe(); carry_sop_reg.strobe();
        carry_eop_reg.strobe(); protocol_error_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class OutputMerger<64, 2048, 12>;

#undef OUTPUT_MERGER_FOR_EACH_STREAM
