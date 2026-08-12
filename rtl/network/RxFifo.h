#pragma once

// Eight-ingress packet-descriptor FIFO.  Each balanced receive stream has an
// independent storage FIFO, so all eight streams may complete a packet in the
// same clock.  A fair round-robin mux presents one descriptor output stream.

#include "PacketParser.h"
#include "../common/Fifo.cpp"
#include "../common/ClockDomains.h"

using namespace cpphdl;

enum RxDescriptorFlags : uint8_t
{
    RX_DESCRIPTOR_FLAG_RAW = 1u << 0
};

// The 32-byte descriptor header precedes the 128-byte packet view.  Parsed
// mode uses packet_word0.fields and leaves packet_word1 zero.  RAW mode stores
// the first 128 original packet bytes in the two packet words.
struct RxDescriptor
{
    u32 packet_address;
    u16 packet_length;
    u8 ingress_stream;
    u8 flags;
    logic<192> reserved;
    PacketParserWord packet_word0;
    PacketParserWord packet_word1;
} __PACKED;

union RxDescriptorWord
{
    RxDescriptor descriptor;
    logic<1280> raw;
} __PACKED;

using RxDescriptorInputBus = array<8, RxDescriptorWord, true>;

static_assert(sizeof(RxDescriptor) == 160,
    "RxDescriptor must occupy five 256-bit words");
static_assert(sizeof(RxDescriptorWord) == 160,
    "RxDescriptorWord must occupy five 256-bit words");

#define RX_FIFO_FOR_EACH_STREAM(M) \
    M(0) M(1) M(2) M(3) M(4) M(5) M(6) M(7)

template<size_t FIFO_DEPTH = 64>
class RxFifo : public Module
{
public:
    static constexpr size_t STREAMS = 8;
    static constexpr size_t DESCRIPTOR_BYTES = 160;
    static constexpr size_t DESCRIPTOR_BITS = DESCRIPTOR_BYTES * 8;

    _PORT(logic<STREAMS>) valid_in;
    _PORT(RxDescriptorInputBus) data_in;
    _PORT(logic<STREAMS>) ready_out;
    _PORT(logic<STREAMS>) almost_full_out;

    _PORT(bool) valid_out;
    _PORT(RxDescriptorWord) data_out;
    _PORT(bool) ready_in;
    _PORT(bool) clear_in;

private:
    Fifo<DESCRIPTOR_BYTES, FIFO_DEPTH, true, false> fifos[STREAMS];
    reg<u<3>> rr_reg;

    logic<STREAMS> input_ready_comb;
    logic<STREAMS> almost_full_comb;
    logic<STREAMS> fifo_read_comb;
#define RX_FIFO_DECLARE_INPUT_BITS(number) \
    logic<DESCRIPTOR_BITS> input_bits_##number##_comb; \
    logic<DESCRIPTOR_BITS>& input_bits_##number##_comb_func() \
    { \
        RxDescriptorWord word; \
        word = data_in()[number]; \
        input_bits_##number##_comb = word.raw; \
        return input_bits_##number##_comb; \
    }
    RX_FIFO_FOR_EACH_STREAM(RX_FIFO_DECLARE_INPUT_BITS)
#undef RX_FIFO_DECLARE_INPUT_BITS
    bool output_valid_comb;
    RxDescriptorWord output_data_comb;

    logic<STREAMS>& input_ready_comb_func()
    {
        uint32_t stream;
        input_ready_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            input_ready_comb[stream] = !fifos[stream].full_out();
        }
        return input_ready_comb;
    }

    logic<STREAMS>& almost_full_comb_func()
    {
        uint32_t stream;
        almost_full_comb = 0;
        for (stream = 0; stream < STREAMS; ++stream) {
            almost_full_comb[stream] = fifos[stream].afull_out();
        }
        return almost_full_comb;
    }

    uint32_t selected_stream_value()
    {
        uint32_t offset;
        uint32_t candidate;
        for (offset = 0; offset < STREAMS; ++offset) {
            candidate = ((uint32_t)rr_reg + offset) & 7;
            if (!fifos[candidate].empty_out()) {
                return candidate;
            }
        }
        return STREAMS;
    }

    bool& output_valid_comb_func()
    {
        output_valid_comb = selected_stream_value() < STREAMS;
        return output_valid_comb;
    }

    logic<STREAMS>& fifo_read_comb_func()
    {
        uint32_t selected;
        fifo_read_comb = 0;
        selected = selected_stream_value();
        if (selected < STREAMS && ready_in()) {
            fifo_read_comb[selected] = 1;
        }
        return fifo_read_comb;
    }

    RxDescriptorWord& output_data_comb_func()
    {
        uint32_t selected;
        output_data_comb.raw = 0;
        selected = selected_stream_value();
        if (selected < STREAMS) {
            output_data_comb.raw = fifos[selected].read_data_out();
        }
        return output_data_comb;
    }

public:
#ifndef SYNTHESIS
    uint32_t debug_total_descriptors() const
    {
        uint32_t total = 0;
        for (uint32_t stream = 0; stream < STREAMS; ++stream) {
            total += fifos[stream].debug_count();
        }
        return total;
    }
#endif

    void _assign()
    {
#define RX_FIFO_BIND_STREAM(number) \
        fifos[number].write_in = _ASSIGN((bool)valid_in()[number] \
            && (bool)input_ready_comb_func()[number]); \
        fifos[number].write_data_in = \
            _ASSIGN_COMB(input_bits_##number##_comb_func()); \
        fifos[number].read_in = _ASSIGN((bool)fifo_read_comb_func()[number]); \
        fifos[number].clear_in = clear_in; \
        fifos[number].__inst_name = __inst_name + "/stream" + std::to_string(number); \
        fifos[number]._assign();
        RX_FIFO_FOR_EACH_STREAM(RX_FIFO_BIND_STREAM)
#undef RX_FIFO_BIND_STREAM

        ready_out = _ASSIGN_COMB(input_ready_comb_func());
        almost_full_out = _ASSIGN_COMB(almost_full_comb_func());
        valid_out = _ASSIGN_COMB(output_valid_comb_func());
        data_out = _ASSIGN_COMB(output_data_comb_func());
    }

    void _work(bool reset)
    {
        uint32_t stream;
        uint32_t selected;
        if (reset) {
            rr_reg.clr();
            for (stream = 0; stream < STREAMS; ++stream) {
                fifos[stream]._work(true);
            }
            return;
        }
        for (stream = 0; stream < STREAMS; ++stream) {
            fifos[stream]._work(false);
        }
        selected = selected_stream_value();
        if (selected < STREAMS && ready_in()) {
            rr_reg._next = (selected + 1) & 7;
        }
    }

#ifdef SMARTNIC_TWO_CLOCKS
    void _strobe_net_clk()
    {
        uint32_t stream;
        for (stream = 0; stream < STREAMS; ++stream) {
            fifos[stream]._strobe();
        }
        rr_reg.strobe();
    }
#endif

    void _strobe()
    {
        uint32_t stream;
        for (stream = 0; stream < STREAMS; ++stream) fifos[stream]._strobe();
        rr_reg.strobe();
    }

    SMARTNIC_NETWORK_CLOCK_METHODS()
};

template class RxFifo<64>;

#undef RX_FIFO_FOR_EACH_STREAM
