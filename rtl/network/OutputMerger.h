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
    static constexpr size_t WINDOW_WORDS = 2;
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t OUTPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t OUTPUT_BYTES = STREAMS * LANE_BYTES;
    static constexpr size_t MAX_LANE_WIDTH = 64;
    static constexpr size_t MAX_LANE_BYTES = MAX_LANE_WIDTH / 8;
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
    static constexpr size_t RESULT_NEXT_ACTIVE = RESULT_NEXT_RR + 1;
    static constexpr size_t RESULT_NEXT_STREAM = RESULT_NEXT_ACTIVE + 1;
    static constexpr size_t RESULT_NEXT_GAP = RESULT_NEXT_STREAM + 1;
    static constexpr size_t RESULT_NEXT_CARRY_VALID =
        RESULT_NEXT_GAP + GAP_BITS;
    static constexpr size_t RESULT_NEXT_CARRY_DATA =
        RESULT_NEXT_CARRY_VALID + 1;
    static constexpr size_t RESULT_NEXT_CARRY_KEEP =
        RESULT_NEXT_CARRY_DATA + LANE_WIDTH;
    static constexpr size_t RESULT_NEXT_CARRY_SOP =
        RESULT_NEXT_CARRY_KEEP + LANE_BYTES;
    static constexpr size_t RESULT_NEXT_CARRY_EOP =
        RESULT_NEXT_CARRY_SOP + 1;
    static constexpr size_t RESULT_ERROR = RESULT_NEXT_CARRY_EOP + 1;
    static constexpr size_t RESULT_BITS = RESULT_ERROR + 1;

    TxFifo<LANE_WIDTH, FIFO_WORDS> fifos[STREAMS];

    reg<u1> rr_reg;
    reg<u1> active_reg;
    reg<u1> stream_reg;
    reg<u<GAP_BITS>> gap_reg;
    reg<u1> carry_valid_reg;
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
        size_t piece;
        uint8_t rr;
        uint8_t selected;
        uint8_t slot;
        uint8_t slot0;
        uint8_t slot1;
        uint8_t gap;
        uint8_t position;
        uint8_t space;
        uint8_t bytes;
        uint8_t take;
        uint8_t keep_mask;
        uint64_t data_mask;
        bool active;
        bool loaded;
        bool found;
        bool any_data;
        bool error;
        bool blocked;
        bool expect_sop;
        bool available0;
        bool available1;
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
        logic<OUTPUT_BITS> output_data;
        logic<OUTPUT_BYTES> output_keep;
        logic<OUTPUT_BYTES> output_sop;
        logic<OUTPUT_BYTES> output_eop;

        merge_result_comb = 0;
        merge_read_counts_comb = 0;
        read_counts = 0;
        output_data = 0;
        output_keep = 0;
        output_sop = 0;
        output_eop = 0;
        all_data = fifo_data_comb_func();
        all_keep = fifo_keep_comb_func();
        all_sop = fifo_sop_comb_func();
        all_eop = fifo_eop_comb_func();
        all_valid = fifo_valid_comb_func();
        rr = (uint8_t)rr_reg;
        selected = (uint8_t)stream_reg;
        gap = (uint8_t)gap_reg;
        position = 0;
        active = active_reg;
        expect_sop = !active;
        loaded = carry_valid_reg;
        word_data = carry_data_reg;
        word_keep = carry_keep_reg;
        word_sop = carry_sop_reg;
        word_eop = carry_eop_reg;
        any_data = false;
        error = false;
        blocked = false;
        slot = 0;
        slot0 = 0;
        slot1 = 0;
        space = 0;
        bytes = 0;
        take = 0;
        keep_mask = 0;
        data_mask = 0;
        found = false;
        available0 = false;
        available1 = false;

        // At most three packet-word fragments can contribute to one 16-byte
        // aggregate word: an old carry, two aligned words, or a post-IPG
        // prefix.  Keeping this loop at three prevents a byte-serial path.
        for (piece = 0; piece < 3; ++piece) {
            if (!blocked && position < OUTPUT_BYTES) {
                if (gap != 0) {
                    space = OUTPUT_BYTES - position;
                    take = gap < space ? gap : space;
                    position += take;
                    gap -= take;
                }

                if (gap == 0 && position < OUTPUT_BYTES) {
                    if (!active) {
                        slot0 = (uint8_t)(uint64_t)read_counts.bits(3, 0);
                        slot1 = (uint8_t)(uint64_t)read_counts.bits(7, 4);
                        available0 = slot0 < WINDOW_WORDS
                            && (slot0 == 0 ? (bool)all_valid[0]
                                : (bool)all_valid[1]);
                        available1 = slot1 < WINDOW_WORDS
                            && (slot1 == 0 ? (bool)all_valid[2]
                                : (bool)all_valid[3]);
                        found = available0 || available1;
                        if (rr == 0) selected = available0 ? 0 : 1;
                        else selected = available1 ? 1 : 0;
                        if (!found) blocked = true;
                        else {
                            active = true;
                            expect_sop = true;
                            loaded = false;
                        }
                    }

                    if (!blocked && !loaded) {
                        slot = selected == 0
                            ? (uint8_t)(uint64_t)read_counts.bits(3, 0)
                            : (uint8_t)(uint64_t)read_counts.bits(7, 4);
                        if (slot >= WINDOW_WORDS
                            || (selected == 0
                                ? (slot == 0 ? !(bool)all_valid[0]
                                    : !(bool)all_valid[1])
                                : (slot == 0 ? !(bool)all_valid[2]
                                    : !(bool)all_valid[3]))) {
                            blocked = true;
                        }
                        else {
                            if (selected == 0 && slot == 0) {
                                word_data = all_data.bits(63, 0);
                                word_keep = all_keep.bits(7, 0);
                                word_sop = all_sop[0];
                                word_eop = all_eop[0];
                            }
                            else if (selected == 0) {
                                word_data = all_data.bits(127, 64);
                                word_keep = all_keep.bits(15, 8);
                                word_sop = all_sop[1];
                                word_eop = all_eop[1];
                            }
                            else if (slot == 0) {
                                word_data = all_data.bits(191, 128);
                                word_keep = all_keep.bits(23, 16);
                                word_sop = all_sop[2];
                                word_eop = all_eop[2];
                            }
                            else {
                                word_data = all_data.bits(255, 192);
                                word_keep = all_keep.bits(31, 24);
                                word_sop = all_sop[3];
                                word_eop = all_eop[3];
                            }
                            if (selected == 0)
                                read_counts.bits(3, 0) = slot + 1;
                            else
                                read_counts.bits(7, 4) = slot + 1;
                            loaded = true;
                            if (word_sop != expect_sop) error = true;
                            expect_sop = false;
                        }
                    }

                    if (!blocked && loaded) {
                        bytes = 0;
                        if (word_keep[7]) bytes = 8;
                        else if (word_keep[6]) bytes = 7;
                        else if (word_keep[5]) bytes = 6;
                        else if (word_keep[4]) bytes = 5;
                        else if (word_keep[3]) bytes = 4;
                        else if (word_keep[2]) bytes = 3;
                        else if (word_keep[1]) bytes = 2;
                        else if (word_keep[0]) bytes = 1;
                        if (bytes == 0) {
                            error = true;
                            blocked = true;
                        }
                        else {
                            space = OUTPUT_BYTES - position;
                            take = bytes < space ? bytes : space;
                            data_mask = take == LANE_BYTES ? ~uint64_t(0)
                                : ((uint64_t(1) << (take * 8)) - 1);
                            keep_mask = (1u << take) - 1;
                            output_data = output_data
                                | ((logic<OUTPUT_BITS>)(word_data & data_mask)
                                    << (position * 8));
                            output_keep = output_keep
                                | (logic<OUTPUT_BYTES>)(keep_mask << position);
                            if (word_sop) output_sop[position] = 1;
                            any_data = true;
                            position += take;

                            if (take < bytes) {
                                word_data = word_data >> (take * 8);
                                word_keep = word_keep >> take;
                                word_sop = false;
                                loaded = true;
                            }
                            else {
                                loaded = false;
                                if (word_eop) {
                                    output_eop[position - 1] = 1;
                                    active = false;
                                    expect_sop = true;
                                    gap = MIN_IPG_BYTES;
                                    rr = (selected + 1) & (STREAMS - 1);

                                    // Consume as much of the mandatory gap as
                                    // fits in this aggregate word immediately.
                                    // Otherwise an EOP handled by the final
                                    // piece would add an unnecessary whole
                                    // output word to the inter-packet gap.
                                    space = OUTPUT_BYTES - position;
                                    take = gap < space ? gap : space;
                                    position += take;
                                    gap -= take;
                                }
                            }
                        }
                    }
                }
            }
        }

        merge_read_counts_comb = read_counts;
        merge_result_comb.bits(RESULT_DATA + OUTPUT_BITS - 1,
            RESULT_DATA) = output_data;
        merge_result_comb.bits(RESULT_KEEP + OUTPUT_BYTES - 1,
            RESULT_KEEP) = output_keep;
        merge_result_comb.bits(RESULT_SOP + OUTPUT_BYTES - 1,
            RESULT_SOP) = output_sop;
        merge_result_comb.bits(RESULT_EOP + OUTPUT_BYTES - 1,
            RESULT_EOP) = output_eop;
        merge_result_comb[RESULT_VALID] = any_data;
        merge_result_comb[RESULT_NEXT_RR] = rr;
        merge_result_comb[RESULT_NEXT_ACTIVE] = active;
        merge_result_comb[RESULT_NEXT_STREAM] = selected;
        merge_result_comb.bits(RESULT_NEXT_GAP + GAP_BITS - 1,
            RESULT_NEXT_GAP) = gap;
        merge_result_comb[RESULT_NEXT_CARRY_VALID] = loaded;
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
            rr_reg._next = (bool)merge_result_comb_func()[RESULT_NEXT_RR];
            active_reg._next = (bool)merge_result_comb_func()[
                RESULT_NEXT_ACTIVE];
            stream_reg._next = (bool)merge_result_comb_func()[
                RESULT_NEXT_STREAM];
            gap_reg._next = merge_result_comb_func().bits(
                RESULT_NEXT_GAP + GAP_BITS - 1,
                RESULT_NEXT_GAP);
            carry_valid_reg._next = (bool)merge_result_comb_func()[
                RESULT_NEXT_CARRY_VALID];
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
        gap_reg.strobe(); carry_valid_reg.strobe();
        carry_data_reg.strobe(); carry_keep_reg.strobe(); carry_sop_reg.strobe();
        carry_eop_reg.strobe(); protocol_error_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class OutputMerger<64, 2048, 12>;

#undef OUTPUT_MERGER_FOR_EACH_STREAM
