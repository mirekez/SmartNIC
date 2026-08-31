#pragma once

// Two independent packet-committed TX FIFOs feeding two 64-bit MAC ports.
// Stream N always leaves on MAC lane N; streams are never round-robin merged.
// A shared valid/ready encloses the aggregate beat while per-byte keep/SOP/EOP
// identify activity on each physical lane. Each lane enforces its own IPG.

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
    static constexpr size_t LANE_BYTES = LANE_WIDTH / 8;
    static constexpr size_t OUTPUT_BITS = STREAMS * LANE_WIDTH;
    static constexpr size_t OUTPUT_BYTES = STREAMS * LANE_BYTES;
    static constexpr size_t IPG_CYCLES =
        (MIN_IPG_BYTES + LANE_BYTES - 1) / LANE_BYTES;
    // A zero delay is used when this AXI stream feeds an Ethernet MAC: the
    // MAC owns FCS/IFG generation and advertises any required pause through
    // ready_in.  Keep a real one-bit register in that configuration because
    // zero-width C++/SV integers are not portable.
    static constexpr size_t IPG_COUNT_BITS = IPG_CYCLES == 0
        ? 1 : clog2(IPG_CYCLES + 1);

    static_assert(LANE_WIDTH == 64,
        "OutputMerger supports two 64-bit 10GbE MAC ports");

    _PORT(logic<STREAMS>) tx_valid_in;
    _PORT(logic<STREAMS * LANE_WIDTH>) tx_data_in;
    _PORT(logic<STREAMS * LANE_BYTES>) tx_keep_in;
    _PORT(logic<STREAMS>) tx_sop_in;
    _PORT(logic<STREAMS>) tx_eop_in;
    _PORT(logic<STREAMS>) tx_ready_out;
    _PORT(logic<STREAMS>) tx_almost_full_out;
    _PORT(logic<STREAMS>) tx_protocol_error_out;

    // Each 64-bit slice is one independent MAC port. valid_out is asserted
    // when at least one slice contains data; inactive slices have keep == 0.
    _PORT(bool) valid_out;
    _PORT(logic<OUTPUT_BITS>) data_out;
    _PORT(logic<OUTPUT_BYTES>) keep_out;
    _PORT(logic<OUTPUT_BYTES>) sop_out;
    _PORT(logic<OUTPUT_BYTES>) eop_out;
    // The two MACs are independent AXI streams.  A pause or IFG on one port
    // must never prevent the other port from draining its own TxFifo.
    _PORT(logic<STREAMS>) ready_in;
    _PORT(bool) protocol_error_out;

private:
    TxFifo<LANE_WIDTH, FIFO_WORDS> fifos[STREAMS];
    reg<u<IPG_COUNT_BITS>> ipg_cycles_reg[STREAMS];

#define OUTPUT_MERGER_DECLARE_INPUT(number) \
    logic<LANE_WIDTH> tx_data_##number##_comb; \
    logic<LANE_WIDTH>& tx_data_##number##_comb_func() \
    { \
        tx_data_##number##_comb = tx_data_in().bits( \
            number * LANE_WIDTH + LANE_WIDTH - 1, number * LANE_WIDTH); \
        return tx_data_##number##_comb; \
    } \
    logic<LANE_BYTES> tx_keep_##number##_comb; \
    logic<LANE_BYTES>& tx_keep_##number##_comb_func() \
    { \
        tx_keep_##number##_comb = tx_keep_in().bits( \
            number * LANE_BYTES + LANE_BYTES - 1, number * LANE_BYTES); \
        return tx_keep_##number##_comb; \
    }
    OUTPUT_MERGER_FOR_EACH_STREAM(OUTPUT_MERGER_DECLARE_INPUT)
#undef OUTPUT_MERGER_DECLARE_INPUT

    _LAZY_COMB(lane_valid_comb, logic<STREAMS>)
        size_t stream;
        lane_valid_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            lane_valid_comb[stream] = (uint32_t)ipg_cycles_reg[stream] == 0
                && (bool)fifos[stream].valid_out()[0];
        }
        return lane_valid_comb;
    }

    bool output_valid_comb;
    bool& output_valid_comb_func()
    {
        output_valid_comb = (uint64_t)lane_valid_comb_func() != 0;
        return output_valid_comb;
    }

    logic<OUTPUT_BITS> output_data_comb;
    logic<OUTPUT_BITS>& output_data_comb_func()
    {
        size_t stream;
        size_t bit;
        output_data_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            if ((bool)lane_valid_comb_func()[stream]) {
                for (bit = 0; bit < LANE_WIDTH; ++bit) {
                    output_data_comb[stream * LANE_WIDTH + bit] =
                        fifos[stream].data_out()[bit];
                }
            }
        }
        return output_data_comb;
    }

    logic<OUTPUT_BYTES> output_keep_comb;
    logic<OUTPUT_BYTES>& output_keep_comb_func()
    {
        size_t stream;
        size_t byte;
        output_keep_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            if ((bool)lane_valid_comb_func()[stream]) {
                for (byte = 0; byte < LANE_BYTES; ++byte) {
                    output_keep_comb[stream * LANE_BYTES + byte] =
                        fifos[stream].keep_out()[byte];
                }
            }
        }
        return output_keep_comb;
    }

    logic<OUTPUT_BYTES> output_sop_comb;
    logic<OUTPUT_BYTES>& output_sop_comb_func()
    {
        size_t stream;
        output_sop_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            if ((bool)lane_valid_comb_func()[stream]
                && (bool)fifos[stream].sop_out()[0]) {
                output_sop_comb[stream * LANE_BYTES] = 1;
            }
        }
        return output_sop_comb;
    }

    logic<OUTPUT_BYTES> output_eop_comb;
    logic<OUTPUT_BYTES>& output_eop_comb_func()
    {
        size_t stream;
        size_t byte;
        uint32_t last_byte;
        output_eop_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            last_byte = 0;
            for (byte = 0; byte < LANE_BYTES; ++byte) {
                if ((bool)fifos[stream].keep_out()[byte]) last_byte = byte;
            }
            if ((bool)lane_valid_comb_func()[stream]
                && (bool)fifos[stream].eop_out()[0]) {
                output_eop_comb[stream * LANE_BYTES + last_byte] = 1;
            }
        }
        return output_eop_comb;
    }

    logic<STREAMS> tx_ready_comb;
    logic<STREAMS>& tx_ready_comb_func()
    {
        tx_ready_comb = 0;
        tx_ready_comb[0] = fifos[0].ready_out();
        tx_ready_comb[1] = fifos[1].ready_out();
        return tx_ready_comb;
    }

    logic<STREAMS> tx_almost_full_comb;
    logic<STREAMS>& tx_almost_full_comb_func()
    {
        tx_almost_full_comb = 0;
        tx_almost_full_comb[0] = fifos[0].almost_full_out();
        tx_almost_full_comb[1] = fifos[1].almost_full_out();
        return tx_almost_full_comb;
    }

    logic<STREAMS> tx_fifo_error_comb;
    logic<STREAMS>& tx_fifo_error_comb_func()
    {
        tx_fifo_error_comb = 0;
        tx_fifo_error_comb[0] = fifos[0].protocol_error_out();
        tx_fifo_error_comb[1] = fifos[1].protocol_error_out();
        return tx_fifo_error_comb;
    }

#define OUTPUT_MERGER_DECLARE_READ_COUNT(number) \
    u<4> read_count_##number##_comb; \
    u<4>& read_count_##number##_comb_func() \
    { \
        read_count_##number##_comb = (bool)ready_in()[number] \
            && (bool)lane_valid_comb_func()[number] ? 1 : 0; \
        return read_count_##number##_comb; \
    }
    OUTPUT_MERGER_FOR_EACH_STREAM(OUTPUT_MERGER_DECLARE_READ_COUNT)
#undef OUTPUT_MERGER_DECLARE_READ_COUNT

    bool error_comb;
    bool& error_comb_func()
    {
        error_comb = (uint64_t)tx_fifo_error_comb_func() != 0;
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
        for (stream = 0; stream < STREAMS; ++stream) {
            fifos[stream]._work(reset);
            if (reset) {
                ipg_cycles_reg[stream].clr();
            }
            else if ((bool)ready_in()[stream]
                && (bool)lane_valid_comb_func()[stream]
                && (bool)fifos[stream].eop_out()[0]) {
                ipg_cycles_reg[stream]._next = IPG_CYCLES;
            }
            else if ((bool)ready_in()[stream]
                && (uint32_t)ipg_cycles_reg[stream] != 0) {
                ipg_cycles_reg[stream]._next = ipg_cycles_reg[stream] - 1;
            }
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        size_t stream;
        for (stream = 0; stream < STREAMS; ++stream) {
            fifos[stream]._strobe();
            ipg_cycles_reg[stream].strobe();
        }
    }
#endif

    void _strobe()
    {
        size_t stream;
        for (stream = 0; stream < STREAMS; ++stream) {
            fifos[stream]._strobe();
            ipg_cycles_reg[stream].strobe();
        }
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class OutputMerger<64, 2048, 12>;

#undef OUTPUT_MERGER_FOR_EACH_STREAM
