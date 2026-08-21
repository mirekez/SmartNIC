#pragma once

// Merge two packet-committed transmit FIFOs onto one 128-bit Ethernet stream.
//
// The implementation has two deliberately registered stages.  The scheduler
// removes at most two 64-bit words from one FIFO and records that packet-only
// batch.  A separate wire-time queue appends the batch and, at EOP, twelve
// invalid byte slots for the Ethernet IPG.  Keeping FIFO dequeue independent
// from byte alignment prevents the formatter from feeding a long combinational
// path back into both FIFO BRAM read addresses.

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

    static_assert(LANE_WIDTH == 64,
        "OutputMerger supports two 64-bit 10GbE MAC lanes");

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
    static constexpr size_t BATCH_BYTES = OUTPUT_BYTES;
    static constexpr size_t TIME_QUEUE_BYTES = 64;
    static constexpr size_t TIME_QUEUE_BITS = TIME_QUEUE_BYTES * 8;
    static constexpr size_t TIME_COUNT_BITS =
        clog2(TIME_QUEUE_BYTES + 1);
    static constexpr size_t BATCH_COUNT_BITS = clog2(BATCH_BYTES + 1);

    // Packed scheduler result.  It is registered before it reaches the
    // byte/IPG formatter.
    static constexpr size_t SCHED_VALID = 0;
    static constexpr size_t SCHED_SELECTED = SCHED_VALID + 1;
    static constexpr size_t SCHED_READ_COUNT = SCHED_SELECTED + 1;
    static constexpr size_t SCHED_DATA = SCHED_READ_COUNT + 2;
    static constexpr size_t SCHED_KEEP = SCHED_DATA + OUTPUT_BITS;
    static constexpr size_t SCHED_SOP = SCHED_KEEP + OUTPUT_BYTES;
    static constexpr size_t SCHED_EOP = SCHED_SOP + OUTPUT_BYTES;
    static constexpr size_t SCHED_BYTES = SCHED_EOP + OUTPUT_BYTES;
    static constexpr size_t SCHED_NEXT_RR =
        SCHED_BYTES + BATCH_COUNT_BITS;
    static constexpr size_t SCHED_NEXT_ACTIVE = SCHED_NEXT_RR + 1;
    static constexpr size_t SCHED_NEXT_STREAM = SCHED_NEXT_ACTIVE + 1;
    static constexpr size_t SCHED_ERROR = SCHED_NEXT_STREAM + 1;
    static constexpr size_t SCHED_BITS = SCHED_ERROR + 1;

    TxFifo<LANE_WIDTH, FIFO_WORDS> fifos[STREAMS];

    reg<u1> scheduler_rr_reg;
    reg<u1> scheduler_active_reg;
    reg<u1> scheduler_stream_reg;

    reg<u1> batch_valid_reg;
    reg<logic<OUTPUT_BITS>> batch_data_reg;
    reg<logic<OUTPUT_BYTES>> batch_keep_reg;
    reg<logic<OUTPUT_BYTES>> batch_sop_reg;
    reg<logic<OUTPUT_BYTES>> batch_eop_reg;
    reg<u<BATCH_COUNT_BITS>> batch_bytes_reg;

    // Each position is a wire byte-time.  Invalid positions are Ethernet IPG.
    reg<logic<TIME_QUEUE_BITS>> time_data_reg;
    reg<logic<TIME_QUEUE_BYTES>> time_keep_reg;
    reg<logic<TIME_QUEUE_BYTES>> time_sop_reg;
    reg<logic<TIME_QUEUE_BYTES>> time_eop_reg;
    reg<u<TIME_COUNT_BITS>> time_count_reg;
    reg<u1> protocol_error_reg;

    logic<STREAMS> tx_ready_comb;
    logic<STREAMS> tx_almost_full_comb;
    logic<STREAMS> tx_fifo_error_comb;

#define OUTPUT_MERGER_DECLARE_INPUT(number) \
    logic<LANE_WIDTH> tx_data_##number##_comb; \
    logic<LANE_WIDTH>& tx_data_##number##_comb_func() \
    { \
        size_t bit; \
        for (bit = 0; bit < LANE_WIDTH; ++bit) \
            tx_data_##number##_comb[bit] = \
                tx_data_in()[number * LANE_WIDTH + bit]; \
        return tx_data_##number##_comb; \
    } \
    logic<LANE_BYTES> tx_keep_##number##_comb; \
    logic<LANE_BYTES>& tx_keep_##number##_comb_func() \
    { \
        size_t byte; \
        for (byte = 0; byte < LANE_BYTES; ++byte) \
            tx_keep_##number##_comb[byte] = \
                tx_keep_in()[number * LANE_BYTES + byte]; \
        return tx_keep_##number##_comb; \
    }
    OUTPUT_MERGER_FOR_EACH_STREAM(OUTPUT_MERGER_DECLARE_INPUT)
#undef OUTPUT_MERGER_DECLARE_INPUT

    logic<STREAMS>& tx_ready_comb_func()
    {
        tx_ready_comb = 0;
        tx_ready_comb[0] = fifos[0].ready_out();
        tx_ready_comb[1] = fifos[1].ready_out();
        return tx_ready_comb;
    }

    logic<STREAMS>& tx_almost_full_comb_func()
    {
        tx_almost_full_comb = 0;
        tx_almost_full_comb[0] = fifos[0].almost_full_out();
        tx_almost_full_comb[1] = fifos[1].almost_full_out();
        return tx_almost_full_comb;
    }

    logic<STREAMS>& tx_fifo_error_comb_func()
    {
        tx_fifo_error_comb = 0;
        tx_fifo_error_comb[0] = fifos[0].protocol_error_out();
        tx_fifo_error_comb[1] = fifos[1].protocol_error_out();
        return tx_fifo_error_comb;
    }

    static uint32_t prefix_bytes(logic<LANE_BYTES> keep)
    {
        uint32_t count;
        uint32_t byte;
        count = 0;
        for (byte = 0; byte < LANE_BYTES; ++byte) {
            if ((bool)keep[byte]) ++count;
        }
        return count;
    }

    static bool prefix_keep_valid(logic<LANE_BYTES> keep)
    {
        uint32_t byte;
        bool seen_zero;
        bool malformed;
        seen_zero = false;
        malformed = false;
        for (byte = 0; byte < LANE_BYTES; ++byte) {
            if (!(bool)keep[byte]) seen_zero = true;
            else if (seen_zero) malformed = true;
        }
        return !malformed && (uint64_t)keep != 0;
    }

    _LAZY_COMB(scheduler_result_comb, logic<SCHED_BITS>)
        uint32_t selected;
        uint32_t read_count;
        uint32_t bytes0;
        uint32_t bytes1;
        uint32_t total_bytes;
        bool active;
        bool valid0;
        bool valid1;
        bool eop0;
        bool eop1;
        bool sop0;
        bool sop1;
        bool error;
        logic<2 * LANE_WIDTH> words_data;
        logic<2 * LANE_BYTES> words_keep;
        logic<2> words_sop;
        logic<2> words_eop;
        logic<2> words_valid;
        logic<OUTPUT_BITS> batch_data;
        logic<OUTPUT_BYTES> batch_keep;
        logic<OUTPUT_BYTES> batch_sop;
        logic<OUTPUT_BYTES> batch_eop;

        scheduler_result_comb = 0;
        selected = (uint32_t)scheduler_stream_reg;
        active = (bool)scheduler_active_reg;
        if (!active) {
            if ((bool)scheduler_rr_reg) {
                selected = (bool)fifos[1].valid_out()[0] ? 1 : 0;
            }
            else {
                selected = (bool)fifos[0].valid_out()[0] ? 0 : 1;
            }
        }

        if (selected == 0) {
            words_data = fifos[0].data_out();
            words_keep = fifos[0].keep_out();
            words_sop = fifos[0].sop_out();
            words_eop = fifos[0].eop_out();
            words_valid = fifos[0].valid_out();
        }
        else {
            words_data = fifos[1].data_out();
            words_keep = fifos[1].keep_out();
            words_sop = fifos[1].sop_out();
            words_eop = fifos[1].eop_out();
            words_valid = fifos[1].valid_out();
        }

        valid0 = (bool)words_valid[0];
        valid1 = (bool)words_valid[1];
        eop0 = (bool)words_eop[0];
        eop1 = (bool)words_eop[1];
        sop0 = (bool)words_sop[0];
        sop1 = (bool)words_sop[1];
        read_count = 0;
        bytes0 = 0;
        bytes1 = 0;
        total_bytes = 0;
        error = false;
        batch_data = 0;
        batch_keep = 0;
        batch_sop = 0;
        batch_eop = 0;

        if (valid0) {
            read_count = 1;
            bytes0 = prefix_bytes(words_keep.bits(LANE_BYTES - 1, 0));
            if (!prefix_keep_valid(words_keep.bits(LANE_BYTES - 1, 0)))
                error = true;
            if (sop0 == active) error = true;
            if (!eop0 && bytes0 != LANE_BYTES) error = true;

            batch_data.bits(LANE_WIDTH - 1, 0) =
                words_data.bits(LANE_WIDTH - 1, 0);
            batch_keep.bits(LANE_BYTES - 1, 0) =
                words_keep.bits(LANE_BYTES - 1, 0);
            if (sop0) batch_sop[0] = 1;
            total_bytes = bytes0;

            if (!eop0) {
                if (!valid1) {
                    error = true;
                }
                else {
                    read_count = 2;
                    // Literal bounds avoid leaving a parameter expression in
                    // the generated indexed part-select.
                    bytes1 = prefix_bytes(words_keep.bits(15, 8));
                    if (!prefix_keep_valid(words_keep.bits(15, 8)))
                        error = true;
                    if (sop1) error = true;
                    if (!eop1 && bytes1 != LANE_BYTES) error = true;
                    batch_data.bits(OUTPUT_BITS - 1, LANE_WIDTH) =
                        words_data.bits(127, 64);
                    batch_keep.bits(OUTPUT_BYTES - 1, LANE_BYTES) =
                        words_keep.bits(15, 8);
                    total_bytes += bytes1;
                }
            }

            if ((eop0 || (read_count == 2 && eop1))
                && total_bytes != 0) {
                batch_eop[total_bytes - 1] = 1;
            }
            scheduler_result_comb[SCHED_VALID] = 1;
            scheduler_result_comb[SCHED_SELECTED] = selected;
            scheduler_result_comb.bits(SCHED_READ_COUNT + 1,
                SCHED_READ_COUNT) = read_count;
            scheduler_result_comb.bits(SCHED_DATA + OUTPUT_BITS - 1,
                SCHED_DATA) = batch_data;
            scheduler_result_comb.bits(SCHED_KEEP + OUTPUT_BYTES - 1,
                SCHED_KEEP) = batch_keep;
            scheduler_result_comb.bits(SCHED_SOP + OUTPUT_BYTES - 1,
                SCHED_SOP) = batch_sop;
            scheduler_result_comb.bits(SCHED_EOP + OUTPUT_BYTES - 1,
                SCHED_EOP) = batch_eop;
            scheduler_result_comb.bits(SCHED_BYTES + BATCH_COUNT_BITS - 1,
                SCHED_BYTES) = total_bytes;

            if (eop0 || (read_count == 2 && eop1)) {
                scheduler_result_comb[SCHED_NEXT_RR] = selected ^ 1;
                scheduler_result_comb[SCHED_NEXT_ACTIVE] = 0;
                scheduler_result_comb[SCHED_NEXT_STREAM] = selected;
            }
            else {
                scheduler_result_comb[SCHED_NEXT_RR] =
                    (bool)scheduler_rr_reg;
                scheduler_result_comb[SCHED_NEXT_ACTIVE] = 1;
                scheduler_result_comb[SCHED_NEXT_STREAM] = selected;
            }
        }
        else {
            scheduler_result_comb[SCHED_NEXT_RR] =
                (bool)scheduler_rr_reg;
            scheduler_result_comb[SCHED_NEXT_ACTIVE] = active;
            scheduler_result_comb[SCHED_NEXT_STREAM] = selected;
        }
        scheduler_result_comb[SCHED_ERROR] = error;
        return scheduler_result_comb;
    }

    bool output_valid_comb;
    bool& output_valid_comb_func()
    {
        uint32_t count;
        count = (uint32_t)time_count_reg;
        // Do not expose a short aggregate in the middle of a frame.  At a
        // packet boundary it is held long enough for the next packet and its
        // exact IPG to be appended, or flushed when no work remains.
        output_valid_comb = count != 0
            && (count >= OUTPUT_BYTES
                || (!(bool)batch_valid_reg
                    && !(bool)scheduler_active_reg));
        return output_valid_comb;
    }

    bool output_drain_comb;
    bool& output_drain_comb_func()
    {
        output_drain_comb = output_valid_comb_func() && ready_in();
        return output_drain_comb;
    }

    uint32_t queue_count_after_drain()
    {
        uint32_t count;
        count = (uint32_t)time_count_reg;
        if (output_drain_comb_func()) {
            count = count > OUTPUT_BYTES ? count - OUTPUT_BYTES : 0;
        }
        return count;
    }

    bool queue_append_comb;
    bool& queue_append_comb_func()
    {
        uint32_t span;
        span = (uint32_t)batch_bytes_reg;
        if ((uint64_t)batch_eop_reg != 0) span += MIN_IPG_BYTES;
        queue_append_comb = (bool)batch_valid_reg
            && queue_count_after_drain() + span <= TIME_QUEUE_BYTES;
        return queue_append_comb;
    }

    bool batch_slot_ready_comb;
    bool& batch_slot_ready_comb_func()
    {
        batch_slot_ready_comb = !(bool)batch_valid_reg
            || queue_append_comb_func();
        return batch_slot_ready_comb;
    }

#define OUTPUT_MERGER_DECLARE_READ_COUNT(number) \
    u<4> read_count_##number##_comb; \
    u<4>& read_count_##number##_comb_func() \
    { \
        read_count_##number##_comb = 0; \
        if (batch_slot_ready_comb_func() \
            && (bool)scheduler_result_comb_func()[SCHED_VALID] \
            && ((bool)scheduler_result_comb_func()[SCHED_SELECTED] \
                == (number != 0))) { \
            read_count_##number##_comb = scheduler_result_comb_func().bits( \
                SCHED_READ_COUNT + 1, SCHED_READ_COUNT); \
        } \
        return read_count_##number##_comb; \
    }
    OUTPUT_MERGER_FOR_EACH_STREAM(OUTPUT_MERGER_DECLARE_READ_COUNT)
#undef OUTPUT_MERGER_DECLARE_READ_COUNT

    logic<OUTPUT_BITS> output_data_comb;
    logic<OUTPUT_BITS>& output_data_comb_func()
    {
        output_data_comb = time_data_reg.bits(OUTPUT_BITS - 1, 0);
        return output_data_comb;
    }

    logic<OUTPUT_BYTES> output_keep_comb;
    logic<OUTPUT_BYTES>& output_keep_comb_func()
    {
        output_keep_comb = time_keep_reg.bits(OUTPUT_BYTES - 1, 0);
        return output_keep_comb;
    }

    logic<OUTPUT_BYTES> output_sop_comb;
    logic<OUTPUT_BYTES>& output_sop_comb_func()
    {
        output_sop_comb = time_sop_reg.bits(OUTPUT_BYTES - 1, 0);
        return output_sop_comb;
    }

    logic<OUTPUT_BYTES> output_eop_comb;
    logic<OUTPUT_BYTES>& output_eop_comb_func()
    {
        output_eop_comb = time_eop_reg.bits(OUTPUT_BYTES - 1, 0);
        return output_eop_comb;
    }

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
        fifos[number].read_count_in = \
            _ASSIGN_COMB(read_count_##number##_comb_func()); \
        fifos[number].clear_in = _ASSIGN(false); \
        fifos[number].__inst_name = __inst_name + "/tx_fifo" \
            + std::to_string(number); \
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
        uint32_t count;
        uint32_t append_position;
        uint32_t append_span;
        logic<TIME_QUEUE_BITS> queue_data;
        logic<TIME_QUEUE_BYTES> queue_keep;
        logic<TIME_QUEUE_BYTES> queue_sop;
        logic<TIME_QUEUE_BYTES> queue_eop;
        logic<SCHED_BITS> candidate;

        for (stream = 0; stream < STREAMS; ++stream) {
            fifos[stream]._work(reset);
        }

        if (reset) {
            scheduler_rr_reg.clr();
            scheduler_active_reg.clr();
            scheduler_stream_reg.clr();
            batch_valid_reg.clr();
            batch_data_reg.clr();
            batch_keep_reg.clr();
            batch_sop_reg.clr();
            batch_eop_reg.clr();
            batch_bytes_reg.clr();
            time_data_reg.clr();
            time_keep_reg.clr();
            time_sop_reg.clr();
            time_eop_reg.clr();
            time_count_reg.clr();
            protocol_error_reg.clr();
            return;
        }

        queue_data = time_data_reg;
        queue_keep = time_keep_reg;
        queue_sop = time_sop_reg;
        queue_eop = time_eop_reg;
        count = (uint32_t)time_count_reg;

        if (output_drain_comb_func()) {
            queue_data = queue_data >> OUTPUT_BITS;
            queue_keep = queue_keep >> OUTPUT_BYTES;
            queue_sop = queue_sop >> OUTPUT_BYTES;
            queue_eop = queue_eop >> OUTPUT_BYTES;
            count = count > OUTPUT_BYTES ? count - OUTPUT_BYTES : 0;
        }

        if (queue_append_comb_func()) {
            append_position = count;
            append_span = (uint32_t)batch_bytes_reg;
            queue_data = queue_data
                | (logic<TIME_QUEUE_BITS>(batch_data_reg)
                    << (append_position * 8));
            queue_keep = queue_keep
                | (logic<TIME_QUEUE_BYTES>(batch_keep_reg)
                    << append_position);
            queue_sop = queue_sop
                | (logic<TIME_QUEUE_BYTES>(batch_sop_reg)
                    << append_position);
            queue_eop = queue_eop
                | (logic<TIME_QUEUE_BYTES>(batch_eop_reg)
                    << append_position);
            if ((uint64_t)batch_eop_reg != 0)
                append_span += MIN_IPG_BYTES;
            count += append_span;
        }

        time_data_reg._next = queue_data;
        time_keep_reg._next = queue_keep;
        time_sop_reg._next = queue_sop;
        time_eop_reg._next = queue_eop;
        time_count_reg._next = count;

        if (batch_slot_ready_comb_func()) {
            candidate = scheduler_result_comb_func();
            if ((bool)candidate[SCHED_VALID]) {
                batch_valid_reg._next = 1;
                batch_data_reg._next = candidate.bits(
                    SCHED_DATA + OUTPUT_BITS - 1, SCHED_DATA);
                batch_keep_reg._next = candidate.bits(
                    SCHED_KEEP + OUTPUT_BYTES - 1, SCHED_KEEP);
                batch_sop_reg._next = candidate.bits(
                    SCHED_SOP + OUTPUT_BYTES - 1, SCHED_SOP);
                batch_eop_reg._next = candidate.bits(
                    SCHED_EOP + OUTPUT_BYTES - 1, SCHED_EOP);
                batch_bytes_reg._next = candidate.bits(
                    SCHED_BYTES + BATCH_COUNT_BITS - 1, SCHED_BYTES);
                scheduler_rr_reg._next =
                    (bool)candidate[SCHED_NEXT_RR];
                scheduler_active_reg._next =
                    (bool)candidate[SCHED_NEXT_ACTIVE];
                scheduler_stream_reg._next =
                    (bool)candidate[SCHED_NEXT_STREAM];
                if ((bool)candidate[SCHED_ERROR])
                    protocol_error_reg._next = 1;
            }
            else {
                batch_valid_reg._next = 0;
            }
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        size_t stream;
        for (stream = 0; stream < STREAMS; ++stream)
            fifos[stream]._strobe();
        scheduler_rr_reg.strobe();
        scheduler_active_reg.strobe();
        scheduler_stream_reg.strobe();
        batch_valid_reg.strobe();
        batch_data_reg.strobe();
        batch_keep_reg.strobe();
        batch_sop_reg.strobe();
        batch_eop_reg.strobe();
        batch_bytes_reg.strobe();
        time_data_reg.strobe();
        time_keep_reg.strobe();
        time_sop_reg.strobe();
        time_eop_reg.strobe();
        time_count_reg.strobe();
        protocol_error_reg.strobe();
    }
#endif

    void _strobe()
    {
        size_t stream;
        for (stream = 0; stream < STREAMS; ++stream)
            fifos[stream]._strobe();
        scheduler_rr_reg.strobe(); scheduler_active_reg.strobe();
        scheduler_stream_reg.strobe(); batch_valid_reg.strobe();
        batch_data_reg.strobe(); batch_keep_reg.strobe();
        batch_sop_reg.strobe(); batch_eop_reg.strobe();
        batch_bytes_reg.strobe(); time_data_reg.strobe();
        time_keep_reg.strobe(); time_sop_reg.strobe();
        time_eop_reg.strobe(); time_count_reg.strobe();
        protocol_error_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class OutputMerger<64, 2048, 12>;

#undef OUTPUT_MERGER_FOR_EACH_STREAM
